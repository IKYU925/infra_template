# aiops-eks base 층: 프로젝트 기간 내내 남기는 리소스. 시간당 과금이 거의 없다.
# 매일 만들고 지우는 클러스터는 ../cluster 다. 이 층의 output 을 terraform_remote_state 로 읽는다.
# 이름(ECR aiops, 비밀 ai-incident/aiops, 서비스 계정)은 AI_auto_pipeline P2 매니페스트와의 계약이라 바꾸려면 양쪽을 함께 바꾼다.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  secret_name = "ai-incident/aiops"

  # ArgoCD 가 설치하는 워크로드의 Pod Identity. cluster 층이 이 표대로 연결(association)을 만든다
  workload_identities = {
    external-secrets = {
      namespace       = "external-secrets"
      service_account = "external-secrets"
      statements = [
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = "arn:${data.aws_partition.current.partition}:secretsmanager:${var.region}:${local.account_id}:secret:ai-incident/*"
        },
      ]
    }
    loki = {
      namespace       = "monitoring"
      service_account = "loki"
      statements = [
        {
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = aws_s3_bucket.loki.arn
        },
        {
          # 컴팩터가 보존 기간이 지난 청크를 지운다
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          Resource = "${aws_s3_bucket.loki.arn}/*"
        },
      ]
    }
  }
}

################################################################################
# ECR (api, worker, shopapi 가 같이 쓰는 이미지)
################################################################################
resource "aws_ecr_repository" "aiops" {
  #checkov:skip=CKV_AWS_136:실습 이미지라 KMS 키 비용을 들이지 않는다. 기본 AES256 암호화는 켜져 있다
  name = "aiops"
  # 같은 태그 재푸시로 다른 이미지가 배포되는 것을 저장소 수준에서 막는다
  image_tag_mutability = "IMMUTABLE"
  # 프로젝트 종료 시 이미지가 남아 있어도 destroy 로 0개가 되게 한다
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

################################################################################
# Loki 저장소 (S3)
################################################################################
#trivy:ignore:AVD-AWS-0089
#trivy:ignore:AVD-AWS-0090
#trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket" "loki" {
  #checkov:skip=CKV_AWS_18:가짜 데이터의 로그 청크라 접근 로그를 남길 이유가 없다
  #checkov:skip=CKV_AWS_21:Loki 가 객체를 직접 관리하고 7일 뒤 지운다. 버전 관리는 지운 객체만 쌓는다
  #checkov:skip=CKV_AWS_144:실습 로그라 교차 리전 복제를 하지 않는다
  #checkov:skip=CKV_AWS_145:실습 로그라 KMS 키 비용을 들이지 않는다. 기본 SSE-S3 는 켜져 있다
  #checkov:skip=CKV2_AWS_62:이벤트 알림을 받을 소비자가 없다
  bucket = "ai-incident-loki-${local.account_id}"
  # 프로젝트 종료 시 로그가 남아 있어도 destroy 로 0개가 되게 한다
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket = aws_s3_bucket.loki.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    id     = "expire"
    status = "Enabled"
    filter {}

    expiration {
      days = var.loki_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

################################################################################
# Secrets Manager (값은 eks.sh secrets 가 넣는다. state 에 비밀값을 남기지 않는다)
################################################################################
resource "aws_secretsmanager_secret" "aiops" {
  #checkov:skip=CKV_AWS_149:실습 비밀이라 KMS 키 비용을 들이지 않는다. 기본 aws/secretsmanager 키로 암호화된다
  #checkov:skip=CKV2_AWS_57:외부 API 키라 AWS 가 회전할 수 없다
  name = local.secret_name
  # 지운 직후 같은 이름으로 다시 만들 수 있게 복구 대기 기간을 두지 않는다
  recovery_window_in_days = 0
}

################################################################################
# Pod Identity 역할 (연결은 cluster 층)
################################################################################
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "workload" {
  for_each = local.workload_identities

  name               = "ai-incident-${each.key}"
  description        = "Pod Identity for ${each.value.namespace}/${each.value.service_account}"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy" "workload" {
  for_each = local.workload_identities

  name   = each.key
  role   = aws_iam_role.workload[each.key].id
  policy = jsonencode({ Version = "2012-10-17", Statement = each.value.statements })
}

resource "aws_iam_role" "ebs_csi" {
  name               = "ai-incident-ebs-csi"
  description        = "Pod Identity for kube-system/ebs-csi-controller-sa (EBS CSI add-on)"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

################################################################################
# 예산 알림 (계정 전체, 할인·차감 전 금액)
################################################################################
resource "aws_budgets_budget" "monthly" {
  name         = "ai-incident-monthly"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"

  cost_types {
    include_credit   = false
    include_discount = false
    include_refund   = false
  }

  dynamic "notification" {
    for_each = { actual-50 = ["ACTUAL", 50], actual-80 = ["ACTUAL", 80], actual-100 = ["ACTUAL", 100], forecast-100 = ["FORECASTED", 100] }
    content {
      notification_type          = notification.value[0]
      threshold                  = notification.value[1]
      threshold_type             = "PERCENTAGE"
      comparison_operator        = "GREATER_THAN"
      subscriber_email_addresses = [var.budget_email]
    }
  }
}
