---
name: verify-infra
description: Prove changes to the infra_template repo (Terraform for AWS + Ansible + local Docker Compose) actually work, by driving the LOCAL stand-in, never real AWS. Use after editing terraform/ (modules, envs, bootstrap), ansible/ (playbooks, roles, inventories), local/docker-compose.yml, or the Makefile, when asked to "verify", "test", "prove", or "run" the infra. Covers terraform apply against the floci AWS emulator, fmt/validate of every root including dev/prod, ansible site.yml against a container, and the compose app+postgres stack.
---

# verify-infra

What this repo is: an infra **template**. Terraform builds AWS (`terraform/bootstrap` = state bucket + lock table + GitHub OIDC roles; `terraform/modules/platform` = VPC/SG/EC2/RDS/S3/IAM used by `envs/dev` and `envs/prod`), Ansible configures the EC2 hosts (`site.yml` = hardening -> docker -> app), and `local/` + `terraform/envs/local` + the `ansible-lab` profile are the cost-free local stand-in. GitHub Actions run fmt/validate/tflint/plan/apply and Trivy/Checkov.

There is no UI. The "user" is an infra/fullstack/security engineer running `make` targets. You drive it with one helper:

```bash
S=.claude/skills/verify-infra/scripts/verify.sh   # run from repo root
$S launch | $S doctor | $S drive <feature> | $S tf <dir> <args> | $S aws <args> | $S cleanup
```

**Hard rule: never run `terraform apply`/`plan` against `envs/dev`, `envs/prod`, `envs/aiops-lab`, or `bootstrap` with real credentials, and never `make tf-apply`.** Those create billable AWS resources in shared accounts (`allowed_account_ids` are placeholders `111111111111`, `backend.hcl` has `CHANGE_ME`). Real dev/prod is proven only by `tf-static` locally plus the CI `plan` job. If the user explicitly asks for a real plan, have them run it themselves.

## Prerequisites

- Docker running (Docker Desktop). Terraform and the AWS CLI are **not** needed on the host: the helper uses `hashicorp/terraform:1.17.1` (same as CI) and `amazon/aws-cli` containers.
- `ansible-playbook` on the host only for `drive ansible-lab` (`pip install -r ansible/requirements.txt`).
- Network access: first run pulls images, Terraform registry modules, and Ansible Galaxy content.

## Launch

```bash
$S launch
```

- Creates `.verify-runs/<timestamp>/` (gitignored) with `work/` (scratch) and `evidence/`, and points `.verify-runs/current` at it.
- Writes `work/.env` from `local/.env.example` with **shifted ports** (postgres `15432`, app `18080`) so it never collides with the user's own `make local-up` (5432/8080). Copies `terraform/` into `work/terraform/` so the user's own `terraform/envs/local/terraform.tfstate` is never touched.
- Starts compose project **`verify-infra`** with the `aws` profile (postgres + app + floci) and `--wait` until all healthchecks pass, then runs `doctor`.
- Ready = the line `READY: app http://127.0.0.1:18080 ...` after six `ok` lines. Empty data dir is fine: postgres initialises the `app` DB itself; floci starts empty and `drive local-aws` creates the resources.

Isolation limits (launch refuses rather than sharing):
- floci binds fixed host port **4566** and the ansible-lab container has fixed `container_name: infra-local-ansible-target`. So only **one** verify run at a time, and not while the user has `make local-aws-up`, `local-localstack-up`, or ansible-lab running.
- If launch says the project already exists, run `$S doctor`; if it is a stale run of yours, `$S cleanup` and relaunch.

## Doctor

```bash
$S doctor
```

Read-only. Checks each host port (15432/18080/4566) is owned by a `verify-infra-*` container, postgres answers `select 1`, app returns HTTP 200, floci `/_floci/health` reports `secretsmanager` running. Exit 0 = worth driving. Run it first whenever anything looks off.

## Drive

Features live in [`features/`](features/README.md). Each `drive` target exits non-zero with the path of the failing log on failure.

| Command | Proves |
|---|---|
| `$S drive local-aws` | `terraform/envs/local` applies to floci, the S3 bucket + Secrets Manager secret really exist, re-plan is empty |
| `$S drive tf-static` | `terraform fmt -check` + `init -backend=false && validate` for bootstrap, envs/local, envs/dev, envs/prod, envs/aiops-lab (what CI `fmt`/`validate` do) |
| `$S drive ansible-lab` | `ansible ping` + `site.yml` against the Ubuntu 24.04 lab container, idempotent 2nd run, rendered `/opt/sample-app/compose.yml` |
| `$S drive aiops-lab` | `terraform/envs/aiops-lab` (AI_auto_pipeline 4단계) applies to floci with a test-only provider override, an EventBridge `CloudWatch Alarm State Change` event for our alarm lands in SQS, another alarm's event does not |
| `$S drive local-app` | app container serves HTTP 200 with the right env wiring, postgres accepts writes |

Ad-hoc access to the same instance:

```bash
$S tf envs/local state list                    # terraform in work/terraform/<dir>, on the compose network
$S aws s3 ls                                   # aws cli -> floci (http://aws:4566 inside the network)
docker exec verify-infra-postgres-1 psql -U app -d app -c '\dt'
```

Inside containers the emulator host is `aws:4566` (compose alias), so pass `-var aws_endpoint=http://aws:4566` to any terraform plan/apply of `envs/local`.

## Evidence

Everything goes to `.verify-runs/<timestamp>/evidence/<feature>/` (log files, JSON from the emulator, rendered files from the target). Standards:

- Drive the real path a user takes (the same terraform roots, the same playbooks and inventories, the same compose file). Do not hand-create buckets or files to make a check pass.
- Capture the action (`tf-apply.txt`, `site-run1.txt`) **and** the resulting state observed independently (`aws s3api ...` against floci, `docker exec ... cat` on the target), not just "Apply complete!".
- Prove idempotency where the tool promises it (`tf-replan.txt` must say no changes; `site-run2.txt` must have `changed=0`).
- floci is the stand-in for AWS APIs only. A green `local-aws` says nothing about VPC/EC2/RDS/IAM in `modules/platform`; those are covered only by `tf-static` (syntactic/schema) and CI plan.

When you report, quote the key lines and give the evidence path.

## Cleanup

```bash
$S cleanup
```

Runs `docker compose -p verify-infra ... down -v --remove-orphans` across all profiles (kills only what launch started, by compose project label, never by process name), deletes `work/` (env file, terraform copy + state, galaxy content), removes the `current` link, and fails loudly if any `verify-infra` container survives. **`evidence/` is kept.** Run cleanup after every failed iteration too. Delete old runs by hand with `rm -rf .verify-runs/<timestamp>` when no longer needed.

## Helpers

- `scripts/verify.sh` (executable). Subcommands above; `$S` with no args prints usage. Edit the constants at its top (ports, images) if the repo's compose file changes ports or images.
