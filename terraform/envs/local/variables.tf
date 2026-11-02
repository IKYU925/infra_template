variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "region" {
  description = "에뮬레이터에 전달할 리전 값"
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_endpoint" {
  description = "로컬 AWS 에뮬레이터 엔드포인트 (floci / LocalStack)"
  type        = string
  default     = "http://localhost:4566"
}
