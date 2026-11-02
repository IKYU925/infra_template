variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "account_alias" {
  description = "이 계정의 용도 (dev, prod 등). 리소스 이름과 GitHub Environment 이름에 쓰인다."
  type        = string
}

variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "allowed_account_ids" {
  description = "이 부트스트랩을 적용할 AWS 계정 ID"
  type        = list(string)
}

variable "github_repository" {
  description = "GitHub Actions OIDC 신뢰 대상 저장소 (owner/repo)"
  type        = string
}

variable "create_github_oidc_provider" {
  description = "계정에 GitHub OIDC 공급자가 아직 없으면 true"
  type        = bool
  default     = true
}

variable "apply_role_policy_arns" {
  description = "apply 역할에 붙일 정책 ARN. 보안팀과 협의해 최소 권한으로 줄일 것."
  type        = map(string)
  default = {
    power_user = "arn:aws:iam::aws:policy/PowerUserAccess"
    iam_full   = "arn:aws:iam::aws:policy/IAMFullAccess"
  }
}
