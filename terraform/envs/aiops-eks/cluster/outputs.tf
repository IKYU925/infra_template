# 이름은 AI_auto_pipeline 과의 계약이다. 바꾸면 양쪽을 함께 바꾼다
output "cluster_name" {
  value = module.eks.cluster_name
}

output "region" {
  value = var.region
}

output "account_id" {
  value = local.base.account_id
}

output "ecr_repository_url" {
  value = local.base.ecr_repository_url
}

output "loki_bucket_name" {
  value = local.base.loki_bucket_name
}

output "aiops_secret_name" {
  value = local.base.aiops_secret_name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
