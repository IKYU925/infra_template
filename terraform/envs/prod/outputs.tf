output "vpc_id" {
  description = "VPC ID"
  value       = module.platform.vpc_id
}

output "cluster_name" {
  description = "EKS 클러스터 이름"
  value       = module.platform.cluster_name
}

output "configure_kubectl" {
  description = "kubectl 연결 명령"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.platform.cluster_name}"
}

output "ecr_repository_url" {
  description = "앱 이미지 ECR 주소"
  value       = module.platform.ecr_repository_url
}

output "artifact_bucket_name" {
  description = "아티팩트 버킷"
  value       = module.platform.artifact_bucket_name
}

output "db_address" {
  description = "RDS 호스트 이름"
  value       = module.platform.db_address
}

output "db_master_secret_arn" {
  description = "RDS 마스터 비밀번호 Secrets Manager ARN"
  value       = module.platform.db_master_secret_arn
}
