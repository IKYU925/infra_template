variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "allowed_account_ids" {
  description = "배포를 허용할 AWS 계정 ID 목록"
  type        = list(string)
}

variable "budget_limit_usd" {
  description = "월 예산(USD). 총예산 100달러를 사용 기간 2달로 나눈 값"
  type        = number
  default     = 50
}

variable "budget_email" {
  description = "예산 알림을 받을 메일 주소"
  type        = string
}

variable "loki_retention_days" {
  description = "Loki 버킷 객체 보존 기간(일)"
  type        = number
  default     = 7
}
