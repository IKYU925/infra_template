terraform {
  required_version = ">= 1.11.1, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.71"
    }
  }

  # 부트스트랩은 state 버킷 자체를 만들기 때문에 처음엔 로컬 state 로 시작한다.
  # apply 후 README 의 "state 이전" 절차대로 S3 로 옮길 수 있다.
}
