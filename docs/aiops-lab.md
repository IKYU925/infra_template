# aiops-lab (AI_auto_pipeline 4단계 실습 환경)

AI_auto_pipeline 의 4단계(plan.md 10)를 위한 AWS 환경입니다. 자동화 본체는 로컬 K3s 에 그대로 두고, **감지 수단과 알림 입구만 AWS 로 바꿔도** 감지부터 Slack 회신까지 이어지는지 확인하는 용도입니다.
AWS 리소스 정의는 모두 이 저장소의 `terraform/envs/aiops-lab` 에 있고, AI_auto_pipeline 쪽에는 없습니다.

실습이 끝나면 destroy 해서 **과금 리소스 0개**로 돌려놓는 것을 전제로 합니다. 그래서 state 도 S3 가 아닌 로컬 파일(`terraform/envs/aiops-lab/terraform.tfstate`)에 둡니다. 이 파일은 destroy 전까지 지우지 마세요.

명령은 저장소 루트에서 실행한다고 가정합니다.

## 1. 무엇이 만들어지나

```text
EC2(shopapi 컨테이너) --docker awslogs--> 로그 그룹 /ai-incident/shopapi --ERROR 지표 필터--+
EC2(CloudWatch Agent) --disk_used_percent------------------------------------------------+--> CloudWatch 경보
                                                                                             |
                                       로컬 자동화 <-- SQS <-- EventBridge 규칙 <-- 경보 상태 변경
```

| 리소스 | 이름(기본값) | 비고 |
|---|---|---|
| VPC, 퍼블릭 서브넷 1개, IGW | `ai-incident-lab` | `10.40.0.0/16`. dev(`10.10.0.0/16`)와 겹치지 않음 |
| 보안 그룹 | `ai-incident-lab` | 인바운드 없음, 아웃바운드 443 만 |
| EC2 1대 | `ai-incident-lab` | `t4g.small`(arm64), Amazon Linux 2023, IMDSv2, 암호화 gp3 20GiB(`root_volume_size`). user_data 가 Docker 와 CloudWatch Agent 만 설치 |
| SSM 파라미터 | `AmazonCloudWatch-ai-incident-lab` | CloudWatch Agent 설정 (루트 디스크 사용률) |
| ECR 저장소 | `ai-incident-lab/shopapi` | 태그 변경 불가(IMMUTABLE), push 시 스캔 |
| 로그 그룹 | `/ai-incident/shopapi` | 보존 3일 |
| CloudWatch 경보 2개 | `tenant-a-shopapi-ErrorLogs`, `tenant-a-shopapi-DiskUsageHigh` | 아래 3절 |
| EventBridge 규칙 | `ai-incident-lab-alarm-state-change` | 위 경보 2개의 상태 변경만 SQS 로 보냄 |
| SQS | `ai-incident-lab-alarms` | SSE, 보존 4일, 가시성 제한 300초 |
| IAM 사용자 | `ai-incident-lab-automation` | SQS 읽기·삭제, 로그 조회만. 액세스 키는 Terraform 밖에서 만든다 |
| AWS Budgets | `ai-incident-lab-monthly` | 월 10 USD. 실제 80%, 예상 100% 에서 메일 |

모든 리소스에 `Project=ai-incident` 태그가 붙습니다 (provider `default_tags`).

**일부러 만들지 않는 것**: NAT 게이트웨이, 로드밸런서, RDS. EC2 는 퍼블릭 IP 로 IGW 를 거쳐 SSM, ECR, CloudWatch 에 나가고, 들어오는 포트는 하나도 없습니다. 접속은 SSM Session Manager 로만 합니다. 자동화가 SQS 를 가져가는 방식이라 공개 주소도 필요 없습니다.

## 2. 비용

켜 두는 동안 시간 단위로 나가는 것은 다음과 같습니다. 금액은 리전과 시점마다 다르니 **실행 전에 [AWS 요금 계산기](https://calculator.aws/)로 확인**하세요.

- EC2 `t4g.small` 시간당 요금 + 루트 EBS
- 퍼블릭 IPv4 주소 시간당 요금 (인스턴스에 붙은 퍼블릭 IP 도 과금 대상)
- CloudWatch: 사용자 지정 지표(디스크, ERROR 수), 경보 2개, 로그 수집·저장, Logs Insights 쿼리가 스캔한 양
- ECR 저장 용량, SQS·EventBridge 요청 (실습 규모에서는 작음)

`budget_limit_usd`(기본 10) 를 넘을 것 같으면 메일이 옵니다. 다 쓰고 나면 바로 6절대로 지우세요.

## 3. 자동화(AI_auto_pipeline)와의 약속

자동화의 SQS 어댑터는 아래 값만 알면 됩니다. 모두 `terraform -chdir=terraform/envs/aiops-lab output` 에 나옵니다.

| Terraform 출력 | 자동화 쪽 환경 변수 (제안) | 쓰임 |
|---|---|---|
| `region` | `AWS_REGION` | SQS, Logs 클라이언트 리전 |
| `sqs_queue_url` | `AIOPS_SQS_QUEUE_URL` | 경보 메시지를 ReceiveMessage / DeleteMessage |
| `log_group_name` | `AIOPS_LOG_GROUP` | ErrorLogs 경보 때 Logs Insights 로 스택트레이스 조회 |
| `automation_user_name` | (없음) | 이 사용자의 액세스 키를 `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` 로 넣는다 |
| `alarm_names` | (없음) | 확인용. alertname -> 경보 이름 |

**경보 이름 규칙**은 `<tenant>-<service>-<alertname>` 입니다 (plan.md 10-2). 기본값은 `tenant-a-shopapi-ErrorLogs`, `tenant-a-shopapi-DiskUsageHigh`.

> **주의**: 고객사 이름 `tenant-a` 자체에 하이픈이 들어 있습니다. 왼쪽부터 자르면 `tenant` / `a` / `shopapi-ErrorLogs` 로 깨집니다. 서비스와 alertname 에는 하이픈을 쓰지 않으니 **오른쪽부터 두 번만** 자르세요.
>
> ```python
> tenant, service, alertname = alarm_name.rsplit("-", 2)
> ```

| alertname | 감지 | 시나리오 |
|---|---|---|
| `ErrorLogs` | 로그 그룹의 `"ERROR"` 지표 필터 -> `AiIncident/shopapiErrorCount` 합계 1 이상(1분) | S18 코드 버그 |
| `DiskUsageHigh` | CloudWatch Agent `CWAgent/disk_used_percent` (`InstanceId`, `path=/`, `fstype=xfs`) 최대값 90 이상, 2분 연속 | S19 디스크 부족 |

**SQS 메시지 본문**은 EventBridge 의 표준 `CloudWatch Alarm State Change` 이벤트 JSON 그대로입니다 (`detail-type`, `resources` 에 경보 ARN, `detail.alarmName`, `detail.state.value`, `detail.previousState`, `detail.configuration.metrics`). 별도 변환은 하지 않습니다.

상태가 바뀔 때마다 메시지가 오므로 `ALARM`, `OK` 외에 `INSUFFICIENT_DATA` 도 옵니다. apply 직후 경보가 `INSUFFICIENT_DATA` -> `OK` 로 바뀌는 메시지도 오니, 어댑터는 접수한 적 없는 경보의 `OK` 와 `INSUFFICIENT_DATA` 를 지우고 넘어가면 됩니다.

## 4. 만들기

### 4.1 값 넣기

`terraform/envs/aiops-lab/terraform.tfvars` 의 TODO 두 개를 채웁니다.

```hcl
allowed_account_ids = ["123456789012"]    # 실습 계정 ID
budget_email        = "me@example.com"    # 예산 알림 받을 메일
```

경보 이름의 고객사나 서비스를 바꾸려면 `tenant`, `service` 를 함께 넣습니다 (`variables.tf` 참고).

### 4.2 apply

```bash
aws sts get-caller-identity               # 실습 계정으로 로그인했는지 확인
make tf-init  ENV=aiops-lab
make tf-plan  ENV=aiops-lab               # NAT, LB, RDS 가 없는지 확인
make tf-apply ENV=aiops-lab
terraform -chdir=terraform/envs/aiops-lab output
```

인스턴스가 뜬 뒤 2~3분 지나면 Systems Manager → Fleet Manager 에 보이고, CloudWatch 지표 `CWAgent` 에 `disk_used_percent` 가 생깁니다.

### 4.3 자동화용 액세스 키 만들기

비밀이 Terraform state 에 남지 않도록 키는 CLI 로 만듭니다. 출력된 `SecretAccessKey` 는 다시 볼 수 없으니 바로 자동화의 Secret 에 넣으세요.

```bash
USER_NAME=$(terraform -chdir=terraform/envs/aiops-lab output -raw automation_user_name)
aws iam create-access-key --user-name "$USER_NAME"
```

### 4.4 이미지 올리기

EC2 가 arm64 이므로 이미지도 `linux/arm64` 여야 합니다. AI_auto_pipeline 의 `scripts/build_push.sh` 가 이미 `--platform linux/arm64` 로 빌드합니다. 로컬에 있는 그 이미지를 ECR 로 다시 태그해 올립니다.

```bash
REPO=$(terraform -chdir=terraform/envs/aiops-lab output -raw ecr_repository_url)
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin "${REPO%%/*}"

docker tag <로컬 이미지, 예: 192.168.56.10:30500/aiops:base-abc1234> "$REPO:base-abc1234"
docker push "$REPO:base-abc1234"
```

저장소는 태그 변경 불가(IMMUTABLE)라서 **같은 태그를 두 번 올릴 수 없습니다**. 버그를 주입한 이미지는 다른 태그(`s01-...`)로 올리세요. `build_push.sh` 의 태그 규칙을 그대로 쓰면 자연히 달라집니다.

### 4.5 앱 띄우기

```bash
terraform/envs/aiops-lab/lab.sh deploy "$REPO:base-abc1234"
```

SSM Run Command 로 인스턴스에서 ECR 로그인 → 기존 컨테이너 삭제 → 새 컨테이너 실행을 하고, 명령의 출력과 상태를 보여 줍니다. 실패하면 0 이 아닌 값으로 끝납니다. 컨테이너 로그는 docker `awslogs` 드라이버로 `/ai-incident/shopapi` 의 `shopapi` 스트림에 쌓입니다.

이미지를 바꿀 때도 같은 명령을 다시 실행합니다. 인스턴스는 교체되지 않습니다.

인스턴스 안을 직접 보려면:

```bash
aws ssm start-session --target "$(terraform -chdir=terraform/envs/aiops-lab output -raw instance_id)"
```

## 5. 시나리오 실행 시 참고

- **S18 (ErrorLogs)**: 버그 이미지를 4.4~4.5 로 배포하고 요청을 보내 ERROR 로그를 냅니다. 인바운드가 없으므로 요청은 SSM 세션 안에서 `curl localhost:8100/...` 로 보내거나 `aws ssm start-session --document-name AWS-StartPortForwardingSession --parameters portNumber=8100,localPortNumber=8100` 로 포트를 끌어와서 보냅니다.
- **S19 (DiskUsageHigh)**: SSM 세션에서 루트 볼륨을 채웁니다 (예: `fallocate`). 지표가 1분 주기라 경보까지 최소 2분 걸립니다. 끝나면 만든 파일을 지워 `OK` 로 돌려놓으세요.

## 6. 지우기 (끝나면 반드시)

```bash
terraform -chdir=terraform/envs/aiops-lab destroy
terraform/envs/aiops-lab/lab.sh leftovers
```

`lab.sh leftovers` 는 `Project=ai-incident` 태그가 남은 리소스(Resource Groups Tagging API)와, 태그 API 에 잘 안 잡히는 IAM 사용자·역할, Budgets 를 이름으로 한 번 더 확인합니다. 남은 개수를 출력하고 하나라도 있으면 1 로 끝납니다.

- ECR 저장소는 이미지가 남아 있어도 지워집니다 (`force_delete`). IAM 사용자도 액세스 키가 남아 있어도 지워집니다 (`force_destroy`).
- 방금 종료된 EC2 처럼 지운 직후의 리소스가 태그 API 에 잠시 더 보일 수 있습니다. 몇 분 뒤 다시 실행해서 0 이 되는지 보세요.

마지막으로 4.3 에서 만든 키를 자동화 설정에서도 지웁니다. destroy 가 사용자와 키를 함께 지웠으므로 AWS 쪽에서는 따로 할 일이 없습니다. destroy 전에 키만 먼저 없애고 싶다면:

```bash
aws iam list-access-keys --user-name "$USER_NAME"
aws iam delete-access-key --user-name "$USER_NAME" --access-key-id <AccessKeyId>
```

## 7. 문제 해결

| 증상 | 원인과 해결 |
|---|---|
| `lab.sh deploy` 가 `TargetNotConnected` / `InvalidInstanceId` | 인스턴스가 막 생성돼 SSM 에이전트 등록 전입니다. 2~3분 뒤 다시 시도하세요. |
| deploy 출력에 `exec format error` | 이미지가 amd64 입니다. `--platform linux/arm64` 로 다시 빌드하세요. |
| push 가 `tag invalid ... already exists` | IMMUTABLE 저장소에 같은 태그를 다시 올렸습니다. 태그를 바꾸세요. |
| `DiskUsageHigh` 가 계속 `INSUFFICIENT_DATA` | CloudWatch Agent 가 안 떴습니다. SSM 세션에서 `sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status` 와 `/var/log/cloud-init-output.log` 를 확인하세요. |
| `ErrorLogs` 가 계속 `OK` | 정상입니다. ERROR 로그가 없으면 데이터가 없고, 경보는 이를 정상(`notBreaching`)으로 봅니다. ERROR 를 냈는데도 그대로면 로그 그룹에 `shopapi` 스트림이 생겼는지 보세요. |
| SQS 에 메시지가 안 쌓임 | EventBridge 규칙은 이 환경이 만든 경보 2개의 ARN 만 받습니다. 콘솔에서 만든 다른 경보는 오지 않습니다. |
