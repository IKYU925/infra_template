output "vpc_id" {
  description = "VPC ID (deploy/argocd 의 aws-load-balancer-controller 값에 넣는다)"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록"
  value       = module.vpc.private_subnets
}

output "cluster_name" {
  description = "EKS 클러스터 이름"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API 엔드포인트"
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "앱 이미지 ECR 주소 (deploy/charts/app/values-<env>.yaml 의 image.repository)"
  value       = module.ecr.repository_url
}

output "artifact_bucket_name" {
  description = "아티팩트 버킷 이름"
  value       = module.artifact_bucket.s3_bucket_id
}

output "db_endpoint" {
  description = "RDS 엔드포인트 (host:port)"
  value       = module.db.db_instance_endpoint
}

output "db_address" {
  description = "RDS 호스트 이름 (deploy/charts/app/values-<env>.yaml 의 externalDatabase.host)"
  value       = module.db.db_instance_address
}

output "db_master_secret_arn" {
  description = "RDS 마스터 비밀번호가 저장된 Secrets Manager ARN (External Secrets 가 읽는다)"
  value       = module.db.db_instance_master_user_secret_arn
}
