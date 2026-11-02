# prod: 가용성·보호 우선. AZ별 NAT, Multi-AZ DB, 삭제 보호 켜짐.
project             = "myproject"
environment         = "prod"
region              = "ap-northeast-2"
allowed_account_ids = ["222222222222"] # TODO: prod 계정 ID (dev 와 분리 권장)

vpc_cidr           = "10.20.0.0/16"
az_count           = 3
single_nat_gateway = false

flow_log_retention_days = 365

app_instance_count = 2
app_instance_type  = "t3.medium"

db_instance_class        = "db.t4g.medium"
db_allocated_storage     = 50
db_max_allocated_storage = 500
db_multi_az              = true
db_backup_retention_days = 30
db_deletion_protection   = true

artifact_bucket_force_destroy = false
