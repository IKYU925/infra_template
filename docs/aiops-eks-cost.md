# aiops-eks 비용

AI_auto_pipeline 4단계 EKS 환경의 비용 근거다. 총예산 100~120달러 중 하한 100달러를 기준으로 계산하고, 목표선은 90달러(10%는 비상용)다. 숫자마다 출처를 적는다. **추정**은 공시 단가와 가정으로 계산한 값이고, **실측**은 Cost Explorer, Billing, 워크플로 로그에서 읽은 값이다.

## 공시 단가 (서울, ap-northeast-2)

출처는 AWS Price List 공개 파일(`https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<서비스>/current/ap-northeast-2/index.json`)이다. 요금 계산기와 같은 데이터다. 2026-11-16에 받았다(파일 publicationDate 2026-11-05 ~ 2026-11-14).

| 항목 | 단가 | usagetype |
| --- | --- | --- |
| EKS 컨트롤 플레인 (표준 지원) | 0.10 USD/시간 | `APN2-AmazonEKS-Hours:perCluster` |
| EKS 컨트롤 플레인 (연장 지원) | 0.50 USD/시간 | `APN2-AmazonEKS-Hours:extendedSupport` |
| t4g.large 온디맨드 Linux | 0.0832 USD/시간 | `APN2-BoxUsage:t4g.large` |
| t4g.medium 온디맨드 Linux | 0.0416 USD/시간 | `APN2-BoxUsage:t4g.medium` |
| NAT 게이트웨이 | 0.059 USD/시간 | `APN2-NatGateway-Hours` |
| NAT 데이터 처리 | 0.059 USD/GB | `APN2-NatGateway-Bytes` |
| 공인 IPv4 (NAT 의 EIP) | 0.005 USD/시간 | `APN2-PublicIPv4:InUseAddress` |
| EBS gp3 | 0.0912 USD/GB-월 | `APN2-EBS:VolumeUsage.gp3` |
| Secrets Manager | 0.40 USD/비밀-월 | `APN2-AWSSecretsManager-Secrets` |
| ECR 저장 | 0.10 USD/GB-월 | `APN2-TimedStorage-ByteHrs` |
| S3 Standard 저장 | 0.025 USD/GB-월 | `APN2-TimedStorage-ByteHrs` |

VPC 엔드포인트는 쓰지 않으므로(설계 3.1) 과금 항목에 없다. 연장 지원 단가는 표준의 5배다. `upgrade_policy = STANDARD` 로 연장 지원에 들어가지 않게 했다.

## cluster 층 시간당 비용 (추정)

EBS 는 노드 루트 볼륨 2 × 20GB 와 PVC 40GB(가정)를 더한 80GB 로 잡았다. 80 × 0.0912 / 730 = 0.010 USD/시간이다.

| 항목 | t4g.large | t4g.medium |
| --- | --- | --- |
| EKS 컨트롤 플레인 | 0.100 | 0.100 |
| 노드 2대 | 0.166 | 0.083 |
| NAT 게이트웨이 | 0.059 | 0.059 |
| 공인 IPv4 1개 | 0.005 | 0.005 |
| EBS 80GB | 0.010 | 0.010 |
| **합계 (USD/시간)** | **0.340** | **0.257** |

NAT 데이터 처리는 시간이 아니라 GB 로 붙는다. 노드가 ECR, Helm 차트 저장소, GitHub 에서 받는 양을 하루 3GB 로 가정해 하루 0.18달러를 더한다. 매일 클러스터를 새로 만들어 이미지 캐시가 없으므로 첫 실측에서 반드시 고친다.

## 하루 비용과 운영 가능 일수 (추정)

base 층은 비밀 1개(0.40), ECR 이미지 2GB(0.20), Loki 로그 1GB(0.03)로 월 약 0.63달러, 2달 1.3달러다. 예산 알림은 계정당 2개까지 무료다. 목표선 90달러에서 base 2달치를 뺀 88.7달러로 일수를 계산한다.

| 운영 방식 | 켜진 시간 | 하루 비용 (large) | 90달러로 가능한 일수 | 하루 비용 (medium) | 가능한 일수 |
| --- | --- | --- | --- | --- | --- |
| 24시간 상시 | 24시간 | 8.35 | 10.6일 | 6.35 | 14.0일 |
| 코어타임, 연장한 날 (09:30~13:00 + 내리기) | 3.5시간 | 1.37 | 64.7일 | 1.08 | 82.1일 |
| 코어타임, 보통 날 (09:30~12:00 + 내리기) | 2.75시간 | 1.12 | 79.2일 | 0.89 | 99.7일 |

사용 기간 1~2달(평일 22~44일)을 모두 연장한 날로 계산하면 t4g.large 로 30~60달러에 base 1.3달러를 더해 **31~62달러**다. 목표선 90달러의 35~68%다. 상시 운영과 비교하면 하루 비용이 8.35달러에서 1.37달러로 84% 줄고, 같은 예산으로 쓸 수 있는 날이 10.6일에서 64.7일로 6.1배가 된다.

노드 타입 결정: 추정상 t4g.large 로도 2달을 목표선 안에서 쓴다. t4g.medium 은 하루 0.29달러를 아끼지만 prefix delegation 설정과 메모리 여유 40%를 감수해야 한다(P0). 기본값은 t4g.large 다.

요금 계산기 공유 링크는 아직 없다. 위 단가가 계산기와 같은 데이터이므로, 운영자가 계산기에서 같은 구성을 넣고 링크를 이 줄에 남긴다.

## 실측 기록

`Project=ai-incident` 비용 할당 태그는 첫 실제 실행 전에 Billing 에서 활성화한다. Cost Explorer 에 나오기까지 최대 24시간이 걸린다. 누적 사용액은 주 1회 갱신하고, 90달러에 닿으면 `EKS_SCHEDULE_ENABLED` 를 끄고 운영자에게 알린다.

| 항목 | 값 | 출처 |
| --- | --- | --- |
| 코어타임 운영 시 하루 비용 (1주 평균) | 미측정 | Cost Explorer `Project=ai-incident` 일별 |
| eks-up 소요 시간 (apply + 노드 Ready) | 미측정 | `eks.sh up` 의 `up took` 로그, 워크플로 실행 시간 |
| eks-up + ArgoCD 전체 Healthy | 미측정 | P2 이후. 올리기 cron 을 이 시간만큼 당긴다 |
| eks-down 소요 시간 | 미측정 | `eks.sh down` 의 `down took` 로그 |
| 비 코어타임 cluster 층 남은 리소스 | 미측정 | 정리 워크플로의 `leftovers: 0` 로그 |
| 계산기 예측과 실제의 차이 (데이터 전송, NAT 처리량, EBS) | 미측정 | 위 두 출처 비교 |
| 누적 사용액 (프로젝트 시작일부터) | 0 | Cost Explorer |
| 프로젝트 종료 시 실제 사용액과 남은 비율 | 미측정 | Billing |
