variable "project" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 이름"
  type        = string
}

variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "allowed_account_ids" {
  description = "배포를 허용할 AWS 계정 ID 목록"
  type        = list(string)
}

variable "owner_team" {
  description = "리소스 소유 팀 태그"
  type        = string
  default     = "infra"
}

variable "repository" {
  description = "이 코드가 있는 저장소 (태그용)"
  type        = string
  default     = "infra_template"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

variable "az_count" {
  description = "가용 영역 수"
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "NAT 게이트웨이 1개만 사용"
  type        = bool
  default     = true
}

variable "enable_flow_log" {
  description = "VPC Flow Log 활성화"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Flow Log 보존 기간(일)"
  type        = number
  default     = 90
}

variable "app_ingress_cidrs" {
  description = "앱 HTTP/HTTPS 허용 CIDR (비우면 VPC 내부만)"
  type        = list(string)
  default     = []
}

variable "app_instance_count" {
  description = "앱 EC2 수"
  type        = number
  default     = 1
}

variable "app_instance_type" {
  description = "앱 EC2 타입"
  type        = string
  default     = "t3.small"
}

variable "app_root_volume_size" {
  description = "앱 EC2 루트 볼륨(GiB)"
  type        = number
  default     = 30
}

variable "db_engine_version" {
  description = "PostgreSQL 메이저 버전"
  type        = string
  default     = "17"
}

variable "db_instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "RDS 스토리지(GiB)"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "RDS 스토리지 자동 확장 상한(GiB)"
  type        = number
  default     = 100
}

variable "db_multi_az" {
  description = "RDS Multi-AZ"
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "RDS 백업 보존(일)"
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "RDS 삭제 보호"
  type        = bool
  default     = false
}

variable "artifact_bucket_force_destroy" {
  description = "아티팩트 버킷 강제 삭제 허용"
  type        = bool
  default     = false
}
