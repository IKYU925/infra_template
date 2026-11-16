#!/usr/bin/env bash
# aiops-eks 운영 도우미. 사용법은 docs/aiops-eks.md
# 수동 실행(make eks-*)과 GitHub Actions 스케줄(.github/workflows/eks.yml)이 같은 함수를 부른다.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER="$DIR/cluster"
NAME=ai-incident
REGION="${AWS_REGION:-ap-northeast-2}"

# 코어타임(KST). UP_AT 은 eks.yml 의 올리기 cron 과 같은 시각이어야 한다
UP_AT="${UP_AT:-09:30}"
CORE_END="${CORE_END:-12:00}"
HOLD_MAX="${HOLD_MAX:-13:00}"

usage() {
  cat >&2 <<'EOF'
usage:
  eks.sh up                 cluster 층 apply, 노드 Ready 까지 기다린다
  eks.sh down               루트 앱 삭제 -> PVC, PV 정리 대기 -> cluster 층 destroy -> leftovers
  eks.sh drain              KUBECONFIG 클러스터에서 down 의 클러스터 안 정리만 한다 (루트 앱, LoadBalancer, PVC)
  eks.sh leftovers          cluster 층 리소스가 남았는지 확인한다 (남으면 exit 1)
  eks.sh secrets <.env>     AI_auto_pipeline .env 의 값을 Secrets Manager ai-incident/aiops 에 넣는다
  eks.sh sweep              코어타임 밖이고 cluster 층이 남아 있으면 down (몇 번 돌아도 같은 상태로 수렴)
  eks.sh keep-up <요일1-7> <HH:MM> <YYYY-MM-DD> [hold]   지금 클러스터를 유지할 시간인지 (0 = 유지)
EOF
  exit 2
}

log() { echo "eks.sh: $*" >&2; }
die() { log "$*"; exit 1; }

tf() { terraform -chdir="$CLUSTER" "$@"; }
tf_init() { tf init -input=false -reconfigure -backend-config=backend.hcl >/dev/null; }
caller_cidr() { echo "$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')/32"; }

cluster_status() {
  aws eks describe-cluster --region "$REGION" --name "$NAME" --query cluster.status --output text 2>/dev/null || echo NONE
}

# 실행하는 곳(맥, GitHub Actions 러너)의 IP 가 공개 엔드포인트 허용 목록에 없으면 더하고 반영될 때까지 기다린다
ensure_endpoint_access() {
  local me cidrs id status
  me="$(caller_cidr)"
  cidrs="$(aws eks describe-cluster --region "$REGION" --name "$NAME" \
    --query 'cluster.resourcesVpcConfig.publicAccessCidrs' --output text | tr '\t' ',')"
  [[ ",$cidrs," == *",$me,"* ]] && return
  log "adding $me to endpoint allow list ($cidrs)"
  id="$(aws eks update-cluster-config --region "$REGION" --name "$NAME" \
    --resources-vpc-config "publicAccessCidrs=$cidrs,$me" --query update.id --output text)"
  while status="$(aws eks describe-update --region "$REGION" --name "$NAME" --update-id "$id" --query update.status --output text)"; [[ "$status" == InProgress ]]; do
    sleep 15
  done
  [[ "$status" == Successful ]] || die "endpoint update $id: $status"
}

kubeconfig() {
  # 운영자의 ~/.kube/config 를 건드리지 않는다
  KUBECONFIG="$(mktemp)"
  export KUBECONFIG
  aws eks update-kubeconfig --region "$REGION" --name "$NAME" --kubeconfig "$KUBECONFIG" >/dev/null
}

up() {
  local start=$SECONDS
  tf_init
  tf apply -input=false -auto-approve -lock-timeout=5m -var "caller_cidr=$(caller_cidr)"
  kubeconfig
  kubectl wait --for=condition=Ready nodes --all --timeout=10m
  kubectl get nodes -L workload
  log "up took $((SECONDS - start))s"
  tf output
}

# KUBECONFIG 의 클러스터에서 Terraform 밖 리소스(ELB, EBS)를 남기지 않게 지운다
drain() {
  # 루트 앱의 finalizer 가 하위 앱과 그 리소스를 지운다. up 이 ArgoCD 전에 실패했으면 CRD 가 없다
  if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
    kubectl delete application aiops-root -n argocd --ignore-not-found --wait=false
    local deadline=$((SECONDS + 900))
    while kubectl get application aiops-root -n argocd >/dev/null 2>&1; do
      ((SECONDS < deadline)) || die "aiops-root still exists after 15m"
      # ArgoCD 는 동기화 중인 앱을 지우지 않는다. 끝나지 않는 동기화(Pending Pod, 잘못된 이미지 태그)가 삭제를 막지 않게 끝낸다
      kubectl get applications -n argocd -o json |
        jq -r '.items[] | select(.status.operationState.phase == "Running") | .metadata.name' |
        while read -r app; do
          kubectl patch application "$app" -n argocd --type merge -p '{"status":{"operationState":{"phase":"Terminating"}}}' >/dev/null
        done
      sleep 10
    done
  fi
  # LoadBalancer 는 만들지 않지만 생겼다면 ELB 가 남지 않게 지운다
  kubectl get svc -A -o json |
    jq -r '.items[] | select(.spec.type == "LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' |
    while read -r ns svc; do kubectl delete svc -n "$ns" "$svc" --timeout=5m; done
  # StatefulSet 의 PVC 는 ArgoCD 가 관리하지 않아 따로 지운다. EBS CSI 가 볼륨을 지울 때까지 PV 를 기다린다
  kubectl delete pvc --all -A --timeout=10m
  [[ -z "$(kubectl get pv -o name)" ]] || kubectl wait --for=delete pv --all --timeout=10m
}

down() {
  local start=$SECONDS status
  status="$(cluster_status)"
  if [[ "$status" == ACTIVE ]]; then
    ensure_endpoint_access
    kubeconfig
    drain
  else
    log "cluster status $status: skipping in-cluster cleanup"
  fi
  tf_init
  tf destroy -input=false -auto-approve -lock-timeout=5m -var "caller_cidr=$(caller_cidr)"
  log "down took $((SECONDS - start))s"
  leftovers
}

# 태그 API 는 지운 리소스를 한동안 계속 돌려준다. 종류별 API 로 실제로 남았는지 확인한다
gone() {
  local arn="$1" id="${1##*/}" out
  case "$arn" in
    *:instance/*) out="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$id" --query 'Reservations[].Instances[].State.Name' --output text 2>&1)" ;;
    *:natgateway/*) out="$(aws ec2 describe-nat-gateways --region "$REGION" --nat-gateway-ids "$id" --query 'NatGateways[].State' --output text 2>&1)" ;;
    *:volume/*) out="$(aws ec2 describe-volumes --region "$REGION" --volume-ids "$id" --query 'Volumes[].State' --output text 2>&1)" ;;
    *:security-group/*) out="$(aws ec2 describe-security-groups --region "$REGION" --group-ids "$id" --query 'SecurityGroups[].GroupId' --output text 2>&1)" ;;
    *:subnet/*) out="$(aws ec2 describe-subnets --region "$REGION" --subnet-ids "$id" --query 'Subnets[].SubnetId' --output text 2>&1)" ;;
    *:vpc/*) out="$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$id" --query 'Vpcs[].VpcId' --output text 2>&1)" ;;
    *:route-table/*) out="$(aws ec2 describe-route-tables --region "$REGION" --route-table-ids "$id" --query 'RouteTables[].RouteTableId' --output text 2>&1)" ;;
    *:internet-gateway/*) out="$(aws ec2 describe-internet-gateways --region "$REGION" --internet-gateway-ids "$id" --query 'InternetGateways[].InternetGatewayId' --output text 2>&1)" ;;
    *:elastic-ip/*) out="$(aws ec2 describe-addresses --region "$REGION" --allocation-ids "$id" --query 'Addresses[].AllocationId' --output text 2>&1)" ;;
    *:launch-template/*) out="$(aws ec2 describe-launch-templates --region "$REGION" --launch-template-ids "$id" --query 'LaunchTemplates[].LaunchTemplateId' --output text 2>&1)" ;;
    *:podidentityassociation/*) out="$(aws eks describe-pod-identity-association --region "$REGION" --cluster-name "$NAME" --association-id "$id" --query association.associationId --output text 2>&1)" ;;
    *) return 1 ;;
  esac
  [[ -z "$out" || "$out" == terminated || "$out" == deleted || "$out" == *NotFound* ]]
}

leftovers() {
  local found=() arns arn state
  # 조회가 실패하면 "0개"로 읽지 않고 멈춘다. && 와 pipefail 이 실패를 넘긴다
  arns="$(
    {
      aws resourcegroupstaggingapi get-resources --region "$REGION" --tag-filters Key=Project,Values=ai-incident \
        --query "ResourceTagMappingList[?length(Tags[?Key=='Layer' && Value=='base']) == \`0\`].ResourceARN" --output text &&
        aws resourcegroupstaggingapi get-resources --region "$REGION" --tag-filters "Key=kubernetes.io/cluster/$NAME" \
          --query 'ResourceTagMappingList[].ResourceARN' --output text &&
        # VPC CNI 가 만든 ENI 는 Project 태그가 없다
        aws ec2 describe-network-interfaces --region "$REGION" --filters "Name=tag:cluster.k8s.amazonaws.com/name,Values=$NAME" \
          --query 'NetworkInterfaces[].NetworkInterfaceId' --output text
    } | tr '\t' '\n' | sort -u
  )" || die "listing resources failed"
  while read -r arn; do
    [[ -n "$arn" ]] || continue
    gone "$arn" || found+=("$arn")
  done <<<"$arns"
  log "leftovers: ${#found[@]}"
  [[ ${#found[@]} -eq 0 ]] || { printf '%s\n' "${found[@]}"; return 1; }
}

secrets() {
  local env_file="$1" secret_id current
  [[ -f "$env_file" ]] || die "no such file: $env_file"
  secret_id="$(terraform -chdir="$DIR/base" output -raw aiops_secret_name)"
  current="$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$secret_id" \
    --query SecretString --output text 2>/dev/null || echo '{}')"
  # 값은 argv 가 아니라 stdin 으로 넘긴다 (ps 에 보이지 않게)
  CURRENT="$current" python3 - "$env_file" <<'EOF' | aws secretsmanager put-secret-value --region "$REGION" --secret-id "$secret_id" --secret-string file:///dev/stdin --query VersionId --output text
import json, os, secrets, sys
env = {}
for line in open(sys.argv[1]):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip("'\"")
value = json.loads(os.environ["CURRENT"])
for k in ("ANTHROPIC_API_KEY", "SLACK_BOT_TOKEN", "SLACK_APP_TOKEN", "AUTOMATION_TOKEN", "POSTGRES_PASSWORD"):
    if env.get(k):
        value[k] = env[k]
for k in ("AUTOMATION_TOKEN", "POSTGRES_PASSWORD"):
    value.setdefault(k, secrets.token_urlsafe(32))
missing = [k for k in ("ANTHROPIC_API_KEY", "SLACK_BOT_TOKEN", "SLACK_APP_TOKEN") if not value.get(k)]
if missing:
    sys.exit(f"missing in {sys.argv[1]}: {', '.join(missing)}")
print(json.dumps(value))
EOF
}

# 0 = 유지할 시간. 평일 UP_AT 부터 CORE_END 까지. hold 는 오늘 날짜의 "YYYY-MM-DDTHH:MM" 일 때만 HOLD_MAX 까지 연장한다
keep_up() {
  local dow="$1" now="$2" today="$3" hold="${4:-}" end="$CORE_END"
  if [[ "$hold" =~ ^${today}T([0-2][0-9]:[0-5][0-9])$ ]]; then
    local h="${BASH_REMATCH[1]}"
    [[ "$h" > "$HOLD_MAX" ]] && h="$HOLD_MAX"
    [[ "$h" > "$end" ]] && end="$h"
  fi
  ((dow <= 5)) && [[ ! "$now" < "$UP_AT" && "$now" < "$end" ]]
}

sweep() {
  if keep_up "$(TZ=Asia/Seoul date +%u)" "$(TZ=Asia/Seoul date +%H:%M)" "$(TZ=Asia/Seoul date +%F)" "${EKS_HOLD_UNTIL:-}"; then
    log "inside core time (hold: ${EKS_HOLD_UNTIL:-none}), keeping cluster"
  elif leftovers >/dev/null && [[ "$(cluster_status)" == NONE ]]; then
    log "outside core time, nothing left"
  else
    down
  fi
}

case "${1:-}" in
  up) [[ $# -eq 1 ]] || usage; up ;;
  down) [[ $# -eq 1 ]] || usage; down ;;
  drain) [[ $# -eq 1 ]] || usage; drain ;;
  leftovers) [[ $# -eq 1 ]] || usage; leftovers ;;
  secrets) [[ $# -eq 2 ]] || usage; secrets "$2" ;;
  sweep) [[ $# -eq 1 ]] || usage; sweep ;;
  keep-up) [[ $# -ge 4 ]] || usage; keep_up "$2" "$3" "$4" "${5:-}" ;;
  *) usage ;;
esac
