provider "aws" {
  region = var.region

  allowed_account_ids = var.allowed_account_ids

  # eks.sh leftovers 가 이 태그로 남은 리소스를 찾는다
  default_tags {
    tags = {
      Project     = "ai-incident"
      Environment = "aiops-eks"
      Layer       = "cluster"
      ManagedBy   = "terraform"
    }
  }
}

# 토큰을 apply 중에 받는다. aws_eks_cluster_auth 토큰은 plan 때 발급돼 클러스터 생성(15분 남짓) 사이에 만료된다
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
