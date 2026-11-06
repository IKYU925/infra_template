################################################################################
# EKS (관리형 Kubernetes)
################################################################################
# 클러스터 안에 올라가는 것(Ingress, cert-manager, External Secrets, 앱)은 Terraform 이 아니라
# Argo CD 가 deploy/ 폴더를 보고 설치한다. Terraform 은 AWS 리소스와 IAM 까지만 맡는다.

# 수업·실습용으로 API 엔드포인트를 공개하되 허용 IP(eks_public_access_cidrs)만 접속하게 한다.
# 보안팀 검토 후 private 전용(SSM 경유)으로 바꿀 수 있다.
# 노드는 ECR, AWS API, 패키지 저장소에 닿아야 해서 노드 SG 의 아웃바운드가 열려 있다 (NAT 경유).
# Trivy 예외 3건은 보안팀 검토 대상.
#trivy:ignore:AVD-AWS-0040
#trivy:ignore:AVD-AWS-0041
#trivy:ignore:AVD-AWS-0104
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = local.name
  kubernetes_version = var.eks_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.eks_public_access_cidrs
  endpoint_private_access      = true

  # Terraform 을 실행한 주체(GitHub Actions apply 역할)를 관리자로 등록한다.
  # 사람 관리자는 eks_admin_principal_arns 로 추가한다.
  enable_cluster_creator_admin_permissions = true
  access_entries = {
    for idx, arn in var.eks_admin_principal_arns : "admin-${idx}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # 컨트롤 플레인 로그 전부를 CloudWatch 로 보낸다 (보안 감사용)
  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = var.eks_log_retention_days

  addons = {
    coredns = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
      # NetworkPolicy 를 실제로 적용한다 (로컬 k3s 도 기본으로 적용된다)
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = module.ebs_csi_pod_identity.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size
    }
  }

  tags = local.tags
}

################################################################################
# Pod Identity (파드가 쓰는 AWS 권한. 장기 키 없음)
################################################################################
module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                      = "${local.name}-ebs-csi"
  attach_aws_ebs_csi_policy = true

  tags = local.tags
}

module "aws_lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                            = "${local.name}-aws-lbc"
  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }

  tags = local.tags
}

# External Secrets Operator 는 RDS 마스터 비밀번호 시크릿만 읽을 수 있다.
module "external_secrets_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                                  = "${local.name}-external-secrets"
  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = [module.db.db_instance_master_user_secret_arn]
  external_secrets_create_permission    = false

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }

  tags = local.tags
}

# 앱 파드(app 네임스페이스의 app 서비스 계정)는 아티팩트 버킷만 읽고 쓸 수 있다.
module "app_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name = "${local.name}-app"

  additional_policy_arns = {
    artifacts = module.app_s3_policy.arn
  }

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = var.app_namespace
      service_account = var.app_service_account
    }
  }

  tags = local.tags
}

module "app_s3_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "6.8.2"

  name        = "${local.name}-app-artifacts"
  description = "App pods: read/write the artifact bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = module.artifact_bucket.s3_bucket_arn
      },
      {
        Sid      = "ObjectRW"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${module.artifact_bucket.s3_bucket_arn}/*"
      },
      {
        Sid      = "KmsForBucket"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${data.aws_region.current.region}.amazonaws.com"
          }
        }
      },
    ]
  })

  tags = local.tags
}

################################################################################
# ECR (앱 이미지 저장소)
################################################################################
module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "3.2.1"

  repository_name                 = "${var.project}/app"
  repository_image_tag_mutability = "IMMUTABLE"
  repository_image_scan_on_push   = true
  repository_force_delete         = var.ecr_force_delete

  # 이미지를 올리는 CI 역할(앱 저장소의 GitHub Actions 등). EKS 노드는 노드 역할로 이미 pull 할 수 있다.
  repository_read_write_access_arns = var.ecr_push_principal_arns

  repository_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "최근 이미지 ${var.ecr_keep_images}개만 보관"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.ecr_keep_images
      }
      action = { type = "expire" }
    }]
  })

  tags = local.tags
}
