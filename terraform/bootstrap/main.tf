# 계정마다 한 번만 적용하는 기반 리소스:
#  1) Terraform 원격 state 버킷 (S3)
#  2) state 잠금 테이블 (DynamoDB)
#  3) GitHub Actions 용 OIDC 공급자 + plan(읽기 전용) / apply 역할

data "aws_caller_identity" "current" {}

locals {
  name          = "${var.project}-${var.account_alias}"
  state_bucket  = "${local.name}-tfstate-${data.aws_caller_identity.current.account_id}"
  lock_table    = "${local.name}-tflock"
  oidc_provider = "token.actions.githubusercontent.com"
}

module "state_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.17.0"

  bucket = local.state_bucket

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
      id      = "state-history"
      enabled = true
      filter  = {}
      noncurrent_version_expiration = {
        days = 90
      }
      abort_incomplete_multipart_upload_days = 7
    }
  ]
}

module "lock_table" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "5.5.2"

  name         = local.lock_table
  hash_key     = "LockID"
  billing_mode = "PAY_PER_REQUEST"

  attributes = [
    { name = "LockID", type = "S" }
  ]

  point_in_time_recovery_enabled = true
  server_side_encryption_enabled = true
  deletion_protection_enabled    = true
}

################################################################################
# GitHub Actions OIDC (장기 액세스 키 없이 CI 에서 AWS 접근)
################################################################################
module "github_oidc" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-oidc-provider"
  version = "6.8.2"

  create = var.create_github_oidc_provider
  url    = "https://${local.oidc_provider}"
}

module "state_access_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "6.8.2"

  name        = "${local.name}-tfstate-access"
  description = "Read/write Terraform state and lock table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = module.state_bucket.s3_bucket_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${module.state_bucket.s3_bucket_arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
        Resource = module.lock_table.dynamodb_table_arn
      },
    ]
  })
}

# PR 에서 terraform plan 만 돌리는 읽기 전용 역할 (모든 브랜치/PR 허용)
module "plan_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name = "${local.name}-gha-plan"

  enable_github_oidc = true
  oidc_subjects = [
    "repo:${var.github_repository}:pull_request",
    "repo:${var.github_repository}:ref:refs/heads/*",
  ]

  policies = {
    read_only    = "arn:aws:iam::aws:policy/ReadOnlyAccess"
    state_access = module.state_access_policy.arn
  }

  depends_on = [module.github_oidc]
}

# apply 역할은 GitHub Environment(승인 규칙이 걸린)에서만 assume 가능
module "apply_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name = "${local.name}-gha-apply"

  enable_github_oidc = true
  oidc_subjects = [
    "repo:${var.github_repository}:environment:${var.account_alias}",
  ]

  policies = merge(var.apply_role_policy_arns, {
    state_access = module.state_access_policy.arn
  })

  depends_on = [module.github_oidc]
}
