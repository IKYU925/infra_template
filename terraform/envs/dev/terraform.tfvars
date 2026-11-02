# dev: 비용 우선. 단일 NAT, 단일 AZ DB, 삭제 보호 꺼짐.
project             = "myproject"
environment         = "dev"
region              = "ap-northeast-2"
allowed_account_ids = ["111111111111"] # TODO: dev 계정 ID

vpc_cidr           = "10.10.0.0/16"
az_count           = 2
single_nat_gateway = true

app_instance_count = 1
app_instance_type  = "t3.small"

db_instance_class        = "db.t4g.micro"
db_multi_az              = false
db_backup_retention_days = 3
db_deletion_protection   = false

artifact_bucket_force_destroy = true
