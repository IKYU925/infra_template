#!/usr/bin/env bash
# verify-infra helper. Drives the LOCAL stand-in of this infra template (docker compose + floci + ansible-lab).
# It never touches real AWS (dev/prod). See ../SKILL.md.
#
#   verify.sh launch                 # start isolated stack (compose project "verify-infra")
#   verify.sh doctor                 # read-only: is the running instance ours and usable?
#   verify.sh drive <feature>        # local-app | local-aws | tf-static | ansible-lab
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
compose() { local r; r="$(run_dir)"; docker compose -p "$PROJECT" -f "$COMPOSE_FILE" --env-file "$r/work/.env" "$@"; }
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
  docker exec ${PROJECT}-app-1 env | grep -E '^(DATABASE_URL|AWS_ENDPOINT_URL|AWS_REGION)=' | sed 's#://\([^:]*\):[^@]*@#://\1:***@#' > "$e/app-env.txt"
  # app -> postgres over the compose network (what a real app would do)
  docker exec ${PROJECT}-postgres-1 psql -U app -d app -c "create table if not exists verify_probe(id int); insert into verify_probe values (1);" > "$e/db-write.txt"
  docker exec ${PROJECT}-postgres-1 psql -U app -d app -tAc "select current_setting('server_version_num'), (select count(*) from verify_probe)" > "$e/db-read.txt"
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
  grep -q '"host":"postgres"' "$e/secret.json" || die "secret content unexpected"
  # idempotency: second plan must be empty
  tf envs/local plan -detailed-exitcode -input=false -no-color -var aws_endpoint=http://aws:4566 > "$e/tf-replan.txt" 2>&1 \
    || die "re-plan not clean (exit $?) - see $e/tf-replan.txt"
  log "PASS local-aws -> $e"
}

drive_tf_static() {
  local e rc=0; e="$(ev tf-static)"; mkdir -p "$e"
  tf . fmt -check -recursive -diff -no-color > "$e/fmt.txt" 2>&1 || { log "FAIL fmt (see $e/fmt.txt)"; rc=1; }
  for d in bootstrap envs/local envs/dev envs/prod; do
    local f="$e/validate-${d//\//-}.txt"
    { tf "$d" init -backend=false -input=false -no-color && tf "$d" validate -no-color; } > "$f" 2>&1 \
      && log "ok   validate $d" || { log "FAIL validate $d (see $f)"; rc=1; }
  done
  [[ $rc == 0 ]] && log "PASS tf-static -> $e" || die "tf-static failed -> $e"
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
  docker compose -p "$PROJECT" -f "$COMPOSE_FILE" --env-file "${r:-$REPO/local}/work/.env" \
    --profile aws --profile localstack --profile ansible-lab down -v --remove-orphans >&2 2>/dev/null \
    || docker compose -p "$PROJECT" down -v --remove-orphans >&2 || true
  if [[ -n "$r" ]]; then rm -rf "$r/work"; rm -f "$CUR"; log "removed work dir; evidence kept at $r/evidence"; fi
  docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" | grep -q . && die "containers of $PROJECT still exist" || log "cleanup done"
}

case "${1:-}" in
  launch)  cmd_launch ;;
  doctor)  cmd_doctor ;;
  drive)   case "${2:-}" in
             local-app) drive_local_app ;; local-aws) drive_local_aws ;;
             tf-static) drive_tf_static ;; ansible-lab) drive_ansible_lab ;;
             *) die "drive <local-app|local-aws|tf-static|ansible-lab>" ;; esac ;;
  tf)      shift; tf "$@" ;;
  aws)     shift; awscli "$@" ;;
  cleanup) cmd_cleanup ;;
  *) sed -n '2,11p' "$0"; exit 2 ;;
esac
