# aiops-eks cluster 층: 코어타임에만 띄우는 리소스. 과금의 대부분이 여기 있다.
# VPC, NAT, EKS, 노드그룹 2개, 애드온, Pod Identity 연결, ArgoCD 와 루트 앱까지 만든다.
# 클러스터 안의 나머지(StorageClass, External Secrets, 관측, 앱)는 AI_auto_pipeline 이 ArgoCD 로 만든다.

data "terraform_remote_state" "base" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "envs/aiops-eks/base/terraform.tfstate"
    region = var.region
  }
}

data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:앞의 두 AZ 만 쓰고 매일 새로 만드는 VPC 라 AZ 가 늘어도 영향이 없다
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  base = data.terraform_remote_state.base.outputs

  # apply 하는 주체는 enable_cluster_creator_admin_permissions 로 이미 관리자다. 같은 주체로 항목을 또 만들면 충돌한다
  admins = [for arn in var.admin_principal_arns : arn if arn != data.aws_iam_session_context.current.issuer_arn]

  # 로컬 K3s 와 같은 노드 라벨. AI_auto_pipeline 매니페스트가 nodeSelector workload=<키> 를 쓴다
  node_groups = ["app", "monitoring"]
}

################################################################################
# VPC (프라이빗 노드, NAT 1개)
################################################################################
# Flow Log 는 비용 때문에 끈다. 매일 지우는 실습 VPC 이고 인바운드가 없다.
#trivy:ignore:AVD-AWS-0178
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = var.name
  cidr = var.vpc_cidr
  # EKS 컨트롤 플레인은 서로 다른 AZ 의 서브넷 2개를 요구한다. 노드는 첫 번째 AZ 에만 둔다
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  private_subnets = [cidrsubnet(var.vpc_cidr, 4, 0), cidrsubnet(var.vpc_cidr, 4, 1)]
  public_subnets  = [cidrsubnet(var.vpc_cidr, 8, 200), cidrsubnet(var.vpc_cidr, 8, 201)]

  # NAT 는 첫 번째 AZ 에 하나. AZ 장애 시 egress 가 끊기는 것을 감수한다 (설계 3.1)
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []
}

################################################################################
# EKS
################################################################################
# 컨트롤 플레인 로그(CloudWatch)와 고객 관리 KMS 키는 끈다. 매일 지우는 클러스터라 로그 그룹과
# 삭제 대기 KMS 키만 쌓인다. 쿠버네티스 API 데이터는 EKS 기본 봉투 암호화(AWS 소유 키)로 암호화된다.
# 노드 보안 그룹의 전체 egress 는 그대로 둔다. NAT 를 거쳐 ECR, Helm 차트 저장소, GitHub 에 나가야 하고 대상이 바뀐다.
#trivy:ignore:AVD-AWS-0038
#trivy:ignore:AVD-AWS-0039
#trivy:ignore:AVD-AWS-0040
#trivy:ignore:AVD-AWS-0041
#trivy:ignore:AVD-AWS-0104
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version
  # 표준 지원이 끝나면 연장 지원 요금(시간당 5배) 대신 자동 업그레이드된다
  upgrade_policy = { support_type = "STANDARD" }

  # 공개 엔드포인트는 허용 IP 만 받는다. 실행하는 곳(맥, GitHub 러너)의 IP 는 eks.sh 가 caller_cidr 로 넘긴다
  endpoint_public_access       = true
  endpoint_private_access      = true
  endpoint_public_access_cidrs = distinct(concat(var.endpoint_allowed_cidrs, [var.caller_cidr]))

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  create_kms_key              = false
  encryption_config           = null
  create_cloudwatch_log_group = false
  enabled_log_types           = []

  enable_cluster_creator_admin_permissions = true
  access_entries = {
    for i, arn in local.admins : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  addons = {
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    coredns                = {}
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = local.base.ebs_csi_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
      # PVC 로 생긴 EBS 볼륨에도 태그를 붙여 eks.sh leftovers 가 찾게 한다
      configuration_values = jsonencode({
        controller = {
          k8sTagClusterId = var.name
          extraVolumeTags = { Project = "ai-incident", Layer = "cluster" }
        }
      })
    }
  }

  # PVC(EBS)가 AZ 에 묶이므로 노드그룹마다 서브넷 하나에 고정한다. 둘 다 NAT 와 같은 AZ 라 AZ 간 전송 요금이 없다
  eks_managed_node_groups = {
    for k in local.node_groups : k => {
      ami_type       = "AL2023_ARM_64_STANDARD"
      instance_types = [var.node_instance_type]
      subnet_ids     = [module.vpc.private_subnets[0]]
      min_size       = 1
      max_size       = 1
      desired_size   = 1
      labels         = { workload = k }
      # 노드 장애 실험(S16)이 노드그룹을 이름(app, monitoring)으로 찾는다. 매일 새로 만들어 교체 충돌이 없다
      use_name_prefix = false
      # 매일 새로 만드는 노드그룹이라 EKS 가 그때의 최신 AMI 를 고른다. SSM 조회로 버전을 고정할 필요가 없다
      use_latest_ami_release_version = false
    }
  }
}

resource "aws_eks_pod_identity_association" "workload" {
  for_each = local.base.workload_identities

  cluster_name    = module.eks.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = each.value.role_arn
}

################################################################################
# ArgoCD 와 루트 앱 (그 아래는 AI_auto_pipeline deploy/argocd 가 관리)
################################################################################
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.17.2"

  # 접속은 kubectl port-forward. LoadBalancer 를 만들지 않는다
  values = [yamlencode({
    dex           = { enabled = false }
    notifications = { enabled = false }
    server        = { service = { type = "ClusterIP" } }
  })]

  # 노드가 떠야 ArgoCD Pod 가 뜬다
  depends_on = [module.eks]
}

resource "helm_release" "root_app" {
  name       = "aiops-root"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.8"

  values = [yamlencode({
    applications = {
      aiops-root = {
        namespace = "argocd"
        # eks.sh down 이 루트 앱을 지우면 하위 앱과 리소스까지 지워지게 한다
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        project    = "default"
        source = {
          repoURL        = "https://github.com/IKYU925/AI_auto_pipeline.git"
          path           = "deploy/argocd"
          targetRevision = var.argocd_root_revision
          helm = {
            valuesObject = merge({
              targetRevision   = var.argocd_root_revision
              region           = var.region
              ecrRepositoryUrl = local.base.ecr_repository_url
              lokiBucket       = local.base.loki_bucket_name
            }, var.image_tag == "" ? {} : { imageTag = var.image_tag })
          }
        }
        destination = { server = "https://kubernetes.default.svc", namespace = "argocd" }
        syncPolicy  = { automated = { prune = true, selfHeal = true } }
      }
    }
  })]

  depends_on = [helm_release.argocd, aws_eks_pod_identity_association.workload]
}
