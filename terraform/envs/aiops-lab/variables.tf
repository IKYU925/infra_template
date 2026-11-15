variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "allowed_account_ids" {
  description = "배포를 허용할 AWS 계정 ID 목록"
  type        = list(string)
}

variable "name" {
  description = "리소스 이름 접두사"
  type        = string
  default     = "ai-incident-lab"
}

variable "tenant" {
  description = "경보 이름의 고객사 부분 (<tenant>-<service>-<alertname>)"
  type        = string
  default     = "tenant-a"
}

variable "service" {
  description = "대상 서비스 이름. 경보 이름, 로그 그룹, ECR 저장소, 컨테이너 이름에 쓰인다"
  type        = string
  default     = "shopapi"
}

variable "vpc_cidr" {
  description = "VPC CIDR (dev 10.10.0.0/16 과 겹치지 않게)"
  type        = string
  default     = "10.40.0.0/16"
}

variable "instance_type" {
  description = "EC2 타입. 앱 이미지가 linux/arm64 로 빌드되므로 Graviton(t4g 등)이어야 한다"
  type        = string
  default     = "t4g.small"
}

variable "disk_alarm_threshold" {
  description = "DiskUsageHigh 경보 기준 루트 디스크 사용률(%)"
  type        = number
  default     = 90
}

variable "log_retention_days" {
  description = "앱 로그 그룹 보존 기간(일)"
  type        = number
  default     = 3
}

variable "budget_limit_usd" {
  description = "월 예산 한도(USD)"
  type        = number
  default     = 10
}

variable "budget_email" {
  description = "예산 알림을 받을 메일 주소"
  type        = string
}

variable "root_volume_size" {
  description = "루트 볼륨(GiB). 앱 이미지(Python, 임베딩 모델)만으로 S19 임계값에 닿지 않을 만큼 둔다"
  type        = number
  default     = 20
}
