# Ansible site.yml on the lab container

Runs the full `playbooks/site.yml` (hardening -> docker -> app) with `inventories/local` against the `ansible-lab` Ubuntu 24.04 systemd container, connecting via `community.docker.docker`.

## Sub-features

- `ansible-ping` inventory resolves `local-app-01` and it answers `ping`.
- `ansible-hardening` play runs; OS/SSH hardening is skipped because `apply_os_hardening/apply_ssh_hardening: false` in local group_vars.
- `ansible-docker` play runs; Docker install skipped (`install_docker: false`).
- `ansible-app` role creates `/opt/sample-app` (root:root 0750) and renders `compose.yml` (0640) with the app image; `docker compose up` is skipped (`app_compose_up` follows `install_docker`).
- `ansible-idempotent` second run reports `changed=0`.

## How to get to it (user POV)

- `docker compose -f local/docker-compose.yml --env-file local/.env --profile ansible-lab up -d`, `make ansible-deps`, `make ansible-run ENV=local`.

## Driving it with verify.sh

Preconditions: `$S launch` done, `ansible-playbook` on host, no other `infra-local-ansible-target` container.

- **Run.** `$S drive ansible-lab`. Starts the lab container in project `verify-infra`, installs Galaxy roles/collections into `work/galaxy` (not `ansible/.galaxy`), runs ping, site.yml twice.
- **Proof.** `evidence/ansible-lab/site-run1.txt` shows the app tasks `changed`; `site-run2.txt` recap `changed=0 ... failed=0`; `target-files.txt` = `root:root 750 /opt/sample-app` and `root:root 640 /opt/sample-app/compose.yml`; `target-compose.yml` contains `nginx-unprivileged`. Full log in `ansible.log`.

## Gotchas

- Hardening and Docker install are skipped in this lab, so this does **not** prove `devsec.hardening` or `geerlingguy.docker` on a real host. Changes to `hardening.yml` group_vars for dev/prod are only syntax-checked by CI.
- The lab image is `geerlingguy/docker-ubuntu2404-ansible:latest` (unpinned) and is privileged with host cgroups.
- dev/prod use the `aws_ec2` inventory + SSM (`ansible_aws_ssm_bucket_name`); that path is not exercised.
