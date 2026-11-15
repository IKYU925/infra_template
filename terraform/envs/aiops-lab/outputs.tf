output "region" {
  description = "AWS 리전 (자동화의 AWS_REGION)"
  value       = var.region
}

output "service" {
  description = "대상 서비스 이름 (lab.sh deploy 의 컨테이너 이름, 로그 스트림)"
  value       = var.service
}

output "instance_id" {
  description = "EC2 인스턴스 ID (SSM 접속, lab.sh deploy 대상)"
  value       = module.ec2.id
}

output "ecr_repository_url" {
  description = "앱 이미지를 push 할 ECR 저장소"
  value       = aws_ecr_repository.app.repository_url
}

output "sqs_queue_url" {
  description = "경보 상태 변경이 쌓이는 SQS (자동화의 AIOPS_SQS_QUEUE_URL)"
  value       = aws_sqs_queue.alarms.url
}

output "sqs_queue_arn" {
  description = "경보 SQS ARN"
  value       = aws_sqs_queue.alarms.arn
}

output "log_group_name" {
  description = "앱 로그 그룹 (자동화의 AIOPS_LOG_GROUP)"
  value       = aws_cloudwatch_log_group.app.name
}

output "alarm_names" {
  description = "alertname -> CloudWatch 경보 이름"
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.alarm_name }
}

output "automation_user_name" {
  description = "로컬 자동화용 IAM 사용자 (액세스 키는 따로 만든다)"
  value       = aws_iam_user.automation.name
}

output "cw_agent_parameter_name" {
  description = "CloudWatch Agent 설정 SSM 파라미터"
  value       = aws_ssm_parameter.cw_agent.name
}
