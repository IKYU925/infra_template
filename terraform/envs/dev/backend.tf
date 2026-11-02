# 원격 state: S3 + DynamoDB 잠금.
# 버킷/테이블 이름은 계정마다 다르므로 partial configuration 으로 분리했다.
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {}
}
