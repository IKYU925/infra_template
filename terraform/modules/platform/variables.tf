variable "project" {
  description = "프로젝트 이름 (리소스 이름 접두사)"
  type        = string
}

variable "environment" {
  description = "환경 이름 (dev, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod"], var.environment)
    error_message = "environment 는 dev, stg, prod 중 하나여야 합니다."
  }
}

variable "tags" {
  description = "모든 리소스에 추가할 태그"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------- 네트워크
variable "vpc_cidr" {
  description = "VPC CIDR (/16 권장, 서브넷은 /24 로 자동 분할)"
  type        = string
}

variable "az_count" {
  description = "사용할 가용 영역 수"
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "NAT 게이트웨이를 하나만 둘지 여부 (dev: true 로 비용 절감, prod: false 로 AZ별 구성)"
  type        = bool
  default     = true
}

variable "enable_flow_log" {
  description = "VPC Flow Log 활성화 (보안팀 감사용)"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Flow Log CloudWatch 보존 기간(일)"
  type        = number
  default     = 90
}

variable "app_ingress_cidrs" {
  description = "앱 서버 HTTP/HTTPS 접근을 허용할 CIDR 목록 (기본: VPC 내부만)"
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------- EC2
variable "app_instance_count" {
  description = "앱 EC2 인스턴스 수"
  type        = number
  default     = 1
}

variable "app_instance_type" {
  description = "앱 EC2 인스턴스 타입"
  type        = string
  default     = "t3.small"
}

variable "app_ami_ssm_parameter" {
  description = "AMI 를 조회할 SSM 파라미터 (기본: Ubuntu 24.04 LTS)"
  type        = string
  default     = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

variable "app_root_volume_size" {
  description = "앱 EC2 루트 볼륨 크기(GiB)"
  type        = number
  default     = 30
}

# ---------------------------------------------------------------- RDS
variable "db_engine_version" {
  description = "PostgreSQL 엔진 버전"
  type        = string
  default     = "17"
}

variable "db_instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "RDS 초기 스토리지(GiB)"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "RDS 스토리지 자동 확장 상한(GiB)"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "기본 데이터베이스 이름"
  type        = string
  default     = "app"
}

variable "db_username" {
  description = "마스터 사용자 이름 (비밀번호는 Secrets Manager 가 관리)"
  type        = string
  default     = "app_admin"
}

variable "db_multi_az" {
  description = "Multi-AZ 배포 여부"
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "자동 백업 보존 기간(일)"
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "삭제 보호 (prod 는 반드시 true)"
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- S3
variable "artifact_bucket_force_destroy" {
  description = "버킷에 객체가 있어도 destroy 허용 (dev 에서만 true)"
  type        = bool
  default     = false
}

variable "artifact_noncurrent_expiration_days" {
  description = "이전 버전 객체 만료 기간(일)"
  type        = number
  default     = 30
}
