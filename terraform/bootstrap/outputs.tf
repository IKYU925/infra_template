output "state_bucket" {
  description = "envs/<env>/backend.hcl 의 bucket 값"
  value       = module.state_bucket.s3_bucket_id
}

output "lock_table" {
  description = "envs/<env>/backend.hcl 의 dynamodb_table 값"
  value       = module.lock_table.dynamodb_table_id
}

output "plan_role_arn" {
  description = "GitHub Environment 변수 AWS_PLAN_ROLE_ARN 에 넣을 값"
  value       = module.plan_role.arn
}

output "apply_role_arn" {
  description = "GitHub Environment 변수 AWS_APPLY_ROLE_ARN 에 넣을 값"
  value       = module.apply_role.arn
}
