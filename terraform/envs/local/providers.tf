# (선택) 로컬 AWS 에뮬레이터용 provider.
# local/docker-compose.yml 의 "aws" 프로필(floci) 또는 "localstack" 프로필을 띄운 뒤 사용한다.
# 둘 다 http://localhost:4566 을 쓰므로 endpoint 만 맞으면 동일하게 동작한다.
provider "aws" {
  region     = var.region
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3             = var.aws_endpoint
    sts            = var.aws_endpoint
    iam            = var.aws_endpoint
    dynamodb       = var.aws_endpoint
    secretsmanager = var.aws_endpoint
    sqs            = var.aws_endpoint
  }

  default_tags {
    tags = {
      Project     = var.project
      Environment = "local"
      ManagedBy   = "terraform"
    }
  }
}
