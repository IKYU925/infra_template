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


# ---------------------------------------------------------------- EKS
variable "eks_version" {
  description = "Kubernetes 마이너 버전. 로컬 k3s(ansible/roles/k3s 의 k3s_version)와 같은 마이너로 맞춘다"
  type        = string
  default     = "1.36"
}

variable "eks_public_access_cidrs" {
  description = "EKS API 에 접속을 허용할 공인 IP 대역 (예: 학교/사무실 IP/32)"
  type        = list(string)

  validation {
    condition     = length(var.eks_public_access_cidrs) > 0 && !contains(var.eks_public_access_cidrs, "0.0.0.0/0")
    error_message = "eks_public_access_cidrs 는 비울 수 없고 0.0.0.0/0 을 넣을 수 없습니다."
  }
}

variable "eks_admin_principal_arns" {
  description = "클러스터 관리자 권한을 줄 IAM 역할/사용자 ARN (사람용. CI 역할은 생성자로 자동 등록)"
  type        = list(string)
  default     = []
}

variable "eks_log_retention_days" {
  description = "EKS 컨트롤 플레인 로그 보존 기간(일)"
  type        = number
  default     = 90
}

variable "node_instance_types" {
  description = "관리형 노드그룹 인스턴스 타입 (amd64)"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  description = "노드 최소 수"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "노드 최대 수"
  type        = number
  default     = 3
}

variable "node_desired_size" {
  description = "노드 기본 수"
  type        = number
  default     = 2
}

variable "app_namespace" {
  description = "앱이 배포되는 네임스페이스 (Pod Identity 연결 대상)"
  type        = string
  default     = "app"
}

variable "app_service_account" {
  description = "앱 파드의 서비스 계정 이름 (Pod Identity 연결 대상)"
  type        = string
  default     = "app"
}

# ---------------------------------------------------------------- ECR
variable "ecr_push_principal_arns" {
  description = "ECR 에 이미지를 올릴 IAM 역할 ARN (앱 저장소 CI 등)"
  type        = list(string)
  default     = []
}

variable "ecr_keep_images" {
  description = "ECR 에 보관할 최근 이미지 수"
  type        = number
  default     = 30
}

variable "ecr_force_delete" {
  description = "이미지가 있어도 저장소 삭제 허용 (dev 에서만 true)"
  type        = bool
  default     = false
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
