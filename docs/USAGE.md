# 사용 가이드

README 가 "무엇이 들어 있는지"를 설명한다면, 이 문서는 **처음 받은 사람이 실제로 쓰기까지의 순서**를 단계별로 정리합니다.
명령은 저장소 루트에서 실행한다고 가정합니다.

## 0. 전체 흐름 한눈에 보기

| 순서 | 할 일 | 담당 | 얼마나 자주 |
|---|---|---|---|
| 1 | 도구 설치 | 모두 | 한 번 |
| 2 | 템플릿 값 바꾸기 (프로젝트 이름, 계정 ID 등) | 인프라 | 한 번 |
| 3 | 로컬 환경 띄우기 | 풀스택 (모두) | 매일 |
| 4 | AWS 계정 부트스트랩 (state 버킷, 잠금 테이블, CI 역할) | 인프라 | 계정당 한 번 |
| 5 | GitHub 설정 (Environments, 변수, 승인자) | 인프라 + 보안 | 한 번 |
| 6 | dev 배포 → 서버 설정(Ansible) | 인프라 | 변경 시 |
| 7 | 일상 작업: 브랜치 → PR → plan 확인 → 병합 → dev 자동 반영 → prod 수동 반영 | 모두 | 매번 |

로컬만 쓸 사람(풀스택)은 1, 3단계만 하면 됩니다.

---

## 1. 도구 설치

macOS (Homebrew) 기준입니다.

```bash
brew install terraform awscli tflint pre-commit
brew install --cask docker session-manager-plugin   # Docker Desktop, SSM 접속 플러그인
python3 -m venv .venv && source .venv/bin/activate
pip install -r ansible/requirements.txt
pre-commit install                                  # 커밋 전에 fmt/lint/시크릿 검사
```

설치 확인:

```bash
terraform version      # 1.11.1 이상
docker compose version
ansible --version      # core 2.18 이상
session-manager-plugin # "installed successfully" 문구가 나오면 정상
```

## 2. 템플릿 값 바꾸기 (인프라팀, 한 번)

1. 프로젝트 이름 `myproject` 를 한 번에 바꿉니다.

   ```bash
   grep -rl myproject terraform ansible | xargs sed -i '' 's/myproject/<우리프로젝트>/g'   # macOS
   ```

2. AWS 계정 ID 를 바꿉니다.
   - dev: `terraform/envs/dev/terraform.tfvars`, `terraform/bootstrap/dev.tfvars` 의 `111111111111`
   - prod: `terraform/envs/prod/terraform.tfvars`, `terraform/bootstrap/prod.tfvars` 의 `222222222222`
3. `terraform/bootstrap/*.tfvars` 의 `github_repository` 를 실제 저장소(예: `IKYU925/infra_template`)로 바꿉니다.
4. `.github/CODEOWNERS` 의 `@your-org/...` 를 실제 GitHub 팀이나 사용자로 바꿉니다.
5. 리전이 서울(`ap-northeast-2`)이 아니면 `tfvars` 와 `ansible/inventories/*/aws_ec2.yml`, `group_vars` 의 리전을 함께 바꿉니다.

## 3. 로컬 환경 (풀스택팀)

```bash
make local-up            # 처음 실행 시 local/.env 를 자동으로 만든다 -> 비밀번호를 바꿔 두자
open http://localhost:8080
docker compose -f local/docker-compose.yml --env-file local/.env logs -f app
make local-down
```

**우리 앱으로 바꾸기**: `local/.env` 의 `APP_IMAGE` 를 우리 이미지로 바꾸거나, `local/docker-compose.yml` 의 `app` 서비스에 `build: ../<앱 폴더>` 를 넣습니다. 앱 안에서 쓸 수 있는 값은 다음과 같습니다.

| 환경 변수 | 값 | AWS 에서 대응 |
|---|---|---|
| `DATABASE_URL` | `postgresql://app:<비번>@postgres:5432/app` | RDS 엔드포인트 + Secrets Manager |
| `AWS_ENDPOINT_URL` | `http://aws:4566` (floci 를 켰을 때) | 설정 안 함 (실제 AWS) |
| `AWS_REGION` | `ap-northeast-2` | 같음 |

**S3 같은 AWS API 가 필요하면**:

```bash
make local-aws-up                                  # floci 실행 + terraform/envs/local apply
aws --endpoint-url http://localhost:4566 s3 ls     # myproject-local-artifacts 버킷이 보이면 성공
```

DB 에 직접 붙기: `psql postgresql://app:<비번>@localhost:5432/app`

## 4. AWS 계정 부트스트랩 (인프라팀, 계정당 한 번)

1. 관리자 권한으로 로그인합니다. (SSO 를 쓴다면 `aws sso login --profile <프로필>` 후 `export AWS_PROFILE=<프로필>`)

   ```bash
   aws sts get-caller-identity   # 계정 ID 가 dev 계정인지 확인
   ```

2. 부트스트랩을 적용합니다.

   ```bash
   cd terraform/bootstrap
   terraform init
   terraform apply -var-file=dev.tfvars
   terraform output
   ```

3. 출력값을 옮겨 적습니다.
   - `state_bucket` → `terraform/envs/dev/backend.hcl` 의 `bucket`
   - `lock_table` → `terraform/envs/dev/backend.hcl` 의 `dynamodb_table`
   - `plan_role_arn`, `apply_role_arn` → 5단계 GitHub 변수
4. `terraform.tfstate` (부트스트랩 state) 는 git 에 올리지 말고 팀 비밀 저장소(1Password 등)에 보관합니다.
5. prod 계정에서 `prod.tfvars` 로 같은 과정을 반복합니다.

> 계정에 GitHub OIDC 공급자가 이미 있다는 오류(`EntityAlreadyExists`)가 나면 tfvars 에 `create_github_oidc_provider = false` 를 넣고 다시 apply 합니다.

## 5. GitHub 설정 (인프라 + 보안, 한 번)

저장소 **Settings → Environments → New environment** 에서 4개를 만들고 변수를 넣습니다.

| Environment | 변수 (Variables 탭) | 보호 규칙 |
|---|---|---|
| `dev-plan` | `AWS_PLAN_ROLE_ARN` = dev 의 `plan_role_arn` | 없음 |
| `prod-plan` | `AWS_PLAN_ROLE_ARN` = prod 의 `plan_role_arn` | 없음 |
| `dev` | `AWS_APPLY_ROLE_ARN` = dev 의 `apply_role_arn` | 선택 |
| `prod` | `AWS_APPLY_ROLE_ARN` = prod 의 `apply_role_arn` | **Required reviewers** 에 인프라·보안 담당자 지정, Deployment branches 를 `main` 으로 제한 |

리전이 서울이 아니면 각 Environment 에 `AWS_REGION` 변수도 넣습니다. 역할 ARN 은 비밀값이 아니라서 Secrets 가 아니라 **Variables** 에 넣습니다.

추가로 권장하는 설정:

- **Settings → Branches → Add rule (`main`)**: PR 필수, 승인 1명 이상, 상태 검사 필수(`fmt`, `validate (...)`, `trivy ...`, `checkov ...`, `ansible-lint + syntax-check`), CODEOWNERS 리뷰 필수
- **Settings → Code security**: Dependabot alerts / security updates 켜기
- 스캔 결과를 **Security → Code scanning** 탭에서 보려면 공개 저장소이거나 GitHub Code Security(유료)가 있어야 합니다. 비공개 저장소에서는 업로드 단계가 경고로만 끝나고, 결과는 워크플로 실행 화면의 **Artifacts**(`trivy-sarif`, `checkov-sarif`)와 로그에서 볼 수 있습니다. HIGH/CRITICAL 판정은 업로드와 상관없이 동작합니다.

변수를 넣기 전에는 plan/apply 단계가 안내 메시지만 남기고 건너뜁니다.

## 6. dev 첫 배포와 서버 설정 (인프라팀)

### 6.1 인프라 만들기

```bash
make tf-init  ENV=dev
make tf-plan  ENV=dev     # 생성될 리소스 확인 (VPC, NAT, EC2, RDS, S3, IAM ...)
make tf-apply ENV=dev     # RDS 생성 때문에 10~15분 걸린다
terraform -chdir=terraform/envs/dev output
```

처음 init 하고 나면 `terraform/envs/dev/.terraform.lock.hcl` 이 생깁니다. 다른 OS 에서도 같은 프로바이더를 쓰도록 다음 명령을 실행한 뒤 커밋합니다.

```bash
terraform -chdir=terraform/envs/dev providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64
```

### 6.2 서버 설정 (Ansible)

1. `artifact_bucket_name` 출력값을 `ansible/inventories/dev/group_vars/all/main.yml` 의 `ansible_aws_ssm_bucket_name` 에 넣습니다.
2. 실행합니다.

   ```bash
   make ansible-deps                      # 롤/컬렉션 설치 (최초 1회, requirements.yml 바뀔 때)
   cd ansible
   ansible-inventory -i inventories/dev --graph          # app 그룹에 i-xxxx 가 보이면 성공
   ansible -i inventories/dev all -m ansible.builtin.ping
   ansible-playbook -i inventories/dev playbooks/site.yml --check --diff   # 미리보기
   ansible-playbook -i inventories/dev playbooks/site.yml --diff          # 적용
   ```

3. 일부만 실행할 때는 태그를 씁니다: `--tags app` (앱만 재배포), `--tags hardening`, `--tags docker`

**앱 설정 바꾸기**: `inventories/<env>/group_vars/all/main.yml` 의 `app_image`, `app_port`, `app_env` 를 바꾸고 `--tags app` 으로 다시 실행합니다.

**비밀값 넣기**: `app_env` 에 비밀번호를 평문으로 넣지 말고 둘 중 하나를 씁니다.

```bash
# 1) ansible-vault
ansible-vault create inventories/dev/group_vars/all/vault.yml   # vault_db_password: ...
#    main.yml 에서 app_env: { DB_PASSWORD: "{{ vault_db_password }}" }
ansible-playbook -i inventories/dev playbooks/site.yml --ask-vault-pass

# 2) AWS Secrets Manager 에서 바로 읽기 (RDS 마스터 비밀번호 등)
#    app_env: { DB_PASSWORD: "{{ (lookup('amazon.aws.secretsmanager_secret', '<secret arn>', region='ap-northeast-2') | from_json).password }}" }
```

서버에 직접 들어가 볼 때: `aws ssm start-session --target <instance-id>`

### 6.3 prod

dev 와 같은 순서이며 `ENV=prod` 로 바꿉니다. 단, 평소에는 로컬에서 prod 를 apply 하지 않고 7단계의 GitHub Actions 수동 실행(승인 필요)으로 반영합니다.

## 7. 일상 작업 흐름 (모두)

```text
브랜치 생성 -> 수정 -> PR -> 자동 검사 + plan 확인 -> 리뷰/승인 -> main 병합
          -> dev 자동 apply -> (필요 시) Actions 에서 prod 수동 실행 -> 승인자 승인 -> prod apply
```

1. `git switch -c feat/<내용>` 으로 브랜치를 만들고 수정합니다. 커밋할 때 pre-commit 이 fmt·lint·시크릿 검사를 먼저 돌립니다.
2. PR 을 열면 다음이 자동으로 실행됩니다.
   - `terraform`: fmt, validate, tflint, dev/prod plan (결과는 각 plan 작업의 **Summary** 탭)
   - `security-scan`: Trivy, Checkov
   - `ansible`: syntax-check, ansible-lint
3. plan 에서 **예상하지 못한 destroy/replace 가 없는지** 확인하고 리뷰를 받습니다. CODEOWNERS 에 따라 담당 팀이 자동으로 리뷰어로 지정됩니다.
4. `main` 에 병합하면 dev 에 자동으로 apply 됩니다.
5. prod 반영: **Actions → terraform → Run workflow → environment: prod** 를 실행하고, 지정된 승인자가 승인하면 apply 됩니다.
6. 서버 설정이 바뀌었으면 Ansible 을 실행합니다 (6.2).

## 8. 보안팀 가이드

| 하고 싶은 일 | 방법 |
|---|---|
| 스캔 결과 보기 | PR 의 `security-scan` 체크, 또는 Security → Code scanning |
| 로컬에서 스캔 | `make scan` (Docker 필요) |
| 예외 허용 (전체) | `.checkov.yaml` 의 `skip-check` 에 ID 와 **사유 주석** 추가 |
| 예외 허용 (리소스 하나) | 리소스 블록 안에 `#checkov:skip=CKV_AWS_xxx:사유` |
| Trivy 예외 | 리소스 위에 `#trivy:ignore:AVD-AWS-xxxx` 또는 저장소 루트에 `.trivyignore` |
| OS/SSH 기준선 변경 | `ansible/inventories/<env>/group_vars/all/hardening.yml` ([변수 목록](https://github.com/dev-sec/ansible-collection-hardening)) |
| CI apply 권한 줄이기 | `terraform/bootstrap` 의 `apply_role_policy_arns` 를 최소 권한 정책으로 교체 후 bootstrap 재적용 |

위 파일들은 CODEOWNERS 로 보안팀 리뷰가 필수입니다.

## 9. 정리(삭제)

```bash
# dev 전체 삭제
terraform -chdir=terraform/envs/dev destroy
```

- prod 는 RDS 삭제 보호가 켜져 있어 바로 지워지지 않습니다. `db_deletion_protection = false` 로 바꿔 apply 한 뒤 destroy 합니다. 삭제 시 최종 스냅샷이 남습니다.
- 부트스트랩(state 버킷, 잠금 테이블)은 모든 환경을 지운 다음 마지막에 지웁니다. 잠금 테이블도 삭제 보호가 켜져 있습니다.
- 로컬 데이터까지 지우려면 `docker compose -f local/docker-compose.yml --env-file local/.env down -v`

## 10. 문제 해결

| 증상 | 원인과 해결 |
|---|---|
| `Warning: Deprecated Parameter "dynamodb_table"` | 정상입니다. Terraform 1.10+ 의 안내 메시지이며 동작에 문제없습니다. 전환 방법은 README 의 4.3 절을 보세요. |
| `Error acquiring the state lock` | 다른 사람이나 CI 가 실행 중입니다. 끝나길 기다리세요. 중단된 작업이 확실할 때만 `terraform force-unlock <ID>` |
| `AccessDenied ... allowed_account_ids` | 다른 계정으로 로그인했습니다. `aws sts get-caller-identity` 로 확인하세요. |
| CI plan 이 "건너뜁니다" 로 끝남 | 해당 Environment 에 `AWS_PLAN_ROLE_ARN` 변수가 없습니다 (5단계). |
| CI 에서 `Not authorized to perform sts:AssumeRoleWithWebIdentity` | bootstrap 의 `github_repository` 가 실제 저장소와 다르거나, apply 를 Environment 밖에서 실행했습니다. |
| `ansible-inventory --graph` 에 호스트가 없음 | AWS 로그인 상태, 리전, `tag:Project` 값(`aws_ec2.yml`)을 확인하세요. 인스턴스가 running 이어야 합니다. |
| Ansible `SSM ... TargetNotConnected` | 인스턴스가 막 생성돼 SSM 에이전트가 아직 등록 전입니다. 2~3분 뒤 다시 시도하거나 Systems Manager → Fleet Manager 에서 상태를 확인하세요. |
| Ansible S3 업로드 오류 | `ansible_aws_ssm_bucket_name` 이 Terraform 출력과 같은지 확인하세요. |
| 로컬 4566 포트 충돌 | floci 와 LocalStack 을 동시에 켰습니다. 하나만 켜세요. |
| `make local-up` 에서 `POSTGRES_PASSWORD` 오류 | `local/.env` 가 없거나 값이 비었습니다. `cp local/.env.example local/.env` |
