output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록"
  value       = module.vpc.private_subnets
}

output "app_instance_ids" {
  description = "앱 EC2 인스턴스 ID (Ansible SSM 접속 대상)"
  value       = { for k, m in module.app : k => m.id }
}

output "app_security_group_id" {
  description = "앱 보안 그룹 ID"
  value       = module.app_sg.id
}

output "artifact_bucket_name" {
  description = "아티팩트 버킷 이름 (Ansible 의 ansible_aws_ssm_bucket_name 에 사용)"
  value       = module.artifact_bucket.s3_bucket_id
}

output "db_endpoint" {
  description = "RDS 엔드포인트"
  value       = module.db.db_instance_endpoint
}

output "db_master_secret_arn" {
  description = "RDS 마스터 비밀번호가 저장된 Secrets Manager ARN"
  value       = module.db.db_instance_master_user_secret_arn
}
