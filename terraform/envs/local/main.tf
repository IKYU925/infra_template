# 로컬에서는 VPC/EC2/RDS 를 에뮬레이션하지 않는다.
#  - DB  : docker-compose 의 postgres 컨테이너가 RDS 를 대신한다.
#  - 앱  : docker-compose 의 app 컨테이너가 EC2 를 대신한다.
# 여기서는 앱 코드가 호출하는 AWS API(S3, Secrets Manager 등)만 흉내 낸다.
# dev/prod 와 같은 모듈(terraform-aws-modules/s3-bucket)을 써서 설정 차이를 줄인다.

module "artifact_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.17.0"

  bucket        = "${var.project}-local-artifacts"
  force_destroy = true

  versioning = {
    enabled = true
  }
}

resource "aws_secretsmanager_secret" "db" {
  #checkov:skip=CKV_AWS_149:로컬 에뮬레이터 전용, KMS CMK 불필요
  #checkov:skip=CKV2_AWS_57:로컬 에뮬레이터 전용, 회전 불필요
  name                    = "${var.project}/local/db"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    host     = "postgres"
    port     = 5432
    username = "app"
    dbname   = "app"
    # 비밀번호는 local/.env 의 POSTGRES_PASSWORD 를 쓴다 (코드에 넣지 않음)
  })
}
