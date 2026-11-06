# 하나의 환경(dev/prod)을 구성하는 표준 스택: VPC + EKS + RDS + S3 + ECR.
# 모든 리소스는 검증된 terraform-aws-modules 모듈을 버전 고정해서 사용한다.
# 버전 업데이트는 .github/dependabot.yml 이 PR 로 올려준다.

data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:az_count 만큼 앞에서부터 잘라 쓰므로 AZ 가 추가돼도 기존 서브넷 배치는 바뀌지 않는다
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  name = "${var.project}-${var.environment}"
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /16 기준: public 10.x.0-9.0/24, private 10.x.10-19.0/24, database 10.x.20-29.0/24
  public_subnets   = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  database_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 20)]

  tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
  })
}

################################################################################
# VPC
################################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets   = local.public_subnets
  private_subnets  = local.private_subnets
  database_subnets = local.database_subnets

  # AWS Load Balancer Controller 가 이 태그로 NLB/ALB 를 놓을 서브넷을 찾는다
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  create_database_subnet_group = true

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  # 기본 SG 는 모든 트래픽을 막아 둔다 (CIS 권고)
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  enable_flow_log                                 = var.enable_flow_log
  create_flow_log_cloudwatch_log_group            = var.enable_flow_log
  create_flow_log_cloudwatch_iam_role             = var.enable_flow_log
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_retention_days
  flow_log_max_aggregation_interval               = 60

  tags = local.tags
}

################################################################################
# Security Group (RDS)
################################################################################
# VPC CNI 기본 설정에서 파드는 노드의 보안 그룹을 쓴다. 그래서 노드 SG 에서 오는 5432 만 연다.
module "db_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  name        = "${local.name}-db"
  description = "PostgreSQL only from EKS nodes"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    postgres = {
      description                  = "PostgreSQL from EKS node SG"
      from_port                    = 5432
      to_port                      = 5432
      referenced_security_group_id = module.eks.node_security_group_id
    }
  }

  tags = local.tags
}

################################################################################
# S3 (앱 아티팩트)
################################################################################
module "artifact_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.17.0"

  bucket        = "${local.name}-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.artifact_bucket_force_destroy

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "aws:kms"
      }
      bucket_key_enabled = true
    }
  }

  lifecycle_rule = [
    {
      id      = "noncurrent-cleanup"
      enabled = true
      filter  = {}
      noncurrent_version_expiration = {
        days = var.artifact_noncurrent_expiration_days
      }
      abort_incomplete_multipart_upload_days = 7
    }
  ]

  tags = local.tags
}

################################################################################
# RDS (PostgreSQL)
################################################################################
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "7.2.2"

  identifier = "${local.name}-postgres"

  engine               = "postgres"
  engine_version       = var.db_engine_version
  family               = "postgres${var.db_engine_version}"
  major_engine_version = var.db_engine_version
  instance_class       = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  port     = 5432

  # 마스터 비밀번호는 Secrets Manager 에서 생성·관리 (state 에 평문 저장 안 함)
  manage_master_user_password         = true
  iam_database_authentication_enabled = true

  multi_az               = var.db_multi_az
  create_db_subnet_group = false
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [module.db_sg.id]
  publicly_accessible    = false

  backup_retention_period = var.db_backup_retention_days
  backup_window           = "17:00-18:00" # KST 02:00-03:00
  maintenance_window      = "Sun:18:00-Sun:19:00"

  deletion_protection              = var.db_deletion_protection
  skip_final_snapshot              = !var.db_deletion_protection
  final_snapshot_identifier_prefix = "${local.name}-final"
  copy_tags_to_snapshot            = true
  auto_minor_version_upgrade       = true

  performance_insights_enabled    = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = true

  parameters = [
    { name = "rds.force_ssl", value = "1" },
    { name = "log_min_duration_statement", value = "1000" },
  ]

  tags = local.tags
}
