terraform {
  required_version = ">= 1.11.1, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.71"
    }
  }

  # GitHub Actions 스케줄도 같은 state 를 써야 해서 bootstrap 의 S3 + DynamoDB 를 쓴다.
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}
}
