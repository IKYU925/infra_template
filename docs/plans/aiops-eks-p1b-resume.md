# infra_template P1b 이어서 하기 (2026-11-16 기준)

설계는 `docs/plans/aiops-eks-design.md`, 운영은 `docs/aiops-eks.md`, 비용은 `docs/aiops-eks-cost.md` 에 있다. 이 문서는 P1b 를 다른 맥에서 이어서 하기 위해 한 일과 남은 일만 적는다.

## 상태

- 코드는 전부 main 에 병합됐다. PR #22 (`f1a6baf`). 로컬에만 있는 변경은 없다.
- 원격 브랜치는 `main` 하나. 저장소 설정 "병합 후 브랜치 자동 삭제"를 켰다.
- 완료 기준 1번(floci apply)은 끝났다. `verify-infra` 의 `drive aiops-eks`, `drive tf-static` 통과.
- 완료 기준 2번(실제 계정 up → 노드 Ready → down → 남은 리소스 0), 3번(코어타임 스케줄 하루 동작)은 아직이다. 운영자 승인이 필요하다.
- `eks` 워크플로는 main 에서 켜져 있지만, `AWS_APPLY_ROLE_ARN` 이 없어 매시 정리 실행이 아무것도 하지 않고 끝난다. 과금 없음.

## 새 맥북 준비

1. `git clone https://github.com/IKYU925/infra_template.git` 후 `main`.
2. 필요한 도구: Docker Desktop, `gh`(로그인), `aws` CLI, `kubectl`, `jq`, `terraform` 1.11.1 이상(`brew install terraform`). 검증 스킬은 terraform 을 컨테이너로 돌려 호스트 설치가 없어도 된다. 실제 계정 실행(`make eks-*`)에는 호스트 terraform 이 필요하다.
3. 실제 계정 자격 증명을 설정한다(`aws sts get-caller-identity` 가 성공해야 한다). 이 맥북에서는 자격 증명이 만료돼 있었다.
4. Claude Code 에서 이 파일(`docs/plans/aiops-eks-p1b-resume.md`)을 넘기며 "이어서 해" 라고 하면 된다.

## 진행 (2026-11-17)

- 새 맥에 `aws` 2.40.3, `terraform` 1.17.2(`hashicorp/tap`) 를 설치했다.
- 계정과 자격 증명 준비(docs/aiops-eks.md "계정과 자격 증명을 준비한다")를 마쳤다. CLI 는 `AdministratorAccess` 가 붙은 IAM 사용자로 동작하고, 루트와 IAM 사용자 모두 MFA 가 켜져 있다.
- 남은 것: 루트 액세스 키가 아직 있다(`AccountAccessKeysPresent=1`). 콘솔에서 삭제해야 한다.
- `terraform/bootstrap/dev.tfvars` 의 `github_repository` 를 실제 저장소로 바꿨다. 계정 ID 는 아직 `111111111111` 이다.
- 노드 타입은 t4g.large 로 둔다. 첫 실계정 실행에서 메모리 사용량을 측정한 뒤 t4g.medium 을 다시 본다.
- 예산 알림은 base 층의 `aws_budgets_budget` 이 만든다. `budget_email` 은 공개 저장소에 커밋하지 않고 `TF_VAR_budget_email` 로 넘긴다.

## 다음 할 일 (순서대로)

1. 운영자 준비 (docs/aiops-eks.md "처음 한 번 준비한다")
   - `terraform/bootstrap` 실제 계정에 적용 (state 버킷, 잠금 테이블, GitHub OIDC `gha-apply` 역할)
   - `terraform/envs/aiops-eks/{base,cluster}/backend.hcl`, `terraform.tfvars` 의 `CHANGE_ME`, `111111111111` 채우기. cluster 의 `admin_principal_arns` 에 운영자 주체와 `gha-apply` 역할
   - Billing 에서 비용 할당 태그 `Project` 활성화
   - GitHub Environment `dev` 에 변수 `AWS_APPLY_ROLE_ARN`
2. `make eks-base-up`, `make eks-secrets AIOPS_ENV=<AI_auto_pipeline>/.env`
3. `make eks-up` → 노드 Ready 확인, `up took` 시간 기록 → `make eks-down` → `leftovers: 0` 확인 (완료 기준 2)
4. 결과 output 값을 AI_auto_pipeline 세션에 전달 (cluster_name, region, account_id, ecr_repository_url, loki_bucket_name, aiops_secret_name, kubeconfig_command)
5. 올리기 cron 시각 조정: 측정한 "up + ArgoCD 전체 Healthy" 시간만큼 09:30 에서 당긴다. `eks.yml` cron 과 `eks.sh` 의 `UP_AT` 을 함께 바꾼다
6. 저장소 변수 `EKS_SCHEDULE_ENABLED=true` 로 스케줄을 켜고 하루 동작 확인 (완료 기준 3)
7. `docs/aiops-eks-cost.md` 실측 칸 채우기, 요금 계산기 공유 링크 추가

## 결정 대기

- 노드 타입: 기본 t4g.large (예산 안. 코어타임 하루 1.37달러 추정). t4g.medium + prefix delegation 이면 하루 0.29달러 절약, 메모리 여유 40%.
- 스케줄을 실제 계정에서 켜는 시점: 운영자 승인 뒤.

## 하다 만 일

- `verify-infra` 스킬(SKILL.md, features/*.md) 한글화. 시작 전에 멈췄고 바꾼 파일은 없다. 명령, 경로, 로그 문자열은 그대로 두고 설명만 한글로 옮기면 된다. 끝나면 `launch → doctor → drive local-aws → cleanup` 한 번 돌려 확인.

## 알아 둘 것

- 비용 추정 근거: AWS Price List 공개 파일(서울). EKS 0.10, t4g.large 0.0832, NAT 0.059 + 0.059/GB, 공인 IPv4 0.005 (USD/시간). NAT 데이터 하루 3GB, PVC 40GB 는 가정.
- `eks.sh down` 은 루트 앱 삭제 후 진행 중인 ArgoCD 동기화를 끝내야 한다(floci 에서 확인). 그렇지 않으면 helm 삭제가 5분 제한에 걸린다.
- floci 검증은 docker 소켓을 floci 에 마운트한다. 실제 노드, NAT, Pod Identity 자격 증명 주입, EBS, `eks.sh up/down` 은 실제 계정에서만 확인된다.
- 브랜치는 squash 병합이라 병합 후 로컬 브랜치는 `git switch main && git pull && git branch -D <브랜치>` 로 정리한다.
