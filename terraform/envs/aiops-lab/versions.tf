terraform {
  required_version = ">= 1.11.1, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.71"
    }
  }

  # 실습이 끝나면 destroy 로 0개까지 지우므로 공유 S3 state 를 쓰지 않는다.
  # make tf-init 이 -backend-config=backend.hcl 을 넘기므로 path 는 그쪽에 둔다.
  backend "local" {}
}
