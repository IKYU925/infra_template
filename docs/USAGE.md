# 사용 가이드

README 가 "무엇이 들어 있는지"를 설명한다면, 이 문서는 **처음 받은 사람이 실제로 쓰기까지의 순서**를 단계별로 정리합니다.
명령은 저장소 루트에서 실행한다고 가정합니다.

## 0. 전체 흐름 한눈에 보기

| 순서 | 할 일 | 담당 | 얼마나 자주 |
|---|---|---|---|
| 1 | 도구 설치 | 모두 | 한 번 |
| 2 | 템플릿 값 바꾸기 (프로젝트 이름, 계정 ID 등) | 인프라 | 한 번 |
| 3 | 로컬 k3s 클러스터 띄우기 (Vagrant) | 모두 | 매일 |
| 4 | AWS 계정 부트스트랩 (state 버킷, 잠금 테이블, CI 역할) | 인프라 | 계정당 한 번 |
| 5 | GitHub 설정 (Environments, 변수, 승인자) | 인프라 + 보안 | 한 번 |
| 6 | dev EKS 만들기 → Argo CD 설치 | 인프라 | 처음 한 번 |
| 7 | 일상 작업: 브랜치 → PR → 검사·plan → 병합 → Argo CD 반영 | 모두 | 매번 |

로컬만 쓸 사람(풀스택)은 1, 3단계만 하면 됩니다.

---

## 1. 도구 설치

### macOS (Apple Silicon / Intel)

```bash
brew install --cask vagrant virtualbox     # VirtualBox 7.1 이상 (Apple Silicon 지원)
brew install kubectl helm terraform awscli tflint pre-commit
python3 -m venv .venv && source .venv/bin/activate
pip install -r ansible/requirements.txt    # ansible-lint 를 노트북에서 돌릴 때만
pre-commit install
```

Apple Silicon 에서 VirtualBox 가 잘 안 되면 VMware Fusion(무료)을 씁니다.

```bash
brew install --cask vmware-fusion vagrant-vmware-utility
vagrant plugin install vagrant-vmware-desktop
export VAGRANT_DEFAULT_PROVIDER=vmware_desktop
```

### Windows

```powershell
winget install Hashicorp.Vagrant Oracle.VirtualBox Kubernetes.kubectl Helm.Helm Hashicorp.Terraform Amazon.AWSCLI
```

- Ansible 은 노트북에 설치하지 않아도 됩니다. VM 안에서 실행됩니다.
- `make` 가 없으면 이 문서의 명령을 직접 실행하면 됩니다 (`Makefile` 의 각 줄과 같습니다).
- WSL2 나 Docker Desktop 때문에 Hyper-V 가 켜져 있으면 VirtualBox 가 느려질 수 있습니다. 처음에 한 번 `vagrant up` 이 끝까지 되는지 확인하세요.
- 저장소는 `.gitattributes` 로 줄바꿈을 LF 로 고정합니다. 클론하기 전에 `git config --global core.autocrlf input` 을 해 두면 안전합니다.

설치 확인:

```bash
vagrant --version      # 2.4 이상
kubectl version --client
helm version           # v3
terraform version      # 1.11.1 이상
```

## 2. 템플릿 값 바꾸기 (인프라팀, 한 번)

1. 프로젝트 이름 `myproject` 를 한 번에 바꿉니다.

   ```bash
   grep -rl myproject terraform deploy | xargs sed -i '' 's/myproject/<우리프로젝트>/g'   # macOS
   ```

2. AWS 계정 ID 를 바꿉니다.
   - dev: `terraform/envs/dev/terraform.tfvars`, `terraform/bootstrap/dev.tfvars` 의 `111111111111`
   - prod: `terraform/envs/prod/terraform.tfvars`, `terraform/bootstrap/prod.tfvars` 의 `222222222222`
3. `terraform/bootstrap/*.tfvars` 의 `github_repository` 를 실제 저장소로 바꿉니다.
4. `terraform/envs/*/terraform.tfvars` 의 `eks_public_access_cidrs` 에 kubectl 을 쓸 곳의 공인 IP(`curl ifconfig.me` 결과 + `/32`)를, `eks_admin_principal_arns` 에 팀원 IAM 역할 ARN 을 넣습니다.
5. `deploy/argocd/*-root.yaml`, `deploy/argocd/apps/*/{app,platform}.yaml` 의 `repoURL` 을 실제 저장소로 바꿉니다.
6. `.github/CODEOWNERS` 의 `@your-org/...` 를 실제 GitHub 팀이나 사용자로 바꿉니다.

## 3. 로컬 k3s 클러스터 (모두)

### 3.1 띄우기

```bash
make k3s-up        # = cd local/vagrant && vagrant up
```

처음 한 번은 박스 내려받기와 설치 때문에 10~15분 걸립니다. 각 VM 에서 다음이 자동으로 실행됩니다.

1. VM 안에 Ansible 설치
2. `ansible/playbooks/hardening.yml`: dev-sec OS/SSH 하드닝 (보안팀 기준선)
3. `ansible/playbooks/k3s.yml`: k3s 설치. `local-cp-01` 이 컨트롤 플레인, `local-worker-01/02` 가 워커로 합류

| VM | IP | 역할 | 기본 RAM |
|---|---|---|---|
| local-cp-01 | 192.168.56.10 | 컨트롤 플레인 | 2GB |
| local-worker-01 | 192.168.56.11 | 워커 | 2GB |
| local-worker-02 | 192.168.56.12 | 워커 | 2GB |

노트북 사양에 맞게 줄일 수 있습니다: `K3S_WORKERS=1 K3S_WORKER_MEMORY=1536 vagrant up`

### 3.2 kubectl 연결

컨트롤 플레인이 kubeconfig 를 `local/vagrant/.kube/config` 에 내보냅니다.

```bash
export KUBECONFIG=$PWD/local/vagrant/.kube/config        # Windows: $env:KUBECONFIG="$PWD\local\vagrant\.kube\config"
kubectl get nodes -o wide
```

### 3.3 앱 배포

```bash
make local-deploy                 # local/.env 로 DB Secret 생성 -> Helm 으로 앱 + Postgres 배포
curl http://192.168.56.10/        # Traefik(Ingress) 를 거쳐 앱이 응답
```

**우리 앱으로 바꾸기**: 이미지를 노트북에서 빌드하고 VM 에 넣은 뒤, 차트 값을 바꿔 배포합니다. ECR 은 쓰지 않습니다.

```bash
docker build -t myapp:dev ../my-app
make local-image-import IMAGE=myapp:dev
helm upgrade --install app deploy/charts/app -n app -f deploy/charts/app/values-local.yaml \
  --set image.repository=myapp --set image.tag=dev --set containerPort=3000
```

Apple Silicon 노트북에서 빌드한 이미지는 arm64 라서 같은 노트북의 VM 에서 바로 돌아갑니다. dev/prod(EKS)는 amd64 이므로 CI 에서는 `docker buildx build --platform linux/amd64,linux/arm64` 로 빌드합니다.

앱 안에서 쓸 수 있는 값:

| 환경 변수 | local | dev / prod |
|---|---|---|
| `DATABASE_URL` | `postgresql://app:<비번>@postgresql:5432/app` (클러스터 안 Postgres) | RDS 주소 + Secrets Manager 비밀번호 (External Secrets 가 생성) |
| AWS 권한 | 없음 (필요하면 `make local-aws-up` 으로 floci) | Pod Identity 로 아티팩트 버킷 읽기/쓰기 |

### 3.4 끄기와 지우기

```bash
make k3s-halt       # VM 끄기 (다음 make k3s-up 은 1~2분)
make k3s-destroy    # VM 삭제 (토큰과 kubeconfig 는 local/vagrant 에 남는다)
```

### 3.5 (선택) 앱만 빠르게 돌리기

클러스터 없이 앱 코드만 확인할 때는 기존 Docker Compose 를 씁니다: `make local-up` → http://localhost:8080, `make local-down`.
S3 같은 AWS API 가 필요하면 `make local-aws-up` (floci + `terraform/envs/local`).

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

- **Settings → Branches → Add rule (`main`)**: PR 필수, 승인 1명 이상, 상태 검사 필수(`fmt`, `validate (...)`, `trivy ...`, `checkov ...`, `ansible-lint + syntax-check`, `helm lint + kubeconform`), CODEOWNERS 리뷰 필수
- **Settings → Code security**: Dependabot alerts / security updates 켜기
- 스캔 결과를 **Security → Code scanning** 탭에서 보려면 공개 저장소이거나 GitHub Code Security(유료)가 있어야 합니다. 비공개 저장소에서는 업로드 단계가 경고로만 끝나고, 결과는 워크플로 실행 화면의 **Artifacts**(`trivy-sarif`, `checkov-sarif`)와 로그에서 볼 수 있습니다. HIGH/CRITICAL 판정은 업로드와 상관없이 동작합니다.

변수를 넣기 전에는 plan/apply 단계가 안내 메시지만 남기고 건너뜁니다.

## 6. dev 첫 배포 (인프라팀)

### 6.1 인프라 만들기 (Terraform)

```bash
make tf-init  ENV=dev
make tf-plan  ENV=dev     # VPC, NAT, EKS, 노드그룹, RDS, ECR, S3, Pod Identity 역할
make tf-apply ENV=dev     # EKS + RDS 생성 때문에 20~30분 걸린다
terraform -chdir=terraform/envs/dev output
```

처음 init 하고 나면 `.terraform.lock.hcl` 이 생깁니다. 다른 OS 에서도 같은 프로바이더를 쓰도록 다음을 실행한 뒤 커밋합니다.

```bash
terraform -chdir=terraform/envs/dev providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64
```

### 6.2 출력값을 deploy/ 에 옮기기

| terraform output | 넣을 곳 |
|---|---|
| `vpc_id` | `deploy/argocd/apps/dev/aws-load-balancer-controller.yaml` 의 `vpcId` |
| `cluster_name` | 같은 파일의 `clusterName` (기본 `myproject-dev`) |
| `ecr_repository_url` | `deploy/charts/app/values-dev.yaml` 의 `image.repository` |
| `db_address` | `values-dev.yaml` 의 `database.external.host` |
| `db_master_secret_arn` | `values-dev.yaml` 의 `database.external.remoteSecret` |

`values-dev.yaml` 의 `ingress.host` 에 실제 도메인을 넣고, `deploy/platform/cluster-issuer.yaml` 의 이메일을 바꿉니다. 이 변경을 PR 로 올려 `main` 에 병합합니다 (Argo CD 는 `main` 을 봅니다).

### 6.3 Argo CD 설치 (클러스터당 한 번)

```bash
make argocd-bootstrap ENV=dev
```

이 명령은 kubeconfig 를 EKS 로 바꾸고, Argo CD 를 Helm 으로 설치한 뒤 `deploy/argocd/dev-root.yaml` 을 적용합니다. 그러면 Argo CD 가 `deploy/argocd/apps/dev/` 의 Application 을 순서대로 설치합니다.

| 순서(sync-wave) | Application | 하는 일 |
|---|---|---|
| -3 | aws-load-balancer-controller, cert-manager, external-secrets | NLB 생성, 인증서, Secrets Manager 연동 |
| -2 | traefik | Ingress 컨트롤러 + 인터넷용 NLB |
| -1 | platform | ClusterSecretStore, ClusterIssuer (`deploy/platform`) |
| 0 | app | 우리 앱 (`deploy/charts/app` + `values-dev.yaml`) |

저장소가 비공개라면 Argo CD 가 읽을 수 있게 먼저 등록합니다 (GitHub 의 읽기 전용 Deploy key 권장).

```bash
kubectl -n argocd port-forward svc/argocd-server 8443:443        # https://localhost:8443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d   # admin 비밀번호
# 화면의 Settings -> Repositories -> Connect Repo 에서 SSH 키 등록 (repoURL 도 git@github.com:... 로 맞춘다)
```

DNS: `kubectl -n traefik get svc traefik` 의 EXTERNAL-IP(NLB 주소)를 도메인의 CNAME 으로 연결하면 cert-manager 가 인증서를 발급합니다.

### 6.4 prod

같은 순서를 `ENV=prod` 로 반복합니다. 평소 prod 인프라 변경은 로컬이 아니라 7단계의 GitHub Actions 수동 실행(승인 필요)으로 반영합니다. prod 의 `app` Application 은 자동 동기화가 꺼져 있어서, Argo CD 화면에서 변경 내용(Diff)을 확인하고 **Sync** 를 눌러야 배포됩니다.

## 7. 일상 작업 흐름 (모두)

```text
인프라 변경 : 브랜치 -> PR -> 검사 + plan 확인 -> 병합 -> dev 자동 apply -> (Actions 수동 실행 + 승인) prod apply
앱 배포     : 이미지 ECR 푸시 -> values-<env>.yaml 의 image.tag 변경 PR -> 병합 -> Argo CD 가 dev 자동 배포 / prod 는 Sync 클릭
```

1. `git switch -c feat/<내용>` 으로 브랜치를 만들고 수정합니다. 커밋할 때 pre-commit 이 fmt·lint·시크릿 검사를 먼저 돌립니다.
2. 바꾼 내용은 로컬 k3s 에서 먼저 확인합니다 (`make local-deploy`, `make k8s-lint`).
3. PR 을 열면 다음이 자동으로 실행됩니다.
   - `terraform`: fmt, validate, tflint, dev/prod plan (결과는 각 plan 작업의 **Summary** 탭)
   - `k8s`: Helm lint, local/dev/prod 렌더링 + 스키마 검사
   - `ansible`: syntax-check, ansible-lint
   - `security-scan`: Trivy, Checkov
4. plan 에서 **예상하지 못한 destroy/replace 가 없는지** 확인하고 리뷰를 받습니다.
5. `main` 에 병합하면 dev 에 자동 반영됩니다 (Terraform 은 Actions, 클러스터 안은 Argo CD).
6. prod 인프라: **Actions → terraform → Run workflow → environment: prod** 를 실행하고 승인자가 승인합니다.

## 8. 보안팀 가이드

| 하고 싶은 일 | 방법 |
|---|---|
| 스캔 결과 보기 | PR 의 `security-scan` 체크, 또는 Security → Code scanning |
| 로컬에서 스캔 | `make scan` (Docker 필요) |
| 예외 허용 (전체) | `.checkov.yaml` 의 `skip-check` 에 ID 와 **사유 주석** 추가 |
| 예외 허용 (리소스 하나) | 리소스 블록 안에 `#checkov:skip=CKV_AWS_xxx:사유` |
| Trivy 예외 | 리소스 위에 `#trivy:ignore:AVD-AWS-xxxx` 또는 저장소 루트에 `.trivyignore`. 현재 예외: EKS 공개 엔드포인트(IP 제한), 노드 아웃바운드 (`terraform/modules/platform/eks.tf`) |
| OS/SSH 기준선 실습 | `ansible/inventories/local/group_vars/all/hardening.yml` 수정 후 `vagrant provision` ([변수 목록](https://github.com/dev-sec/ansible-collection-hardening)) |
| 파드 AWS 권한 검토 | `terraform/modules/platform/eks.tf` 의 Pod Identity 모듈들 |
| EKS API 를 비공개로 | `eks.tf` 에서 `endpoint_public_access = false` 후 SSM 을 거쳐 접속 |
| CI apply 권한 줄이기 | `terraform/bootstrap` 의 `apply_role_policy_arns` 를 최소 권한 정책으로 교체 후 bootstrap 재적용 |

위 파일들은 CODEOWNERS 로 보안팀 리뷰가 필수입니다.

## 9. 정리(삭제)

```bash
# 1) 클러스터 안의 NLB 를 먼저 지운다 (안 지우면 VPC 삭제가 막힌다)
kubectl -n argocd delete application root               # 자식 Application 을 다시 만들지 않게 먼저 지운다
kubectl -n argocd delete application app traefik --wait  # finalizer 가 Service 와 NLB 까지 지운다
kubectl -n traefik get svc                               # 비어 있으면 OK
# 2) 인프라 삭제
terraform -chdir=terraform/envs/dev destroy
# 로컬
make k3s-destroy
```

- prod 는 RDS 삭제 보호가 켜져 있어 바로 지워지지 않습니다. `db_deletion_protection = false` 로 바꿔 apply 한 뒤 destroy 합니다.
- 부트스트랩(state 버킷, 잠금 테이블)은 모든 환경을 지운 다음 마지막에 지웁니다.

## 10. 문제 해결

| 증상 | 원인과 해결 |
|---|---|
| `vagrant up` 이 박스를 못 찾음 (`architecture`) | Vagrant 2.4 미만입니다. 2.4 이상으로 올리세요. 다른 박스는 `K3S_BOX=<박스>` 로 지정합니다. |
| VirtualBox host-only 네트워크 오류 | VirtualBox 7 은 `192.168.56.0/21` 만 허용합니다. IP 를 바꿨다면 이 범위 안으로 두세요. Apple Silicon 에서 계속 실패하면 VMware Fusion(1장)으로 바꿉니다. |
| 워커가 `NotReady` 거나 안 보임 | 컨트롤 플레인을 먼저 올려야 합니다. `vagrant provision local-worker-01` 로 다시 실행하고, 컨트롤 플레인에서 `sudo journalctl -u k3s -f` 를 확인합니다. |
| 파드끼리 통신이 안 됨 | 하드닝이 IP 포워딩을 껐을 수 있습니다. `hardening.yml` 의 `sysctl_overwrite` 에 `net.ipv4.ip_forward: 1` 이 있는지 확인합니다. |
| `vagrant ssh` 가 안 됨 (하드닝 후) | `hardening.yml` 의 SSH 설정을 확인합니다. 급하면 `group_vars/all/main.yml` 에서 `apply_ssh_hardening: false` 후 VM 을 다시 만듭니다. |
| 로컬 이미지가 `ErrImagePull` | 모든 노드에 넣었는지 확인합니다 (`make local-image-import`). `image.pullPolicy` 가 `IfNotPresent` 인지 확인합니다. |
| Windows 에서 스크립트 오류 (`\r`) | CRLF 로 받았습니다. 1장 Windows 의 마지막 항목을 보세요. |
| `kubectl` 이 EKS 에 `Unauthorized` | 내 IAM 역할이 `eks_admin_principal_arns` 에 없거나 IP 가 `eks_public_access_cidrs` 에 없습니다. |
| Traefik 서비스 EXTERNAL-IP 가 `<pending>` | aws-load-balancer-controller 가 아직 안 떴거나 `vpcId` 가 틀렸습니다. `kubectl -n kube-system logs deploy/aws-load-balancer-controller` |
| 앱 파드가 `CreateContainerConfigError` (app-db 없음) | dev/prod: `database.external.*` 값과 `kubectl get externalsecret -n app` 상태를 확인합니다. local: `make local-secret` |
| `Error acquiring the state lock` | 다른 사람이나 CI 가 실행 중입니다. 끝나길 기다리세요. 중단된 작업이 확실할 때만 `terraform force-unlock <ID>` |
| `AccessDenied ... allowed_account_ids` | 다른 계정으로 로그인했습니다. `aws sts get-caller-identity` 로 확인하세요. |
| CI plan 이 "건너뜁니다" 로 끝남 | 해당 Environment 에 `AWS_PLAN_ROLE_ARN` 변수가 없습니다 (5단계). |
