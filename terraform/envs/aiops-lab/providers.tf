provider "aws" {
  region = var.region

  # 실수로 다른 계정에 배포하는 것을 막는다
  allowed_account_ids = var.allowed_account_ids

  # destroy 후 lab.sh leftovers 가 이 Project 태그로 남은 리소스를 찾는다
  default_tags {
    tags = {
      Project     = "ai-incident"
      Environment = "aiops-lab"
      ManagedBy   = "terraform"
    }
  }
}
