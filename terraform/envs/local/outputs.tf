output "artifact_bucket_name" {
  description = "로컬 아티팩트 버킷"
  value       = module.artifact_bucket.s3_bucket_id
}

output "db_secret_arn" {
  description = "로컬 DB 접속 정보 시크릿"
  value       = aws_secretsmanager_secret.db.arn
}
