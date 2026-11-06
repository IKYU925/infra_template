# prod: 가용성·보호 우선. AZ별 NAT, Multi-AZ DB, 삭제 보호 켜짐.
project             = "myproject"
environment         = "prod"
region              = "ap-northeast-2"
allowed_account_ids = ["222222222222"] # TODO: prod 계정 ID (dev 와 분리 권장)

vpc_cidr           = "10.20.0.0/16"
az_count           = 3
single_nat_gateway = false

flow_log_retention_days = 365

# EKS: 노드 t3.medium x 3 (AZ 3개에 분산)
eks_public_access_cidrs  = ["203.0.113.10/32"] # TODO: kubectl 을 쓸 곳의 공인 IP
eks_admin_principal_arns = []                  # TODO: 운영 관리자 IAM 역할 ARN
node_instance_types      = ["t3.medium"]
node_min_size            = 3
node_max_size            = 6
node_desired_size        = 3

db_instance_class        = "db.t4g.medium"
db_allocated_storage     = 50
db_max_allocated_storage = 500
db_multi_az              = true
db_backup_retention_days = 30
db_deletion_protection   = true

artifact_bucket_force_destroy = false
