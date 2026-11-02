provider "aws" {
  region = var.region

  # 실수로 다른 계정에 배포하는 것을 막는다
  allowed_account_ids = var.allowed_account_ids

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner_team
      Repository  = var.repository
    }
  }
}
