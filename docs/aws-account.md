# AWS 계정과 CLI 자격 증명

이 저장소의 Terraform(`bootstrap`, `envs/*`)과 `make eks-*` 는 맥의 AWS CLI 자격 증명으로 실제 계정에 접근한다. 이 문서는 그 자격 증명을 처음 만들고, 다른 맥으로 옮기고, 교체하고, 문제가 생겼을 때 할 일을 적는다.

## 원칙

- 루트 계정은 MFA 를 걸어 두고 쓰지 않는다. 루트 액세스 키는 만들지 않는다.
- 작업은 IAM 사용자로 한다. 콘솔도 CLI 도 같은 사용자다.
- 이 사용자에게는 `AdministratorAccess` 를 준다. Terraform 이 IAM 역할, OIDC 공급자, VPC, EKS, KMS 를 만든다. `iam:CreateRole` 이 있으면 관리자 권한을 스스로 만들 수 있으므로, 권한을 잘게 나눠도 실제로 막는 것은 없고 apply 만 중간에 실패한다.
- 액세스 키는 `~/.aws/credentials` 에만 둔다. 저장소, `.env`, 채팅, 스크린샷에 남기지 않는다. 이 저장소는 공개 저장소다.

## 처음 한 번 만든다

루트로 콘솔에 로그인해 다음을 한다. 1~3 은 루트만 할 수 있다.

1. 루트에 MFA 를 등록한다. 오른쪽 위 계정 이름 → Security credentials → Assign MFA device.
2. 같은 화면의 Access keys 에 키가 있으면 삭제한다.
3. 계정 이름 → Account → IAM user and role access to Billing information → Edit → Activate IAM Access. 꺼져 있으면 관리자 권한이 있는 IAM 사용자도 비용, 예산, 비용 할당 태그 화면에 들어가지 못한다.
4. IAM → Users → Create user. 콘솔 접근을 켜고, Attach policies directly 로 `AdministratorAccess` 를 붙인다. 콘솔 로그인 URL `https://<계정ID>.signin.aws.amazon.com/console` 을 적어 둔다.
5. 그 사용자의 Security credentials 탭에서 MFA 를 등록한다.
6. 같은 탭에서 Create access key → Command Line Interface (CLI) 로 키를 만든다. Secret access key 는 이 화면에서만 보인다.
7. 루트에서 로그아웃하고, 이후 콘솔은 4 의 URL 로 IAM 사용자로 들어간다.

맥에서 키를 넣는다.

```bash
aws configure
# AWS Access Key ID / Secret Access Key: 6 에서 받은 값
# Default region name: ap-northeast-2
# Default output format: json
```

## 제대로 됐는지 확인한다

```bash
aws sts get-caller-identity --query Arn --output text
# arn:aws:iam::<계정ID>:user/<이름> 이어야 한다. :root 면 루트 키가 들어간 것이다.
aws iam get-account-summary --query 'SummaryMap.[AccountMFAEnabled,AccountAccessKeysPresent]' --output text
# 1 0 이어야 한다. 루트 MFA 켜짐, 루트 액세스 키 없음.
aws iam list-mfa-devices --query 'length(MFADevices)'
# 1 이상이어야 한다. IAM 사용자 MFA.
aws configure list
# 지금 쓰는 키가 어디서 왔는지(환경 변수, 설정 파일) 보여 준다.
```

## 다른 맥에서 쓴다

Secret access key 는 다시 볼 수 없다. 키 파일을 옮기는 대신 새 키를 만든다.

1. IAM 사용자로 콘솔에 들어가 Security credentials → Create access key 로 새 키를 만든다. 사용자당 키는 2 개까지라, 이미 2 개면 안 쓰는 키부터 지운다.
2. 새 맥에서 `aws configure` 로 넣고 위 확인 명령을 돌린다.
3. 예전 맥을 더 쓰지 않으면 그 키를 Deactivate 했다가 문제가 없으면 Delete 한다.

## 키를 교체한다

90 일 정도마다, 또는 키를 어디에 붙여 넣었는지 확실하지 않을 때 교체한다.

1. 새 키를 만든다.
2. `aws configure` 로 바꿔 넣고 `aws sts get-caller-identity` 로 확인한다.
3. 예전 키를 Deactivate 한다. 콘솔의 Last used 가 더 늘지 않는지 며칠 본 뒤 Delete 한다.

## 키가 새어 나갔다

1. 바로 콘솔에서 그 키를 Deactivate 한다. 확인은 그다음이다.
2. 새 키를 만들어 맥에 넣는다.
3. CloudTrail → Event history 에서 그 키 ID(`AccessKeyId`)로 거른다. 모르는 리전의 EC2, 새 IAM 사용자나 키 같은 흔적을 찾는다.
4. Billing 에서 예상치 못한 비용이 있는지 본다. AWS 가 유출을 감지하면 메일을 보내고 사용자에 격리 정책을 붙이기도 한다. 그 정책은 정리가 끝난 뒤 뗀다.
5. 예전 키를 Delete 한다.

## 오류가 날 때

| 메시지 | 뜻 | 할 일 |
| --- | --- | --- |
| `NoCredentials`, `Unable to locate credentials` | 이 맥에 키가 없다 | `aws configure` |
| `InvalidClientTokenId` | 키가 지워졌거나 비활성이다 | 콘솔에서 키 상태를 보고 새 키를 넣는다 |
| `SignatureDoesNotMatch` | Secret 을 잘못 넣었다 | `aws configure` 로 다시 넣는다 |
| `ExpiredToken` | 환경 변수의 임시 자격 증명이 만료됐다 | `env \| grep AWS_` 로 남은 변수를 찾아 `unset` 한다 |
| `AccessDenied` 가 Billing, 예산에서만 난다 | 위 3 번(IAM Billing 접근)이 꺼져 있다 | 루트로 켠다 |
| ARN 이 `:root` 로 나온다 | 루트 키가 들어가 있다 | 루트 키를 지우고 IAM 사용자 키를 넣는다 |
| Terraform 이 `allowed_account_ids` 오류를 낸다 | 다른 계정 키를 쓰고 있다 | `aws sts get-caller-identity` 로 계정을 확인한다 |

## 계정이나 키가 여러 개일 때

프로필로 나눈다.

```bash
aws configure --profile lab
export AWS_PROFILE=lab   # 이 셸의 aws, terraform, make 가 이 프로필을 쓴다
```

## 프로젝트를 끝낼 때

Terraform 리소스를 모두 지운 뒤 IAM 사용자의 액세스 키를 Delete 한다. 콘솔 사용자와 루트 MFA 는 남겨 둔다.
