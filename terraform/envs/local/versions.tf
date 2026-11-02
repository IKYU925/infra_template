terraform {
  required_version = ">= 1.11.1, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.71"
    }
  }

  # 로컬 환경은 원격 state 를 쓰지 않는다.
  backend "local" {
    path = "terraform.tfstate"
  }
}
