# AI_auto_pipeline 4단계(plan.md 10) 실습 환경.
# EC2 1대의 지표와 로그로 CloudWatch 경보를 만들고, 경보 상태 변경을 EventBridge -> SQS 로 넘긴다.
# 로컬 자동화가 SQS 를 가져가므로 공개 주소가 필요 없다. NAT, 로드밸런서, RDS 는 만들지 않는다.

data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:첫 번째 AZ 하나만 쓰는 일회성 실습 환경이다
  state = "available"
}

locals {
  error_metric_name = "${var.service}ErrorCount"

  # 경보 이름은 <tenant>-<service>-<alertname> (plan.md 10-2). 자동화의 SQS 어댑터가 이 이름에서 고객사와 서비스를 읽는다.
  # EventBridge 규칙도 이 표의 경보만 받는다.
  alarms = {
    ErrorLogs = {
      description         = "${var.service} 로그에 ERROR 가 찍힘"
      namespace           = "AiIncident"
      metric_name         = local.error_metric_name
      dimensions          = {}
      statistic           = "Sum"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = 1
      period              = 60
      evaluation_periods  = 1
      treat_missing_data  = "notBreaching"
    }
    DiskUsageHigh = {
      description = "루트 디스크 사용률이 ${var.disk_alarm_threshold}% 이상"
      namespace   = "CWAgent"
      metric_name = "disk_used_percent"
      # CloudWatch Agent 설정(aws_ssm_parameter.cw_agent)의 append_dimensions, drop_device 와 맞아야 지표가 잡힌다
      dimensions = {
        InstanceId = module.ec2.id
        path       = "/"
        fstype     = "xfs"
      }
      statistic           = "Maximum"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = var.disk_alarm_threshold
      period              = 60
      evaluation_periods  = 2
      treat_missing_data  = "missing"
    }
  }
}

################################################################################
# VPC (퍼블릭 서브넷 1개, NAT 없음)
################################################################################
# Flow Log 는 비용 때문에 끈다. 인바운드가 없는 일회성 실습 환경이라 분석할 트래픽이 없다.
# NAT 가 없으므로 인스턴스는 퍼블릭 IP 로 IGW 를 거쳐 SSM, ECR, CloudWatch 에 나간다. 인바운드는 SG 가 막는다.
#trivy:ignore:AVD-AWS-0178
#trivy:ignore:AVD-AWS-0164
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = var.name
  cidr = var.vpc_cidr
  azs  = [data.aws_availability_zones.available.names[0]]

  public_subnets = [cidrsubnet(var.vpc_cidr, 8, 0)]

  map_public_ip_on_launch = true

  enable_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  # 기본 SG 는 모든 트래픽을 막아 둔다 (CIS 권고)
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []
}

################################################################################
# Security Group (인바운드 없음, 443 아웃바운드만)
################################################################################
# SSM, ECR, CloudWatch, dnf 저장소가 모두 인터넷의 443 이다. NAT 가 없어 대상 CIDR 을 좁힐 수 없다.
#trivy:ignore:AVD-AWS-0104
module "sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  name        = var.name
  description = "No inbound (SSM only). HTTPS out only."
  vpc_id      = module.vpc.vpc_id

  egress_rules = {
    https = {
      description = "HTTPS to internet via IGW (SSM, ECR, CloudWatch, dnf)"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
}

################################################################################
# EC2 (Docker + CloudWatch Agent, 앱은 lab.sh deploy 로 띄운다)
################################################################################
resource "aws_ssm_parameter" "cw_agent" {
  #checkov:skip=CKV2_AWS_34:비밀이 아닌 CloudWatch Agent 설정이다
  # CloudWatchAgentServerPolicy 는 AmazonCloudWatch- 로 시작하는 파라미터만 읽을 수 있다
  name = "AmazonCloudWatch-${var.name}"
  type = "String"
  value = jsonencode({
    metrics = {
      append_dimensions = {
        InstanceId = "$${aws:InstanceId}"
      }
      metrics_collected = {
        disk = {
          measurement                 = ["used_percent"]
          resources                   = ["/"]
          drop_device                 = true
          metrics_collection_interval = 60
        }
      }
    }
  })
}

module "ec2" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "6.4.1"

  name = var.name

  # 앱 이미지가 linux/arm64 로 빌드된다 (AI_auto_pipeline scripts/build_push.sh)
  ami_ssm_parameter  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
  ignore_ami_changes = true
  instance_type      = var.instance_type
  subnet_id          = module.vpc.public_subnets[0]

  # NAT 없이 IGW 로 나가려면 퍼블릭 IP 가 필요하다. 인바운드는 SG 가 막는다
  associate_public_ip_address = true

  create_security_group  = false
  vpc_security_group_ids = [module.sg.id]

  # SSH 키 없이 SSM Session Manager 로만 접속
  create_iam_instance_profile = true
  iam_role_name               = "${var.name}-instance"
  iam_role_use_name_prefix    = false
  iam_role_description        = "aiops-lab instance (SSM, CloudWatch Agent, ECR pull)"
  iam_role_policies = {
    ssm      = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    cw_agent = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    ecr      = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  }

  # 이미지를 바꿔도 인스턴스가 교체되지 않도록 앱은 user_data 가 아니라 lab.sh deploy 로 띄운다
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    cw_agent_parameter = aws_ssm_parameter.cw_agent.name
  })

  # IMDSv2 강제
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  ebs_optimized = true

  root_block_device = {
    encrypted = true
    type      = "gp3"
    size      = var.root_volume_size
  }
}

################################################################################
# ECR (앱 이미지)
################################################################################
resource "aws_ecr_repository" "app" {
  #checkov:skip=CKV_AWS_136:일회성 실습이라 KMS 키 비용을 들이지 않는다. 기본 AES256 암호화는 켜져 있다
  name                 = "${var.name}/${var.service}"
  image_tag_mutability = "IMMUTABLE"
  # destroy 가 이미지가 남은 저장소까지 지워야 과금 리소스가 0개가 된다
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

################################################################################
# CloudWatch (앱 로그, ERROR 지표 필터, 경보)
################################################################################
resource "aws_cloudwatch_log_group" "app" {
  #checkov:skip=CKV_AWS_158:일회성 실습이라 KMS 키 비용을 들이지 않는다
  #checkov:skip=CKV_AWS_338:가짜 데이터만 쓰는 실습 로그라 오래 둘 이유가 없다
  name              = "/ai-incident/${var.service}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_metric_filter" "errors" {
  name           = "${var.service}-errors"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "\"ERROR\""

  metric_transformation {
    namespace = local.alarms.ErrorLogs.namespace
    name      = local.error_metric_name
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${var.tenant}-${var.service}-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  dimensions          = each.value.dimensions
  statistic           = each.value.statistic
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  treat_missing_data  = each.value.treat_missing_data
}

################################################################################
# 경보 상태 변경 -> EventBridge -> SQS
################################################################################
resource "aws_sqs_queue" "alarms" {
  name                       = "${var.name}-alarms"
  sqs_managed_sse_enabled    = true
  message_retention_seconds  = 4 * 24 * 60 * 60
  visibility_timeout_seconds = 300
}

resource "aws_cloudwatch_event_rule" "alarms" {
  name        = "${var.name}-alarm-state-change"
  description = "aiops-lab alarm state changes to SQS"

  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    resources     = [for a in aws_cloudwatch_metric_alarm.this : a.arn]
  })
}

resource "aws_cloudwatch_event_target" "alarms" {
  rule = aws_cloudwatch_event_rule.alarms.name
  arn  = aws_sqs_queue.alarms.arn
}

resource "aws_sqs_queue_policy" "alarms" {
  queue_url = aws_sqs_queue.alarms.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EventBridgeSend"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.alarms.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.alarms.arn }
        }
      },
    ]
  })
}

################################################################################
# IAM 사용자 (로컬 자동화: SQS 읽기·삭제, Logs Insights 조회)
################################################################################
# 액세스 키는 state 에 비밀이 남지 않도록 Terraform 밖에서 만든다 (docs/aiops-lab.md)
resource "aws_iam_user" "automation" {
  #checkov:skip=CKV_AWS_273:로컬 K3s 의 자동화가 쓸 장기 키가 필요하다 (plan.md 10-1). 실습 후 키와 함께 지운다
  name = "${var.name}-automation"
  # 콘솔 등에서 만든 액세스 키가 남아 있어도 destroy 가 막히지 않게 한다
  force_destroy = true
}

resource "aws_iam_user_policy" "automation" {
  #checkov:skip=CKV_AWS_40:사용자 1명, 정책 1개뿐인 실습 환경이라 그룹을 따로 두지 않는다
  name = "${var.name}-automation"
  user = aws_iam_user.automation.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ConsumeAlarms"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueAttributes",
        ]
        Resource = aws_sqs_queue.alarms.arn
      },
      {
        Sid      = "ReadAppLogs"
        Effect   = "Allow"
        Action   = ["logs:StartQuery", "logs:FilterLogEvents", "logs:GetLogEvents"]
        Resource = [aws_cloudwatch_log_group.app.arn, "${aws_cloudwatch_log_group.app.arn}:*"]
      },
      {
        # 쿼리 ID 로 동작하는 API 라 리소스 수준 권한이 없다
        Sid      = "QueryResults"
        Effect   = "Allow"
        Action   = ["logs:GetQueryResults", "logs:StopQuery"]
        Resource = "*"
      },
    ]
  })
}

################################################################################
# 예산 알림
################################################################################
resource "aws_budgets_budget" "monthly" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}
