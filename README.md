# infra_template

풀스택·보안·인프라 세 팀이 함께 쓰는 **인프라 구성 자동화 템플릿**입니다.
Terraform 으로 AWS 리소스를 만들고, Ansible 로 서버를 설정하며, GitHub Actions 가 PR 마다 검사·plan·보안 스캔을 돌립니다.

> **처음 쓰신다면 [사용 가이드(docs/USAGE.md)](docs/USAGE.md) 를 순서대로 따라 하세요.** 설치부터 GitHub 설정, 배포, 일상 작업 흐름, 문제 해결까지 단계별로 정리돼 있습니다.

| 환경 | 어디서 | 무엇으로 |
|---|---|---|
| **local** | 개발자 PC | Docker Compose (postgres + app), 선택으로 floci / LocalStack 로컬 AWS |
| **dev** | AWS (dev 계정) | Terraform `envs/dev` + Ansible `inventories/dev` |
| **prod** | AWS (prod 계정) | Terraform `envs/prod` + Ansible `inventories/prod` |

---

## 1. 폴더 구조

```text
.
├── terraform/
│   ├── bootstrap/            # 계정당 1회: state 버킷(S3) + 잠금 테이블(DynamoDB) + GitHub OIDC 역할
│   ├── modules/platform/     # 환경 공통 스택 (VPC, SG, EC2, RDS, S3, IAM) - terraform-aws-modules 조합
│   └── envs/
│       ├── local/            # (선택) floci/LocalStack 대상. S3, Secrets Manager 만
│       ├── dev/              # backend.hcl + terraform.tfvars (비용 우선)
│       └── prod/             # backend.hcl + terraform.tfvars (가용성·보호 우선)
├── ansible/
│   ├── inventories/{local,dev,prod}/   # 환경별 인벤토리 (dev/prod 는 aws_ec2 동적 인벤토리)
│   ├── playbooks/            # site.yml = hardening -> docker -> app
│   ├── roles/app/            # 앱 배포 롤 (Docker Compose)
│   └── requirements.yml      # geerlingguy, devsec.hardening, amazon.aws 등 (버전 고정)
├── local/docker-compose.yml  # 로컬 개발 환경
├── .github/
│   ├── workflows/terraform.yml       # fmt / validate / tflint / plan / apply
│   ├── workflows/security-scan.yml   # Trivy + Checkov (SARIF -> Security 탭)
│   ├── workflows/ansible.yml         # ansible-lint + syntax-check
│   ├── dependabot.yml                # 고정 버전 자동 업데이트 PR
│   └── CODEOWNERS                    # 팀별 리뷰 담당
├── docs/USAGE.md                     # 단계별 사용 가이드
├── trivy.yaml / .checkov.yaml        # 스캐너 설정 (보안팀 관리)
├── .pre-commit-config.yaml
└── Makefile                          # make help
```

## 2. 팀별 역할

| 팀 | 주로 보는 곳 | 하는 일 |
|---|---|---|
| **인프라** | `terraform/`, `ansible/playbooks`, `.github/workflows` | 모듈·환경 관리, plan 리뷰, prod apply 승인 |
| **보안** | `.checkov.yaml`, `trivy.yaml`, `ansible/inventories/*/group_vars/all/hardening.yml`, `terraform/bootstrap` (IAM) | 스캔 정책, 하드닝 기준선, 예외 승인, IAM 최소 권한 검토 |
| **풀스택** | `local/`, `ansible/roles/app`, `inventories/*/group_vars/all/main.yml` 의 `app_*` 변수 | 앱 이미지·환경 변수, 로컬 개발 환경 |

리뷰 담당은 `.github/CODEOWNERS` 에 있습니다. `@your-org/...` 를 실제 팀 이름으로 바꾸세요.

## 3. 사용한 오픈소스 (모두 버전 고정)

GitHub 에서 많이 쓰이고 지금도 관리되는 것들로 골랐습니다. 2026-11-02 기준 최신 태그입니다.

| 구분 | 이름 | 버전 |
|---|---|---|
| Terraform | Terraform CLI | 1.17.1 (`required_version >= 1.11.1`) |
| | hashicorp/aws provider | `~> 6.71` |
| | terraform-aws-modules/vpc | 6.7.3 |
| | terraform-aws-modules/security-group | 6.0.0 |
| | terraform-aws-modules/ec2-instance | 6.4.1 |
| | terraform-aws-modules/rds | 7.2.2 |
| | terraform-aws-modules/s3-bucket | 5.17.0 |
| | terraform-aws-modules/iam (iam-role, iam-policy, iam-oidc-provider) | 6.8.2 |
| | terraform-aws-modules/dynamodb-table | 5.5.2 |
| Ansible | geerlingguy.docker / geerlingguy.pip | 8.0.0 / 3.1.2 |
| | devsec.hardening (os_hardening, ssh_hardening) | 11.0.0 |
| | amazon.aws (aws_ec2 인벤토리, aws_ssm 접속) | 12.0.0 |
| | community.docker / community.general / ansible.posix | 5.4.0 / 13.5.0 / 2.2.2 |
| 보안 스캔 | Trivy (tfsec 후속) / Checkov | trivy-action 0.36.0 / checkov-action 12.3136.0 |
| 로컬 AWS | floci (기본) / LocalStack (선택) | 2.4.0 / 4.14.0 |

GitHub Actions 는 태그 대신 **커밋 SHA 로 고정**했습니다 (공급망 공격 방지). 버전 업데이트는 Dependabot 이 PR 로 올립니다.

> **LocalStack 주의**: LocalStack 의 GitHub 레포는 2026년 3월에 아카이브되었습니다. 이미지 사용 조건(인증 토큰 필요 여부)을 확인하기 전까지는 기본값으로 쓰지 않고, `localstack` 프로필로만 켜도록 했습니다. 기본 로컬 AWS 에뮬레이터는 같은 4566 포트를 쓰는 MIT 라이선스 **floci** 입니다.

## 4. 빠른 시작

### 4.1 준비물

- Terraform 1.11.1 이상 (CI 는 1.17.1), AWS CLI v2, Docker (Compose v2)
- Python 3.11 이상: `pip install -r ansible/requirements.txt`
- dev/prod 에 Ansible 로 접속하려면 로컬에 [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- (권장) `pip install pre-commit && pre-commit install`

### 4.2 local (Docker Compose)

```bash
cp local/.env.example local/.env        # 비밀번호 수정
make local-up                           # postgres + app  -> http://localhost:8080

# (선택) 로컬 AWS 가 필요할 때: floci + terraform/envs/local apply
make local-aws-up
aws --endpoint-url http://localhost:4566 s3 ls

# (선택) LocalStack 을 쓰고 싶다면 (floci 와 동시에 켜지 말 것)
make local-localstack-up

# (선택) Ansible 플레이북을 로컬 컨테이너에 연습
docker compose -f local/docker-compose.yml --env-file local/.env --profile ansible-lab up -d
make ansible-deps
make ansible-run ENV=local

make local-down
```

로컬에서는 VPC·EC2·RDS 를 흉내 내지 않습니다. postgres 컨테이너가 RDS(같은 PostgreSQL 17), app 컨테이너가 EC2 역할을 하고, 앱이 호출하는 AWS API(S3, Secrets Manager 등)만 floci 로 대신합니다.

### 4.3 AWS 계정 부트스트랩 (계정당 1회, 인프라팀)

```bash
cd terraform/bootstrap
# dev.tfvars 의 allowed_account_ids, github_repository 수정
terraform init
terraform apply -var-file=dev.tfvars
terraform output
```

출력값을 다음 위치에 넣습니다.

| 출력 | 넣을 곳 |
|---|---|
| `state_bucket`, `lock_table` | `terraform/envs/dev/backend.hcl` 의 `bucket`, `dynamodb_table` |
| `plan_role_arn` | GitHub Environment **`dev-plan`** 의 변수 `AWS_PLAN_ROLE_ARN` |
| `apply_role_arn` | GitHub Environment **`dev`** 의 변수 `AWS_APPLY_ROLE_ARN` |

prod 계정도 `prod.tfvars` 로 같은 과정을 반복합니다. GitHub Environment **`prod`** 에는 반드시 *Required reviewers* 를 걸어 두세요.

부트스트랩 state 는 처음엔 로컬 파일입니다. 안전하게 보관하거나, 만든 버킷으로 옮기려면 `versions.tf` 에 `backend "s3" {}` 를 추가하고 `terraform init -migrate-state -backend-config=...` 를 실행합니다.

> **잠금 방식**: 원격 state 는 **S3 + DynamoDB 잠금**입니다. Terraform 1.10 부터 S3 자체 잠금(`use_lockfile`)이 생겨 `dynamodb_table` 사용 시 *deprecated* 경고가 나옵니다. 동작에는 문제 없고, 옮길 때는 `backend.hcl` 의 `use_lockfile = true` 주석을 풀어 두 방식을 함께 쓰다가 `dynamodb_table` 을 지우면 됩니다.

### 4.4 dev / prod 배포

```bash
# terraform.tfvars 의 project, allowed_account_ids 등 수정
make tf-init  ENV=dev
make tf-plan  ENV=dev
make tf-apply ENV=dev

# Ansible: 출력된 버킷 이름을 inventories/dev/group_vars/all/main.yml 의 ansible_aws_ssm_bucket_name 에
terraform -chdir=terraform/envs/dev output -raw artifact_bucket_name
make ansible-deps
make ansible-ping ENV=dev
make ansible-run  ENV=dev
```

| 항목 | dev | prod |
|---|---|---|
| VPC CIDR / AZ | 10.10.0.0/16, 2 AZ | 10.20.0.0/16, 3 AZ |
| NAT 게이트웨이 | 1개 (비용 절감) | AZ 마다 1개 |
| 앱 EC2 | t3.small × 1 | t3.medium × 2 |
| RDS | db.t4g.micro, 단일 AZ, 백업 3일 | db.t4g.medium, Multi-AZ, 백업 30일, 삭제 보호 |
| Flow Log 보존 | 90일 | 365일 |

## 5. 아키텍처와 보안 기본값

- **네트워크**: public / private / database 서브넷 3계층. EC2 는 private, RDS 는 database 서브넷. 기본 SG 는 모든 트래픽 차단. VPC Flow Log 기본 활성화.
- **접속**: SSH 포트와 키 없이 **SSM Session Manager** 로만 접속합니다. Ansible 도 `amazon.aws.aws_ssm` 커넥션으로 붙고, 파일 전송에는 아티팩트 S3 버킷을 씁니다.
- **EC2**: Ubuntu 24.04 (SSM 파라미터로 최신 AMI), IMDSv2 강제, 루트 볼륨 암호화, 상세 모니터링.
- **RDS**: PostgreSQL 17, 마스터 비밀번호는 **Secrets Manager 가 생성·관리** (state 에 평문 없음), SSL 강제(`rds.force_ssl=1`), IAM DB 인증, Performance Insights, 로그 CloudWatch 전송.
- **S3**: 퍼블릭 차단, KMS 암호화, 버전 관리, HTTPS·TLS1.2 강제 정책.
- **IAM**: CI 는 장기 키 없이 **GitHub OIDC**. PR plan 은 읽기 전용 역할, apply 는 승인 규칙이 걸린 GitHub Environment 에서만 assume 가능. apply 역할 권한(`apply_role_policy_arns`)은 기본값이 넓으니 보안팀과 최소 권한으로 줄이세요.
- **OS**: dev-sec `os_hardening` + `ssh_hardening` 적용. 기준 변수는 `group_vars/all/hardening.yml`.
- **앱 컨테이너**: read-only 루트 FS, `no-new-privileges`, `cap_drop: ALL`.

## 6. CI/CD (GitHub Actions)

| 워크플로 | 언제 | 하는 일 |
|---|---|---|
| `terraform.yml` | `terraform/**` 변경 PR | `fmt -check` → `validate` + `tflint` (모든 루트) → dev/prod `plan` (결과는 Job Summary) |
| | `main` 푸시 | dev `apply` (Environment `dev`) |
| | 수동 실행 | 선택한 환경 `apply` (prod 는 승인 필요) |
| `security-scan.yml` | 모든 PR, main, 매주 월요일 | Trivy(모듈 내부까지 설정 오류+시크릿, HIGH/CRITICAL 이면 실패), Checkov(우리 코드 + GitHub Actions + 시크릿). 결과는 Security 탭 |
| `ansible.yml` | `ansible/**` 변경 PR | 롤·컬렉션 설치 → 환경별 syntax-check → ansible-lint(production 프로필) |

AWS 역할 변수가 아직 없으면 plan/apply 단계는 건너뛰고 안내만 남깁니다. 그래서 저장소를 올리자마자 fmt/validate/스캔은 바로 동작합니다.

**스캔 예외 처리**: 꼭 필요한 경우만 `.checkov.yaml` 의 `skip-check` 또는 리소스 위 `#checkov:skip=CKV_AWS_xxx:사유` 로 남기고, 보안팀 리뷰를 받습니다.

## 7. 처음 쓸 때 바꿀 것 체크리스트

- [ ] `myproject` → 실제 프로젝트 이름 (`terraform.tfvars`, `bootstrap/*.tfvars`, `inventories/*/aws_ec2.yml`)
- [ ] AWS 계정 ID `111111111111` / `222222222222`
- [ ] `your-org/infra_template` (OIDC 신뢰 대상 저장소), CODEOWNERS 팀 이름
- [ ] `backend.hcl` 의 버킷·테이블 이름 (bootstrap 출력)
- [ ] `inventories/{dev,prod}/group_vars/all/main.yml` 의 `ansible_aws_ssm_bucket_name`, `app_image`
- [ ] 첫 `terraform init` 후 생긴 `.terraform.lock.hcl` 커밋 (`terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` 권장)
- [ ] GitHub Environments `dev-plan`, `prod-plan`, `dev`, `prod` 생성과 변수 등록, `prod` 승인자 지정

## 8. 확장 아이디어

- ALB + ACM (`terraform-aws-modules/alb`), ECS/EKS 로 전환 (`terraform-aws-modules/ecs`, `eks`)
- 여러 환경을 DRY 하게 관리해야 하면 Terragrunt 도입 검토
- Ansible 롤 테스트: Molecule + `geerlingguy/docker-ubuntu2404-ansible` 이미지
- 비용 가시화: Infracost 를 PR 코멘트로 추가
