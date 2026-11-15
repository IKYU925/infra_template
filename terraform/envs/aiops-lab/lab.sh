#!/usr/bin/env bash
# aiops-lab 운영 도우미. 사용법은 docs/aiops-lab.md
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'EOF'
usage:
  lab.sh deploy <image-uri>   ECR 이미지로 EC2 의 앱 컨테이너를 (다시) 띄운다
  lab.sh leftovers            destroy 후 Project=ai-incident 리소스가 남았는지 확인한다 (남으면 exit 1)
EOF
  exit 2
}

die() { echo "lab.sh: $*" >&2; exit 1; }

out() { terraform -chdir="$DIR" output -raw "$1"; }

# destroy 뒤에는 output 이 비므로 설정(tfvars)에서 직접 읽는다
tfvar() { echo "var.$1" | terraform -chdir="$DIR" console | tr -d '"'; }

deploy() {
  local image="$1" repo region instance group service
  repo="$(out ecr_repository_url)"
  # 태그/다이제스트 문자만 허용해서 아래 JSON 과 셸 명령에 그대로 넣어도 안전하게 한다
  [[ "$image" =~ ^${repo//./\\.}(:[A-Za-z0-9_.-]+|@sha256:[0-9a-f]{64})$ ]] ||
    die "image must be $repo:<tag> or $repo@sha256:<digest>, got: $image"

  region="$(out region)"
  instance="$(out instance_id)"
  group="$(out log_group_name)"
  service="$(out service)"

  local commands=(
    "set -eu"
    "aws ecr get-login-password --region $region | docker login --username AWS --password-stdin ${image%%/*}"
    "docker rm -f $service || true"
    "docker run -d --name $service --restart unless-stopped -p 8100:8100 -w /repo -e PG_API_KEY=dev-key --log-driver awslogs --log-opt awslogs-region=$region --log-opt awslogs-group=$group --log-opt awslogs-stream=$service $image uvicorn shopapi.main:create_app --factory --host 0.0.0.0 --port 8100"
    "docker ps --filter name=$service"
  )
  local json c
  json="$(printf '"%s",' "${commands[@]}")"
  json="{\"commands\":[${json%,}]}"

  local id
  id="$(aws ssm send-command --region "$region" --instance-ids "$instance" \
    --document-name AWS-RunShellScript --comment "aiops-lab deploy" \
    --parameters "$json" --query Command.CommandId --output text)"
  echo "command $id on $instance" >&2

  # 웨이터는 100초에서 끝나므로 이미지 pull 이 길면 다시 기다린다
  local status
  until aws ssm wait command-executed --region "$region" --command-id "$id" --instance-id "$instance" 2>/dev/null; do
    status="$(aws ssm get-command-invocation --region "$region" --command-id "$id" --instance-id "$instance" --query Status --output text)"
    [[ "$status" =~ ^(Pending|InProgress|Delayed)$ ]] || break
  done

  for c in StandardOutputContent StandardErrorContent; do
    echo "--- $c" >&2
    aws ssm get-command-invocation --region "$region" --command-id "$id" --instance-id "$instance" --query "$c" --output text
  done
  status="$(aws ssm get-command-invocation --region "$region" --command-id "$id" --instance-id "$instance" --query Status --output text)"
  echo "status: $status" >&2
  [[ "$status" == Success ]]
}

# 0 = 있음, 1 = 없음. 권한·네트워크 오류를 "없음"으로 읽지 않도록 그 밖의 오류는 멈춘다
exists() {
  local err
  if err="$("$@" 2>&1 >/dev/null)"; then return 0; fi
  [[ "$err" =~ NoSuchEntity|NotFoundException ]] && return 1
  die "$* failed: $err"
}

leftovers() {
  local region name account
  region="$(tfvar region)"
  name="$(tfvar name)"
  account="$(aws sts get-caller-identity --query Account --output text)"

  local found=() arn
  while read -r arn; do
    [[ -n "$arn" ]] || continue
    # 종료된 인스턴스는 destroy 후에도 한동안 태그 API 에 남는다
    if [[ "$arn" == *":instance/i-"* ]]; then
      local state
      state="$(aws ec2 describe-instances --region "$region" --instance-ids "${arn##*/}" \
        --query 'Reservations[].Instances[].State.Name' --output text 2>&1)" ||
        [[ "$state" == *InvalidInstanceID.NotFound* ]] || die "describe-instances ${arn##*/} failed: $state"
      [[ "$state" == terminated || "$state" == *InvalidInstanceID.NotFound* ]] && continue
    fi
    found+=("$arn")
  done < <(aws resourcegroupstaggingapi get-resources --region "$region" \
    --tag-filters Key=Project,Values=ai-incident \
    --query 'ResourceTagMappingList[].ResourceARN' --output text | tr '\t' '\n')

  # IAM 과 Budgets 는 태그 API 로 늘 잡히지 않아 이름으로 따로 확인한다
  exists aws iam get-user --user-name "$name-automation" && found+=("iam user $name-automation")
  exists aws iam get-role --role-name "$name-instance" && found+=("iam role $name-instance")
  exists aws budgets describe-budget --account-id "$account" --budget-name "$name-monthly" && found+=("budget $name-monthly")

  echo "leftovers: ${#found[@]}" >&2
  [[ ${#found[@]} -eq 0 ]] || { printf '%s\n' "${found[@]}"; return 1; }
}

case "${1:-}" in
  deploy) [[ $# -eq 2 ]] || usage; deploy "$2" ;;
  leftovers) [[ $# -eq 1 ]] || usage; leftovers ;;
  *) usage ;;
esac
