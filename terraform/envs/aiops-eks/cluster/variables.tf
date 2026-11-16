variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "allowed_account_ids" {
  description = "배포를 허용할 AWS 계정 ID 목록"
  type        = list(string)
}

variable "state_bucket" {
  description = "base 층 state 가 있는 버킷 (backend.hcl 의 bucket 과 같다)"
  type        = string
}

variable "name" {
  description = "클러스터와 VPC 이름"
  type        = string
  default     = "ai-incident"
}

variable "kubernetes_version" {
  description = "EKS 버전. 표준 지원 기간 안의 버전만 쓴다 (1.35 표준 지원 종료 2027-03-27)"
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "VPC CIDR (dev 10.10.0.0/16 과 겹치지 않게)"
  type        = string
  default     = "10.40.0.0/16"
}

variable "node_instance_type" {
  description = "노드그룹 인스턴스 타입. 이미지가 linux/arm64 라 Graviton 이어야 한다. t4g.medium 은 VPC CNI 기본값에서 노드당 Pod 17개라 모자란다 (P0)"
  type        = string
  default     = "t4g.large"
}

variable "endpoint_allowed_cidrs" {
  description = "컨트롤 플레인 공개 엔드포인트에 늘 허용할 CIDR (운영자 고정 IP 등)"
  type        = list(string)
  default     = []
}

variable "caller_cidr" {
  description = "apply 하는 곳의 IP/32. eks.sh 가 넘긴다. ArgoCD helm 설치가 이 IP 에서 API 를 부른다"
  type        = string
}

variable "admin_principal_arns" {
  description = "클러스터 관리자 IAM 주체 (운영자, GitHub Actions apply 역할). apply 하는 주체는 자동으로 관리자가 된다"
  type        = list(string)
  default     = []
}

variable "argocd_root_revision" {
  description = "aiops-root 앱과 하위 앱이 볼 AI_auto_pipeline 브랜치 (검증 중에는 기능 브랜치)"
  type        = string
  default     = "main"
}

variable "image_tag" {
  description = "ECR 에 올린 aiops 이미지 태그. 비우면 deploy/argocd 차트 기본값"
  type        = string
  default     = ""
}
