# aiops-eks 운영

AI_auto_pipeline 4단계를 EKS 클러스터 하나에서 돌리기 위한 AWS 기반이다. 설계는 [plans/aiops-eks-design.md](plans/aiops-eks-design.md), 비용 근거는 [aiops-eks-cost.md](aiops-eks-cost.md)에 있다.

## 두 층으로 나눠 매일 지우는 것만 지운다

| 층 | 경로 | 리소스 | 수명 |
| --- | --- | --- | --- |
| base | `terraform/envs/aiops-eks/base` | ECR `aiops`, Loki S3 버킷, Secrets Manager `ai-incident/aiops`, Pod Identity 역할 3개, 월 예산 50달러 | 프로젝트 기간 내내 |
| cluster | `terraform/envs/aiops-eks/cluster` | VPC, NAT 1개, EKS 1.35, 노드그룹 `app`·`monitoring`(각 t4g.large 1대), 애드온 5개, Pod Identity 연결, ArgoCD 10.17.2, 루트 앱 `aiops-root` | 평일 코어타임에만 |

두 층은 state 파일부터 다르다. cluster 층은 base 층 output 을 `terraform_remote_state` 로 읽는다. 모든 리소스에 `Project=ai-incident` 와 `Layer=base|cluster` 태그가 붙는다. EBS CSI 가 만든 PVC 볼륨에도 같은 태그가 붙는다.

## 처음 한 번 준비한다

맥에 `terraform`(1.11.1 이상), `aws`, `kubectl`, `jq` 가 있어야 한다.

1. `terraform/bootstrap` 이 실제 계정에 적용돼 있는지 확인한다. state 버킷, 잠금 테이블, `gha-apply` 역할을 쓴다.
2. 아래 파일의 `CHANGE_ME`, `111111111111` 을 채운다.
   - `base/backend.hcl`, `cluster/backend.hcl`: bootstrap 의 버킷과 잠금 테이블.
   - `base/terraform.tfvars`: 계정 ID, 예산 알림 메일.
   - `cluster/terraform.tfvars`: 계정 ID, `state_bucket`, `admin_principal_arns`(운영자 주체와 `gha-apply` 역할).
3. Billing 콘솔에서 비용 할당 태그 `Project` 를 활성화한다.
4. `make eks-base-up` 으로 base 층을 만든다.
5. `make eks-secrets AIOPS_ENV=<AI_auto_pipeline>/.env` 로 비밀값을 넣는다. `.env` 에 없는 `AUTOMATION_TOKEN`, `POSTGRES_PASSWORD` 는 무작위로 만들고, 이미 넣은 값은 유지한다. 값은 Terraform state 에 들어가지 않는다.
6. GitHub Environment `dev` 에 변수 `AWS_APPLY_ROLE_ARN` 을 넣는다. 이 변수가 없으면 `eks` 워크플로는 아무것도 하지 않는다.

## 클러스터를 올리고 내린다

- 올리기: `make eks-up`. cluster 층을 apply 하고 노드 2대가 Ready 가 될 때까지 기다린 뒤 output 을 출력한다. 걸린 시간이 `up took` 로그에 남는다.
- kubectl 연결: output 의 `kubeconfig_command` 를 실행한다.
- ArgoCD 화면: `kubectl -n argocd port-forward svc/argocd-server 8080:443`. 초기 비밀번호는 `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`.
- 내리기: `make eks-down`. 끝에 남은 리소스 검사까지 한다.

`eks.sh down` 의 순서는 고정이다. 수동 실행과 스케줄이 같은 스크립트를 부른다.

1. 실행하는 곳의 IP 가 엔드포인트 허용 목록에 없으면 더하고 반영을 기다린다.
2. `aiops-root` 앱을 지운다. finalizer 가 하위 앱과 그 리소스를 지운다. ArgoCD 는 동기화 중인 앱을 지우지 않으므로, 루트 앱이 사라질 때까지(최대 15분) 진행 중인 동기화를 10초마다 끝낸다. 잘못된 이미지 태그나 Pending Pod 로 멈춘 동기화가 삭제를 막지 않는다.
3. LoadBalancer Service 가 있으면 지운다.
4. 모든 PVC 를 지우고 PV 가 사라질 때까지 기다린다. EBS CSI 가 볼륨을 지운다.
5. cluster 층을 `terraform destroy` 한다.
6. `eks.sh leftovers` 로 남은 리소스를 센다. 하나라도 있으면 실패로 끝난다.

2~4단계만 하려면 `KUBECONFIG` 를 맞추고 `eks.sh drain` 을 실행한다. 이 단계를 건너뛰고 destroy 하면 ArgoCD 가 하위 앱을 지우는 동안 helm 삭제 제한 시간(5분)에 걸려 실패한다(floci 에서 확인).

`leftovers` 는 `Project=ai-incident` 중 `Layer=base` 가 아닌 것, `kubernetes.io/cluster/ai-incident` 태그가 붙은 것, VPC CNI 가 만든 ENI 를 센다. 종료된 인스턴스와 삭제된 NAT 는 태그 API 에 한동안 남아도 세지 않는다.

## 스케줄은 코어타임에만 클러스터를 둔다

`.github/workflows/eks.yml` 이 GitHub Actions 에서 `eks.sh` 를 부른다. 맥이 잠들어도 돈다.

| 실행 | 시각 (KST) | 하는 일 |
| --- | --- | --- |
| 올리기 | 평일 09:30 | `eks.sh up`. 저장소 변수 `EKS_SCHEDULE_ENABLED=true` 일 때만 |
| 정리 | 매시 5분 | `eks.sh sweep`. 코어타임 밖이고 cluster 층이 남아 있으면 `eks.sh down` |
| 수동 | 아무 때 | `workflow_dispatch` 로 `up`, `down`, `sweep`, `leftovers` 중 하나 |

- 코어타임은 평일 09:30 부터 12:00 까지다. 이 시간이 아니면 정리 실행이 클러스터를 지운다. 수동으로 올린 클러스터도 마찬가지다.
- 그날 13:00 까지 더 쓰려면 저장소 변수 `EKS_HOLD_UNTIL` 을 `2026-11-17T13:00` 처럼 오늘 날짜와 시각으로 넣는다. 13:00 을 넘는 시각은 13:00 으로 줄인다. 다른 날짜의 값은 무시한다.
- 정리 실행에는 끄는 스위치가 없다. `EKS_SCHEDULE_ENABLED` 는 올리기만 끈다. 실험이 없는 기간에는 이 변수를 `false` 로 둔다.
- 주말에는 올리지 않는다. 공휴일 목록은 없다. 공휴일에는 수동으로 `down` 하거나 전날 `EKS_SCHEDULE_ENABLED` 를 끈다.
- 워크플로는 `concurrency: eks` 하나로 묶여 up 과 down 이 겹치지 않는다. Terraform state 잠금도 그대로 쓴다.
- 정리 실행이 실패하면(down 실패, 남은 리소스 있음) GitHub 이 실패 알림 메일을 보낸다.
- 올리기 시각은 첫 실행에서 잰 "eks-up + ArgoCD 전체 Healthy" 시간만큼 10:00 보다 당긴다. 바꿀 때는 `eks.yml` 의 cron 과 `eks.sh` 의 `UP_AT` 을 함께 바꾼다.

`eks.sh keep-up` 이 코어타임 판단을 한다. `terraform/envs/aiops-eks/eks_test.sh` 가 그 경계값을 검사한다.

## 엔드포인트는 실행하는 곳의 IP 만 허용한다

컨트롤 플레인 엔드포인트는 공개하되 `endpoint_allowed_cidrs` 와 실행하는 곳의 IP(`caller_cidr`)만 허용한다. GitHub Actions 러너는 실행마다 IP 가 바뀐다. 그래서 `eks.sh up` 은 러너 IP 를 `caller_cidr` 로 넘겨 만들고, `eks.sh down` 은 자기 IP 가 목록에 없으면 `aws eks update-cluster-config` 로 더한 뒤 지운다.

엔드포인트를 `0.0.0.0/0` 으로 여는 쪽도 검토했다. IAM 인증이 있어 위험은 작지만, 러너 IP 를 더하는 비용은 down 한 번에 몇 분이다. 이 정도 시간을 아끼려고 노출면을 넓힐 이유가 없다고 판단했다. GitHub 러너의 IP 대역은 EKS 허용 목록 한도(40개)보다 많아 고정 목록으로는 해결되지 않는다.

## AI_auto_pipeline 과의 계약

이름을 바꾸려면 AI_auto_pipeline P2 매니페스트와 함께 바꾼다.

- cluster 층 output: `cluster_name`, `region`, `account_id`, `ecr_repository_url`, `loki_bucket_name`, `aiops_secret_name`, `kubeconfig_command`.
- 노드 라벨: `workload=app`, `workload=monitoring`. 두 노드그룹 모두 첫 번째 AZ 의 프라이빗 서브넷에 고정한다.
- Pod Identity: `external-secrets/external-secrets`(비밀 `ai-incident/*` 읽기), `monitoring/loki`(Loki 버킷 읽기·쓰기·목록), `kube-system/ebs-csi-controller-sa`(EBS CSI 애드온).
- 루트 앱 `aiops-root`: `deploy/argocd` 를 `argocd_root_revision`(기본 `main`)으로 본다. `valuesObject` 로 `targetRevision`, `region`, `ecrRepositoryUrl`, `lokiBucket` 을 넘기고, `image_tag` 변수를 채우면 `imageTag` 도 넘긴다.
- 하위 앱에도 `resources-finalizer.argocd.argoproj.io` finalizer 가 있어야 루트 앱 삭제 때 하위 리소스가 지워진다.

## 로컬에서 검증한다

`.claude/skills/verify-infra` 의 `drive aiops-eks` 가 floci 에 두 층을 apply 한다. floci 는 EKS 를 k3s 컨테이너로 띄우므로 ArgoCD 설치와 루트 앱까지 확인한다. 실제 노드, NAT, Pod Identity 자격 증명 주입, `eks.sh up`·`down` 은 실제 계정에서만 확인된다.

## 프로젝트를 끝낸다

1. `make eks-down` 으로 cluster 층을 지우고 `leftovers: 0` 을 확인한다.
2. 저장소 변수 `EKS_SCHEDULE_ENABLED` 를 지운다.
3. `terraform -chdir=terraform/envs/aiops-eks/base destroy` 로 base 층을 지운다. ECR 이미지, Loki 로그, 비밀까지 지워진다.
4. 콘솔에서 `Project=ai-incident` 리소스가 0개인지 확인하고 [aiops-eks-cost.md](aiops-eks-cost.md)의 실측 기록을 채운다.
