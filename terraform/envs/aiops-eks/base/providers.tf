provider "aws" {
  region = var.region

  allowed_account_ids = var.allowed_account_ids

  # eks.sh leftovers 는 Project=ai-incident 중 Layer=base 를 빼고 센다
  default_tags {
    tags = {
      Project     = "ai-incident"
      Environment = "aiops-eks"
      Layer       = "base"
      ManagedBy   = "terraform"
    }
  }
}
