# Terraform static checks (all roots)

Formats and validates every Terraform root, including the real-AWS ones (`bootstrap`, `envs/dev`, `envs/prod`, `envs/aiops-eks/base`, `envs/aiops-eks/cluster`) without credentials or a backend. This is the strongest local proof available for changes to `modules/platform`.

## Sub-features

- `tf-fmt` `terraform fmt -check -recursive` over `terraform/`.
- `tf-validate-bootstrap`, `tf-validate-local`, `tf-validate-dev`, `tf-validate-prod`, `tf-validate-aiops-eks-base`, `tf-validate-aiops-eks-cluster` `init -backend=false` + `validate` per root (downloads pinned registry modules and the `~> 6.71` aws provider).

## How to get to it (user POV)

- `make tf-fmt` (writes, does not check) and `make tf-validate`.
- CI: `.github/workflows/terraform.yml` jobs `fmt` and `validate (<dir>)`.

## Driving it with verify.sh

Preconditions: `$S launch` done (only the run dir and docker network are used; containers need not be healthy).

- **Run.** `$S drive tf-static`. Prints `ok   validate <dir>` for 6 roots, then `PASS tf-static`.
- **Proof.** `evidence/tf-static/fmt.txt` is empty (no diff); each `validate-<dir>.txt` ends with `Success! The configuration is valid.`
- **Single root.** `$S tf envs/prod validate -no-color` after an init in that dir.

## Gotchas

- Uses Terraform 1.17.1 (CI version). The repo allows `>= 1.11.1`; a feature newer than 1.11 can pass here and fail for a teammate on an older CLI.
- `tflint` (CI step) is not run here. If the change could trip a lint rule, run `docker run --rm -v "$PWD/terraform:/data" -w /data --entrypoint sh ghcr.io/terraform-linters/tflint:v0.65.0 -c 'tflint --init && tflint --recursive --format compact'` separately (CI pins v0.65.0 and needs `--init` for the aws plugin in `terraform/.tflint.hcl`).
- It checks the copy of `terraform/` taken at `$S launch`. Edits made after launch are not seen until `$S cleanup` and a new launch.
- `drive aiops-eks` in the same run writes `floci_override.tf` into the copy and runs `fmt` there, so a later `drive tf-static` validates the overridden aiops-eks roots and can hide a fmt diff. Run `tf-static` before `aiops-eks`, or in a fresh run.
- Validate does not evaluate `allowed_account_ids`, backend values, or AWS-side constraints (instance type availability, RDS version strings). Only CI plan with real roles catches those.
