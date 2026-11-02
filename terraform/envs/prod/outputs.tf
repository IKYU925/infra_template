output "vpc_id" {
  description = "VPC ID"
  value       = module.platform.vpc_id
}

output "app_instance_ids" {
  description = "앱 EC2 인스턴스 ID"
  value       = module.platform.app_instance_ids
}

output "artifact_bucket_name" {
  description = "아티팩트 버킷 (Ansible group_vars 의 ansible_aws_ssm_bucket_name 에 넣는다)"
  value       = module.platform.artifact_bucket_name
}

output "db_endpoint" {
  description = "RDS 엔드포인트"
  value       = module.platform.db_endpoint
}

output "db_master_secret_arn" {
  description = "RDS 마스터 비밀번호 Secrets Manager ARN"
  value       = module.platform.db_master_secret_arn
}
