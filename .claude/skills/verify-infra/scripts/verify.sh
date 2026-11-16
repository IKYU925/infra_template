#!/usr/bin/env bash
# verify-infra helper. Drives the LOCAL stand-in of this infra template (docker compose + floci + ansible-lab).
# It never touches real AWS (dev/prod). See ../SKILL.md.
#
#   verify.sh launch                 # start isolated stack (compose project "verify-infra")
#   verify.sh doctor                 # read-only: is the running instance ours and usable?
#   verify.sh drive <feature>        # local-app | local-aws | tf-static | ansible-lab | aiops-eks
#   verify.sh tf <dir> <args...>     # terraform (docker) in the run's copy of terraform/<dir>
#   verify.sh aws <args...>          # aws cli (docker) against floci
#   verify.sh cleanup                # tear down what launch started; evidence is kept
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PROJECT=verify-infra
NET="${PROJECT}_default"
RUNS="$REPO/.verify-runs"
CUR="$RUNS/current"
COMPOSE_FILE="$REPO/local/docker-compose.yml"
TF_IMAGE=hashicorp/terraform:1.17.1
AWS_IMAGE=amazon/aws-cli:latest
LAB_CONTAINER=infra-local-ansible-target   # fixed container_name in compose -> single instance only
PG_PORT=15432
APP_PORT=18080
AWS_PORT=4566                              # fixed in compose -> single instance only

log() { printf '[verify-infra] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

run_dir() { [[ -L "$CUR" || -d "$CUR" ]] || die "no current run; run 'verify.sh launch' first"; cd "$CUR" && pwd -P; }
# floci gets the docker socket so EKS clusters run a real k3s API server (drive aiops-eks installs ArgoCD into it).
# The extra alias is for S3 Control, which the AWS provider calls at <account-id>.<endpoint host>.
FLOCI_DOCKER='services: {floci: {volumes: ["/var/run/docker.sock:/var/run/docker.sock"], networks: {default: {aliases: [aws, 000000000000.aws]}}}}'
compose() { local r; r="$(run_dir)"; docker compose -p "$PROJECT" -f "$COMPOSE_FILE" -f "$r/work/compose.floci-docker.yml" --env-file "$r/work/.env" "$@"; }
port_owner() { docker ps --filter "publish=$1" --format '{{.Names}}' | head -1; }
port_listen() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

tf() {
  local dir="$1"; shift
  local r; r="$(run_dir)"
  docker run --rm --network "$NET" -v "$r/work/terraform:/w" -w "/w/$dir" \
    -e TF_IN_AUTOMATION=1 -e TF_PLUGIN_CACHE_DIR=/w/.plugin-cache "$TF_IMAGE" "$@"
}
awscli() {
  docker run --rm --network "$NET" -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test \
    -e AWS_DEFAULT_REGION=ap-northeast-2 "$AWS_IMAGE" --endpoint-url http://aws:4566 "$@"
}

cmd_launch() {
  docker info >/dev/null 2>&1 || die "docker daemon not running"
  if docker compose -p "$PROJECT" ls -q 2>/dev/null | grep -qx "$PROJECT" || docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" | grep -q .; then
    die "compose project '$PROJECT' already exists (another verify run?). Run doctor or cleanup first; do not double-drive."
  fi
  for p in $PG_PORT $APP_PORT $AWS_PORT; do
    port_listen "$p" && die "port $p already in use by '$(port_owner "$p")' - refusing to share it"
  done
  docker ps -aq --filter "name=^${LAB_CONTAINER}$" | grep -q . && die "container $LAB_CONTAINER exists (someone's ansible-lab) - refusing"

  local ts r; ts="$(date +%Y%m%d-%H%M%S)"; r="$RUNS/$ts"
  mkdir -p "$r/work" "$r/evidence"
  ln -sfn "$ts" "$CUR"
  sed -e "s/^POSTGRES_PORT=.*/POSTGRES_PORT=$PG_PORT/" -e "s/^APP_PORT=.*/APP_PORT=$APP_PORT/" \
      -e 's/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=verify-only-local/' "$REPO/local/.env.example" > "$r/work/.env"
  # terraform copy: keeps the user's own terraform/envs/local/terraform.tfstate untouched
  rsync -a --exclude '.terraform/' --exclude '*.tfstate*' --exclude 'tfplan' "$REPO/terraform/" "$r/work/terraform/"
  mkdir -p "$r/work/terraform/.plugin-cache"
  echo "$FLOCI_DOCKER" > "$r/work/compose.floci-docker.yml"

  log "run dir: $r"
  compose --profile aws up -d --quiet-pull --wait --wait-timeout 180 >/dev/null 2>&1 || die "compose up failed - run: docker compose -p verify-infra logs"
  cmd_doctor
  log "READY: app http://127.0.0.1:$APP_PORT  postgres 127.0.0.1:$PG_PORT  floci http://127.0.0.1:$AWS_PORT"
}

cmd_doctor() {
  local r ok=0; r="$(run_dir)"
  check() { if eval "$2" >/dev/null 2>&1; then log "ok   $1"; else log "FAIL $1"; ok=1; fi; }
  log "run dir: $r"
  check "postgres ours on :$PG_PORT"   "[[ \$(port_owner $PG_PORT) == ${PROJECT}-postgres-1 ]]"
  check "app ours on :$APP_PORT"       "[[ \$(port_owner $APP_PORT) == ${PROJECT}-app-1 ]]"
  check "floci ours on :$AWS_PORT"     "[[ \$(port_owner $AWS_PORT) == ${PROJECT}-floci-1 ]]"
  check "postgres accepts queries"     "docker exec ${PROJECT}-postgres-1 psql -U app -d app -tAc 'select 1' | grep -qx 1"
  check "app HTTP 200"                 "[[ \$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$APP_PORT/) == 200 ]]"
  check "floci s3+secretsmanager up"   "curl -s http://127.0.0.1:$AWS_PORT/_floci/health | grep -q '\"secretsmanager\":\"running\"'"
  return $ok
}

ev() { local r; r="$(run_dir)"; echo "$r/evidence/$1"; }

drive_local_app() {
  local e; e="$(ev local-app)"; mkdir -p "$e"
  curl -si "http://127.0.0.1:$APP_PORT/" > "$e/app-response.txt"
  head -1 "$e/app-response.txt" | grep -q ' 200' || die "app did not return 200 (see $e/app-response.txt)"
  docker exec ${PROJECT}-app-1 env | grep -E '^(DATABASE_URL|AWS_ENDPOINT_URL|AWS_REGION)=' | sed 's#://\([^:]*\):[^@]*@#://\1:***@#' | sort > "$e/app-env.txt"
  [[ "$(cat "$e/app-env.txt")" == "$(printf '%s\n' 'AWS_ENDPOINT_URL=http://aws:4566' 'AWS_REGION=ap-northeast-2' 'DATABASE_URL=postgresql://app:***@postgres:5432/app')" ]] \
    || die "app env wiring unexpected (see $e/app-env.txt)"
  docker inspect ${PROJECT}-app-1 --format '{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.SecurityOpt}} {{.HostConfig.Tmpfs}}' > "$e/app-hardening.txt"
  grep -qx 'true \[no-new-privileges:true\] map\[/tmp:\]' "$e/app-hardening.txt" || die "app hardening unexpected (see $e/app-hardening.txt)"
  # psql runs inside the postgres container; the placeholder app has no DB client
  docker exec ${PROJECT}-postgres-1 psql -U app -d app -c "create table if not exists verify_probe(id int); insert into verify_probe values (1);" > "$e/db-write.txt"
  docker exec ${PROJECT}-postgres-1 psql -U app -d app -tAc "select current_setting('server_version_num'), (select count(*) from verify_probe)" > "$e/db-read.txt"
  grep -qE '^17[0-9]{4}\|[1-9][0-9]*$' "$e/db-read.txt" || die "postgres 17 read-back failed (see $e/db-read.txt)"
  docker compose -p "$PROJECT" ps --format '{{.Service}} {{.Image}} {{.Status}}' > "$e/compose-ps.txt"
  log "PASS local-app -> $e"
}

drive_local_aws() {
  local e; e="$(ev local-aws)"; mkdir -p "$e"
  tf envs/local init -input=false -no-color > "$e/tf-init.txt" 2>&1 || die "init failed ($e/tf-init.txt)"
  tf envs/local apply -auto-approve -input=false -no-color -var aws_endpoint=http://aws:4566 > "$e/tf-apply.txt" 2>&1 || die "apply failed ($e/tf-apply.txt)"
  grep -q 'Apply complete!' "$e/tf-apply.txt" || die "no 'Apply complete!' in $e/tf-apply.txt"
  tf envs/local output -json > "$e/tf-output.json"
  local bucket; bucket="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["artifact_bucket_name"]["value"])' "$e/tf-output.json")"
  # side effects observed directly in the emulator, not via terraform state
  awscli s3api list-buckets --query 'Buckets[].Name' > "$e/s3-buckets.json"
  awscli s3api get-bucket-versioning --bucket "$bucket" > "$e/s3-versioning.json"
  awscli s3api get-public-access-block --bucket "$bucket" > "$e/s3-public-access-block.json"
  awscli secretsmanager get-secret-value --secret-id myproject/local/db --query SecretString --output text > "$e/secret.json"
  grep -q '"Enabled"' "$e/s3-versioning.json" || die "versioning not Enabled"
  [[ "$(cat "$e/secret.json")" == '{"dbname":"app","host":"postgres","port":5432,"username":"app"}' ]] || die "secret content unexpected (see $e/secret.json)"
  [[ "$(grep -c '": true' "$e/s3-public-access-block.json")" == 4 ]] || die "public access block not all true (see $e/s3-public-access-block.json)"
  # idempotency: second plan must be empty
  tf envs/local plan -detailed-exitcode -input=false -no-color -var aws_endpoint=http://aws:4566 > "$e/tf-replan.txt" 2>&1 \
    || die "re-plan not clean (exit $?) - see $e/tf-replan.txt"
  log "PASS local-aws -> $e"
}

drive_tf_static() {
  local e rc=0; e="$(ev tf-static)"; mkdir -p "$e"
  tf . fmt -check -recursive -diff -no-color > "$e/fmt.txt" 2>&1 || { log "FAIL fmt (see $e/fmt.txt)"; rc=1; }
  for d in bootstrap envs/local envs/dev envs/prod envs/aiops-eks/base envs/aiops-eks/cluster; do
    local f="$e/validate-${d//\//-}.txt"
    { tf "$d" init -backend=false -input=false -no-color && tf "$d" validate -no-color; } > "$f" 2>&1 \
      && log "ok   validate $d" || { log "FAIL validate $d (see $f)"; rc=1; }
  done
  [[ $rc == 0 ]] && log "PASS tf-static -> $e" || die "tf-static failed -> $e"
}

drive_aiops_eks() {
  local e r d k3s; e="$(ev aiops-eks)"; r="$(run_dir)"; d="$r/work/terraform/envs/aiops-eks"; mkdir -p "$e"
  k3s=floci-aws-eks-ai-incident
  local bvars=(-var 'allowed_account_ids=["000000000000"]' -var budget_email=lab@example.com)
  local cvars=(-var 'allowed_account_ids=["000000000000"]' -var 'admin_principal_arns=[]' -var state_bucket=unused -var caller_cidr=203.0.113.10/32)
  local endpoints="" s
  for s in budgets ec2 ecr eks iam kms logs s3 s3control secretsmanager ssm sts; do endpoints+="    $s = \"http://aws:4566\""$'\n'; done
  for layer in base cluster; do
    cat > "$d/$layer/floci_override.tf" <<EOF
terraform {
  backend "local" {}
}
provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true
  endpoints {
$endpoints  }
}
EOF
  done
  # cluster reads base from the local state above; helm talks to floci's k3s with its admin kubeconfig
  cat >> "$d/cluster/floci_override.tf" <<'EOF'
data "terraform_remote_state" "base" {
  backend = "local"
  config  = { path = "../base/terraform.tfstate" }
}
provider "helm" {
  kubernetes = { config_path = "kubeconfig" }
}
# floci's caller is the account root, which access entries reject (real callers are IAM roles or users).
# floci neither returns the upgrade policy nor implements UpdateClusterConfig, so every plan would try to update it.
module "eks" {
  enable_cluster_creator_admin_permissions = false
  upgrade_policy                           = null
}
EOF
  tf envs/aiops-eks fmt -recursive >/dev/null   # keeps drive tf-static green in the same run
  tf envs/aiops-eks/base init -input=false -no-color > "$e/base-init.txt" 2>&1 || die "base init failed ($e/base-init.txt)"
  tf envs/aiops-eks/base apply -auto-approve -input=false -no-color "${bvars[@]}" > "$e/base-apply.txt" 2>&1 \
    || die "base apply failed ($e/base-apply.txt)"
  tf envs/aiops-eks/cluster init -input=false -no-color > "$e/cluster-init.txt" 2>&1 || die "cluster init failed ($e/cluster-init.txt)"
  # helm needs the kubeconfig of a cluster that only exists after this first apply
  tf envs/aiops-eks/cluster apply -auto-approve -input=false -no-color "${cvars[@]}" -target=module.eks -target=aws_eks_pod_identity_association.workload \
    > "$e/cluster-apply-eks.txt" 2>&1 || die "cluster apply (eks) failed ($e/cluster-apply-eks.txt)"
  local port; port="$(awscli eks describe-cluster --name ai-incident --query cluster.endpoint --output text)"; port="${port##*:}"
  docker exec "$k3s" cat /etc/rancher/k3s/k3s.yaml \
    | sed -e "s#server: https://127.0.0.1:6443#server: https://host.docker.internal:$port#" \
          -e 's#certificate-authority-data: .*#insecure-skip-tls-verify: true#' > "$d/cluster/kubeconfig"
  tf envs/aiops-eks/cluster apply -auto-approve -input=false -no-color "${cvars[@]}" > "$e/cluster-apply.txt" 2>&1 \
    || die "cluster apply failed ($e/cluster-apply.txt)"
  tf envs/aiops-eks/cluster output -json > "$e/cluster-output.json"
  python3 - "$e/cluster-output.json" <<'EOF' || die "cluster outputs wrong ($e/cluster-output.json)"
import json, sys
o = {k: v["value"] for k, v in json.load(open(sys.argv[1])).items()}
assert set(o) == {"cluster_name", "region", "account_id", "ecr_repository_url", "loki_bucket_name", "aiops_secret_name", "kubeconfig_command"}, o
assert o["ecr_repository_url"].endswith("/aiops") and o["loki_bucket_name"] == "ai-incident-loki-000000000000", o
assert o["aiops_secret_name"] == "ai-incident/aiops", o
EOF
  # AWS side, observed in floci rather than in state
  awscli ecr describe-repositories --repository-names aiops > "$e/ecr.json"
  awscli s3api get-bucket-lifecycle-configuration --bucket ai-incident-loki-000000000000 > "$e/loki-lifecycle.json"
  awscli secretsmanager describe-secret --secret-id ai-incident/aiops > "$e/secret.json"
  awscli budgets describe-budgets --account-id 000000000000 > "$e/budgets.json"
  awscli eks describe-cluster --name ai-incident > "$e/eks-cluster.json"
  local ng a sa
  for ng in app monitoring; do awscli eks describe-nodegroup --cluster-name ai-incident --nodegroup-name "$ng" > "$e/nodegroup-$ng.json"; done
  awscli eks list-addons --cluster-name ai-incident > "$e/eks-addons.json"
  awscli eks list-pod-identity-associations --cluster-name ai-incident > "$e/pod-identity.json"
  grep -q '"imageTagMutability": "IMMUTABLE"' "$e/ecr.json" || die "ECR not IMMUTABLE"
  grep -q '"Days": 7' "$e/loki-lifecycle.json" || die "loki lifecycle not 7 days"
  grep -q '"version": "1.35"' "$e/eks-cluster.json" || die "EKS version not 1.35"
  grep -q '"workload": "app"' "$e/nodegroup-app.json" && grep -q '"workload": "monitoring"' "$e/nodegroup-monitoring.json" || die "nodegroup labels"
  for a in vpc-cni coredns kube-proxy eks-pod-identity-agent aws-ebs-csi-driver; do grep -q "\"$a\"" "$e/eks-addons.json" || die "addon $a missing"; done
  for sa in external-secrets loki ebs-csi-controller-sa; do grep -q "\"$sa\"" "$e/pod-identity.json" || die "pod identity $sa missing"; done
  # cluster side: ArgoCD really runs in floci's k3s and holds the root app with the contract values
  docker exec "$k3s" kubectl -n argocd get pods > "$e/argocd-pods.txt"
  docker exec "$k3s" kubectl -n argocd get application aiops-root -o json > "$e/root-app.json"
  python3 - "$e/root-app.json" <<'EOF' || die "root app wrong ($e/root-app.json)"
import json, sys
a = json.load(open(sys.argv[1]))
s = a["spec"]["source"]
assert s["repoURL"] == "https://github.com/IKYU925/AI_auto_pipeline.git" and s["path"] == "deploy/argocd" and s["targetRevision"] == "main", s
v = s["helm"]["valuesObject"]
assert v == {"targetRevision": "main", "region": "ap-northeast-2", "ecrRepositoryUrl": v["ecrRepositoryUrl"], "lokiBucket": "ai-incident-loki-000000000000"}, v
assert v["ecrRepositoryUrl"].endswith("/aiops"), v
assert a["spec"]["syncPolicy"]["automated"] == {"prune": True, "selfHeal": True}, a["spec"]["syncPolicy"]
assert "resources-finalizer.argocd.argoproj.io" in a["metadata"]["finalizers"], a["metadata"]
EOF
  grep -q 'argocd-server.*Running' "$e/argocd-pods.txt" || die "argocd-server not Running ($e/argocd-pods.txt)"
  tf envs/aiops-eks/base plan -detailed-exitcode -input=false -no-color "${bvars[@]}" > "$e/base-replan.txt" 2>&1 \
    || die "base re-plan not clean (exit $?) - see $e/base-replan.txt"
  tf envs/aiops-eks/cluster plan -detailed-exitcode -input=false -no-color "${cvars[@]}" > "$e/cluster-replan.txt" 2>&1 \
    || die "cluster re-plan not clean (exit $?) - see $e/cluster-replan.txt"
  # eks.sh leftovers against floci: the cluster layer counts, the base layer does not
  local lo=(env AWS_ENDPOINT_URL="http://127.0.0.1:$AWS_PORT" AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test "$REPO/terraform/envs/aiops-eks/eks.sh" leftovers)
  "${lo[@]}" > "$e/leftovers-up.txt" 2>&1 && die "leftovers found nothing while the cluster is up ($e/leftovers-up.txt)"
  # eks.sh down's in-cluster step, from the host against k3s: the root app cascade must finish before helm uninstall
  sed "s#host.docker.internal#127.0.0.1#" "$d/cluster/kubeconfig" > "$d/cluster/kubeconfig.host"
  KUBECONFIG="$d/cluster/kubeconfig.host" "$REPO/terraform/envs/aiops-eks/eks.sh" drain > "$e/drain.txt" 2>&1 || die "eks.sh drain failed ($e/drain.txt)"
  docker exec "$k3s" kubectl get applications -A --no-headers > "$e/apps-after-drain.txt" 2>&1 || true
  [[ ! -s "$e/apps-after-drain.txt" ]] || grep -q 'No resources found' "$e/apps-after-drain.txt" || die "applications left after drain ($e/apps-after-drain.txt)"
  tf envs/aiops-eks/cluster destroy -auto-approve -input=false -no-color "${cvars[@]}" > "$e/cluster-destroy.txt" 2>&1 \
    || die "cluster destroy failed ($e/cluster-destroy.txt)"
  "${lo[@]}" > "$e/leftovers-down.txt" 2>&1 || die "leftovers after cluster destroy ($e/leftovers-down.txt)"
  log "PASS aiops-eks -> $e"
}

drive_ansible_lab() {
  local e r; e="$(ev ansible-lab)"; r="$(run_dir)"; mkdir -p "$e"
  command -v ansible-playbook >/dev/null || die "ansible-playbook not installed (pip install -r ansible/requirements.txt)"
  compose --profile ansible-lab up -d --quiet-pull ansible-target >/dev/null 2>&1 || die "ansible-target failed to start"
  local g="$r/work/galaxy"
  ( cd "$REPO/ansible" && ansible-galaxy role install -r requirements.yml -p "$g/roles" \
      && ansible-galaxy collection install -r requirements.yml -p "$g/collections" ) > "$e/galaxy.txt" 2>&1 \
    || die "ansible-galaxy failed ($e/galaxy.txt)"
  export ANSIBLE_ROLES_PATH="$REPO/ansible/roles:$g/roles" ANSIBLE_COLLECTIONS_PATH="$g/collections" ANSIBLE_LOG_PATH="$e/ansible.log"
  ( cd "$REPO/ansible" && ansible -i inventories/local all -m ansible.builtin.ping ) > "$e/ping.txt" 2>&1 || die "ping failed ($e/ping.txt)"
  ( cd "$REPO/ansible" && ansible-playbook -i inventories/local playbooks/site.yml --diff ) > "$e/site-run1.txt" 2>&1 || die "site.yml failed ($e/site-run1.txt)"
  ( cd "$REPO/ansible" && ansible-playbook -i inventories/local playbooks/site.yml ) > "$e/site-run2.txt" 2>&1 || die "site.yml 2nd run failed ($e/site-run2.txt)"
  grep -Eq 'changed=0 .*failed=0' "$e/site-run2.txt" || die "2nd run not idempotent ($e/site-run2.txt)"
  docker exec "$LAB_CONTAINER" stat -c '%U:%G %a %n' /opt/sample-app /opt/sample-app/compose.yml > "$e/target-files.txt"
  docker exec "$LAB_CONTAINER" cat /opt/sample-app/compose.yml > "$e/target-compose.yml"
  grep -q 'nginx-unprivileged' "$e/target-compose.yml" || die "rendered compose.yml lacks app image"
  log "PASS ansible-lab -> $e"
}

cmd_cleanup() {
  local r=""; [[ -e "$CUR" ]] && r="$(cd "$CUR" && pwd -P)"
  # k3s and ECR registry containers that floci started through the docker socket carry no compose label
  docker ps -aq --filter label=floci=true | xargs -r docker rm -f >/dev/null
  docker compose -p "$PROJECT" -f "$COMPOSE_FILE" --env-file "${r:-$REPO/local}/work/.env" \
    --profile aws --profile localstack --profile ansible-lab down -v --remove-orphans >&2 2>/dev/null \
    || docker compose -p "$PROJECT" down -v --remove-orphans >&2 || true
  # their networks and volumes go once floci itself (still attached to the VPC networks) is down
  docker network ls -q --filter name=floci-aws- | xargs -r docker network rm >/dev/null
  docker volume ls -q --filter name=floci-aws- | xargs -r docker volume rm >/dev/null
  if [[ -n "$r" ]]; then rm -rf "$r/work"; rm -f "$CUR"; log "removed work dir; evidence kept at $r/evidence"; fi
  docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" | grep -q . && die "containers of $PROJECT still exist" || log "cleanup done"
}

case "${1:-}" in
  launch)  cmd_launch ;;
  doctor)  cmd_doctor ;;
  drive)   case "${2:-}" in
             local-app) drive_local_app ;; local-aws) drive_local_aws ;;
             tf-static) drive_tf_static ;; ansible-lab) drive_ansible_lab ;; aiops-eks) drive_aiops_eks ;;
             *) die "drive <local-app|local-aws|tf-static|ansible-lab|aiops-eks>" ;; esac ;;
  tf)      shift; tf "$@" ;;
  aws)     shift; awscli "$@" ;;
  cleanup) cmd_cleanup ;;
  *) sed -n '2,11p' "$0"; exit 2 ;;
esac
