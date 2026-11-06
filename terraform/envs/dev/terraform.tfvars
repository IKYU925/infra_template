# dev: 비용 우선. 단일 NAT, 단일 AZ DB, 삭제 보호 꺼짐.
project             = "myproject"
environment         = "dev"
region              = "ap-northeast-2"
allowed_account_ids = ["111111111111"] # TODO: dev 계정 ID

vpc_cidr           = "10.10.0.0/16"
az_count           = 2
single_nat_gateway = true

# EKS: 노드 t3.medium x 2 (AZ 2개에 분산)
eks_public_access_cidrs  = ["203.0.113.10/32"] # TODO: kubectl 을 쓸 곳의 공인 IP (curl ifconfig.me)
eks_admin_principal_arns = []                  # TODO: 팀원 IAM 역할 ARN
node_instance_types      = ["t3.medium"]
node_min_size            = 2
node_max_size            = 3
node_desired_size        = 2
ecr_force_delete         = true

db_instance_class        = "db.t4g.micro"
db_multi_az              = false
db_backup_retention_days = 3
db_deletion_protection   = false

artifact_bucket_force_destroy = true
