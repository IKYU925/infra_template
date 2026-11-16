output "region" {
  value = var.region
}

output "account_id" {
  value = local.account_id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.aiops.repository_url
}

output "loki_bucket_name" {
  value = aws_s3_bucket.loki.bucket
}

output "aiops_secret_name" {
  value = aws_secretsmanager_secret.aiops.name
}

output "workload_identities" {
  description = "cluster 층이 만들 Pod Identity 연결: 키 => namespace, 서비스 계정, 역할 ARN"
  value = {
    for k, v in local.workload_identities : k => {
      namespace       = v.namespace
      service_account = v.service_account
      role_arn        = aws_iam_role.workload[k].arn
    }
  }
}

output "ebs_csi_role_arn" {
  value = aws_iam_role.ebs_csi.arn
}
