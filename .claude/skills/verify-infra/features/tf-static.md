# Terraform static checks (all roots)

Formats and validates every Terraform root, including the real-AWS ones (`bootstrap`, `envs/dev`, `envs/prod`) without credentials or a backend. This is the strongest local proof available for changes to `modules/platform`.

## Sub-features

- `tf-fmt` `terraform fmt -check -recursive` over `terraform/`.
- `tf-validate-bootstrap`, `tf-validate-local`, `tf-validate-dev`, `tf-validate-prod` `init -backend=false` + `validate` per root (downloads pinned registry modules and the `~> 6.71` aws provider).

## How to get to it (user POV)

- `make tf-fmt` (writes, does not check) and `make tf-validate`.
- CI: `.github/workflows/terraform.yml` jobs `fmt` and `validate (<dir>)`.

## Driving it with verify.sh

Preconditions: `$S launch` done (only the run dir and docker network are used; containers need not be healthy).

- **Run.** `$S drive tf-static`. Prints `ok   validate <dir>` for 4 roots, then `PASS tf-static`.
- **Proof.** `evidence/tf-static/fmt.txt` is empty (no diff); each `validate-<dir>.txt` ends with `Success! The configuration is valid.`
- **Single root.** `$S tf envs/prod validate -no-color` after an init in that dir.

## Gotchas

- Uses Terraform 1.17.1 (CI version). The repo allows `>= 1.11.1`; a feature newer than 1.11 can pass here and fail for a teammate on an older CLI.
- `tflint` (CI step) is not run here. If the change could trip a lint rule, run `docker run --rm -v "$PWD/terraform:/data" -w /data ghcr.io/terraform-linters/tflint --recursive` separately.
- Validate does not evaluate `allowed_account_ids`, backend values, or AWS-side constraints (instance type availability, RDS version strings). Only CI plan with real roles catches those.
