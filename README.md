# infra_template

풀스택·보안·인프라 세 팀이 함께 쓰는 **인프라 구성 자동화 템플릿**입니다.
운영(dev/prod)은 AWS **EKS**, 로컬은 노트북의 **Vagrant VM 3대 + k3s** 로 비슷한 Kubernetes 환경을 만듭니다.
Terraform 이 AWS 리소스를, Ansible 이 로컬 VM(하드닝 + k3s 설치)을, Helm 과 Argo CD 가 클러스터 안의 앱을 맡습니다.

> **처음 쓰신다면 [사용 가이드(docs/USAGE.md)](docs/USAGE.md) 를 순서대로 따라 하세요.**

| 환경 | 어디서 | 클러스터 | 배포 |
|---|---|---|---|
| **local** | 개발자 노트북 | Vagrant VM 3대 (컨트롤 플레인 1 + 워커 2) 위 k3s | `helm` 으로 직접 (`make local-deploy`) |
| **dev** | AWS (dev 계정) | EKS, 관리형 노드 2대 | Argo CD 자동 동기화 |
| **prod** | AWS (prod 계정) | EKS, 관리형 노드 3대 (AZ 3개) | Argo CD, 앱은 **수동 Sync (사람 승인)** |

---

## 1. 로컬과 운영이 같은 점, 다른 점

똑같이 만들 수는 없으니, **앱이 보는 환경은 같게** 하고 AWS 에만 있는 부분은 비슷한 것으로 바꿨습니다.

| 항목 | local (Vagrant + k3s) | dev / prod (EKS) |
|---|---|---|
| Kubernetes 버전 | k3s `v1.36.6+k3s1` | EKS `1.36` (같은 마이너) |
| 노드 OS | Ubuntu 24.04 VM + Ansible 하드닝(dev-sec) | AWS 관리형 AL2023 |
| Ingress | Traefik (k3s 기본) | Traefik + NLB (AWS Load Balancer Controller) |
| TLS | 없음 (HTTP) | cert-manager + Let's Encrypt |
| 앱 배포 | 같은 Helm 차트 `deploy/charts/app` + `values-local.yaml` | 같은 차트 + `values-dev.yaml` / `values-prod.yaml` |
| DB | 클러스터 안 Postgres 17 (StatefulSet) | RDS PostgreSQL 17 |
| DB 비밀번호 | `local/.env` → k8s Secret | Secrets Manager → External Secrets → k8s Secret |
| 이미지 | 노트북에서 빌드 → VM 에 바로 넣기 (`make local-image-import`) | ECR |
| NetworkPolicy | k3s 내장 컨트롤러로 적용 | VPC CNI 네트워크 정책으로 적용 |
| CPU | 노트북에 따라 arm64(Apple Silicon) 또는 amd64 | amd64 (t3) → **이미지는 멀티 아키텍처로 빌드** |

## 2. 폴더 구조

```text
.
├── terraform/
│   ├── bootstrap/            # 계정당 1회: state 버킷 + 잠금 테이블 + GitHub OIDC 역할
│   ├── modules/platform/     # 환경 공통 스택: VPC, EKS, RDS, S3, ECR, Pod Identity
│   └── envs/{local,dev,prod} # local 은 floci(로컬 AWS 에뮬레이터)용 S3/Secrets Manager
├── ansible/                  # 로컬 VM 전용: 하드닝 -> k3s 설치
│   ├── inventories/local/    # VM 3대 (IP 는 Vagrantfile 과 같게)
│   ├── playbooks/            # site.yml = hardening.yml -> k3s.yml
│   └── roles/k3s/            # k3s 바이너리(체크섬 검증) + systemd 설치
├── local/
│   ├── vagrant/Vagrantfile   # VM 3대. macOS(Apple Silicon/Intel), Windows 공통
│   └── docker-compose.yml    # (선택) 앱만 빠르게 돌릴 때, floci 로컬 AWS
├── deploy/
│   ├── charts/app/           # 앱 Helm 차트 + values-{local,dev,prod}.yaml
│   ├── argocd/               # Argo CD 설치값, {dev,prod}-root.yaml, apps/{dev,prod}/
│   └── platform/             # ClusterSecretStore, ClusterIssuer
├── .github/workflows/        # terraform, k8s, ansible, security-scan
├── docs/USAGE.md             # 단계별 사용 가이드
└── Makefile                  # make help
```

## 3. 팀별 역할

| 팀 | 주로 보는 곳 | 하는 일 |
|---|---|---|
| **인프라** | `terraform/`, `deploy/argocd`, `deploy/platform`, `local/vagrant`, `.github/workflows` | 클러스터·네트워크, Argo CD, plan 리뷰, prod 승인 |
| **보안** | `ansible/inventories/local/group_vars/all/hardening.yml`, `.checkov.yaml`, `trivy.yaml`, `terraform/bootstrap`, Pod Identity 권한 | 하드닝 기준선 실습, 스캔 정책, IAM 최소 권한 |
| **풀스택** | `deploy/charts/app/`, `local/` | 앱 이미지·환경 변수, 로컬 배포 |

리뷰 담당은 `.github/CODEOWNERS` 에 있습니다. `@your-org/...` 를 실제 팀 이름으로 바꾸세요.

## 4. 사용한 오픈소스 (모두 버전 고정, 2026-11-06 기준)

| 구분 | 이름 | 버전 |
|---|---|---|
| Terraform | Terraform CLI / hashicorp/aws | 1.17.1 / `~> 6.71` |
| | terraform-aws-modules: eks / eks-pod-identity / ecr | 21.29.0 / 2.10.0 / 3.2.1 |
| | terraform-aws-modules: vpc / security-group / rds / s3-bucket / iam / dynamodb-table | 6.7.3 / 6.0.0 / 7.2.2 / 5.17.0 / 6.8.2 / 5.5.2 |
| Kubernetes | k3s (로컬) / EKS | v1.36.6+k3s1 / 1.36 |
| Helm 차트 (Argo CD 가 설치) | argo-cd / aws-load-balancer-controller / traefik / cert-manager / external-secrets | 10.14.0 / 3.6.2 / 42.3.0 / v1.21.3 / 2.14.0 |
| 로컬 VM | Vagrant / 박스 | 2.4 이상 / `bento/ubuntu-24.04` (arm64·amd64) |
| Ansible | ansible-core (VM 안) / devsec.hardening / community.general / ansible.posix | 2.21.6 / 11.0.0 / 13.5.0 / 2.2.2 |
| 보안 스캔 | Trivy / Checkov | trivy-action 0.36.0 / checkov-action 12.3136.0 |
| 로컬 AWS | floci (기본) / LocalStack (선택) | 2.4.0 / 4.14.0 |

GitHub Actions 는 태그 대신 **커밋 SHA 로 고정**했습니다. 버전 업데이트는 Dependabot 이 PR 로 올립니다.

## 5. 빠른 시작

### 5.1 로컬 (Vagrant + k3s)

필요한 것: Vagrant 2.4+, VirtualBox 7.1+ (또는 VMware Fusion/Workstation), kubectl, helm. RAM 은 VM 이 약 6GB 를 씁니다.

```bash
make k3s-up                                   # VM 3대 생성 + 하드닝 + k3s (처음 10~15분)
export KUBECONFIG=$PWD/local/vagrant/.kube/config
kubectl get nodes                             # local-cp-01, local-worker-01, local-worker-02 가 Ready
make local-deploy                             # 앱 + Postgres 배포 -> http://192.168.56.10
```

노트북 사양이 낮으면 `K3S_WORKERS=1 K3S_WORKER_MEMORY=1536 make k3s-up` 처럼 줄일 수 있습니다.

### 5.2 dev / prod (EKS)

```bash
make tf-init ENV=dev && make tf-plan ENV=dev && make tf-apply ENV=dev   # VPC, EKS, RDS, ECR (20~30분)
make argocd-bootstrap ENV=dev                                           # Argo CD 설치 + app-of-apps 등록
```

그 다음부터는 Git 에 병합하면 Argo CD 가 클러스터에 반영합니다. 자세한 순서는 [USAGE.md](docs/USAGE.md) 6~7단계를 보세요.

| 항목 | dev | prod |
|---|---|---|
| VPC CIDR / AZ | 10.10.0.0/16, 2 AZ | 10.20.0.0/16, 3 AZ |
| NAT 게이트웨이 | 1개 (비용 절감) | AZ 마다 1개 |
| EKS 노드 | t3.medium × 2 (최대 3) | t3.medium × 3 (최대 6) |
| RDS | db.t4g.micro, 단일 AZ, 백업 3일 | db.t4g.medium, Multi-AZ, 백업 30일, 삭제 보호 |
| 앱 배포 | 병합하면 자동 | Argo CD 화면에서 Sync (수동) |

> **비용 주의**: EKS 컨트롤 플레인은 클러스터당 시간 요금이 붙습니다. 실습이 끝나면 dev 를 `terraform destroy` 하세요.

## 6. 아키텍처와 보안 기본값

- **네트워크**: public / private / database 서브넷 3계층. EKS 노드는 private, RDS 는 database 서브넷. 기본 SG 는 모든 트래픽 차단, VPC Flow Log 활성화.
- **EKS**: API 엔드포인트는 공개하되 `eks_public_access_cidrs` 의 IP 만 허용 (0.0.0.0/0 은 변수 검증으로 막음). 컨트롤 플레인 로그 5종 CloudWatch 전송, Secret KMS 암호화. 접근 권한은 EKS Access Entry.
- **파드 권한**: 장기 키 없이 **EKS Pod Identity**. AWS LB Controller, EBS CSI, External Secrets(RDS 비밀번호 시크릿 하나만), 앱(아티팩트 버킷만)에 각각 최소 권한 역할.
- **RDS**: PostgreSQL 17, 마스터 비밀번호는 Secrets Manager 가 생성·관리, SSL 강제, 노드 SG 에서만 5432 허용.
- **앱 파드**: non-root, read-only 루트 FS, 모든 capability 제거, seccomp RuntimeDefault, NetworkPolicy 로 Ingress 컨트롤러에서 오는 트래픽만 허용.
- **로컬 VM**: dev-sec `os_hardening` + `ssh_hardening`. k3s 가 필요한 IP 포워딩만 예외로 켭니다.
- **CI**: GitHub OIDC (장기 키 없음). PR plan 은 읽기 전용 역할, apply 는 승인 규칙이 걸린 GitHub Environment 에서만.

## 7. CI/CD (GitHub Actions)

| 워크플로 | 언제 | 하는 일 |
|---|---|---|
| `terraform.yml` | `terraform/**` 변경 PR / main 푸시 / 수동 | fmt, validate, tflint, dev/prod plan / dev apply / 선택 환경 apply (prod 승인 필요) |
| `k8s.yml` | `deploy/**` 변경 PR | Helm lint, local/dev/prod 렌더링 + kubeconform(CRD 포함) 스키마 검사 |
| `ansible.yml` | `ansible/**`, `local/vagrant/**` 변경 PR | syntax-check, ansible-lint(production 프로필) |
| `security-scan.yml` | 모든 PR, main, 매주 월요일 | Trivy(Terraform 모듈 내부 + Helm/K8s 매니페스트 + 시크릿, HIGH 이상 실패), Checkov |

앱 배포 흐름: 앱 저장소 CI 가 이미지를 ECR 에 올림 → `values-<env>.yaml` 의 `image.tag` 를 바꾸는 PR → 병합 → Argo CD 가 배포.

## 8. 처음 쓸 때 바꿀 것 체크리스트

- [ ] `myproject` → 실제 프로젝트 이름 (`terraform.tfvars`, `bootstrap/*.tfvars`, `deploy/argocd/apps/*/aws-load-balancer-controller.yaml`)
- [ ] AWS 계정 ID `111111111111` / `222222222222`, `backend.hcl` 의 버킷·테이블 (bootstrap 출력)
- [ ] `eks_public_access_cidrs` 에 kubectl 을 쓸 공인 IP, `eks_admin_principal_arns` 에 팀원 IAM 역할
- [ ] `deploy/argocd` 의 `repoURL` (템플릿을 복사한 저장소), 비공개 저장소면 Argo CD 에 저장소 인증 등록
- [ ] `deploy/argocd/apps/*/aws-load-balancer-controller.yaml` 의 `vpcId` (terraform output `vpc_id`)
- [ ] `deploy/charts/app/values-{dev,prod}.yaml` 의 `image.repository`, `ingress.host`, `database.external.*` (terraform output)
- [ ] `deploy/platform/cluster-issuer.yaml` 의 이메일
- [ ] CODEOWNERS 팀 이름, GitHub Environments(`dev-plan`, `prod-plan`, `dev`, `prod`)와 prod 승인자
- [ ] 첫 `terraform init` 후 `.terraform.lock.hcl` 커밋 (`terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`)
