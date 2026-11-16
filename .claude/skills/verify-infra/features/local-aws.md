# Local AWS via Terraform (floci)

Applies `terraform/envs/local` to the floci AWS emulator: an S3 artifact bucket built with the same `terraform-aws-modules/s3-bucket` module as dev/prod, and a Secrets Manager secret holding DB connection info.

## Sub-features

- `local-aws-apply` creates bucket `myproject-local-artifacts` and secret `myproject/local/db`.
- `local-aws-bucket` the bucket has versioning `Enabled` and a public access block.
- `local-aws-secret` the secret value is JSON with `host=postgres`, `port=5432`, `username=app`, `dbname=app` and no password.
- `local-aws-idempotent` a second plan reports no changes.
- `local-aws-outputs` `artifact_bucket_name` and `db_secret_arn` outputs are set.

## How to get to it (user POV)

- `make local-aws-up` (compose `aws` profile, then `terraform -chdir=terraform/envs/local init/apply`).
- Then `aws --endpoint-url http://localhost:4566 s3 ls`.

## Driving it with verify.sh

Preconditions: `$S launch` done and `$S doctor` green (floci owns :4566).

- **Apply.** `$S drive local-aws`. Runs init + `apply -var aws_endpoint=http://aws:4566` in the run's terraform copy. `evidence/local-aws/tf-apply.txt` contains `Apply complete! Resources: 5 added` (the outputs follow it).
- **Bucket exists.** Checked from floci, not from state: `s3-buckets.json` lists `myproject-local-artifacts`; `s3-versioning.json` has `"Status": "Enabled"`; `s3-public-access-block.json` has all four `true` (asserted).
- **Secret.** `secret.json` is exactly `{"dbname":"app","host":"postgres","port":5432,"username":"app"}` (asserted, so a password in it fails the drive).
- **Idempotent.** `tf-replan.txt` contains `No changes.` (plan `-detailed-exitcode` returned 0).
- **Ad hoc.** `$S aws secretsmanager list-secrets`, `$S tf envs/local state list`.

## Gotchas

- Inside the compose network the endpoint is `http://aws:4566`; the repo default `http://localhost:4566` only works from the host. Forgetting `-var aws_endpoint=...` makes terraform hang/fail on connection refused.
- floci keeps state in memory: after `cleanup` (or a floci restart) the resources are gone but the terraform state in `work/` would claim they exist. Always relaunch fresh rather than reusing an old `work/`.
- The provider uses fake creds `test/test` and skips STS; account id shows as `000000000000`.
- This proves the S3/Secrets Manager wiring only. VPC/EC2/RDS in `modules/platform` are never applied locally.
- Launch gives floci a second network alias `000000000000.aws` because the AWS provider calls S3 Control at `<account>.<endpoint host>`. `make local-aws-up` has only the `aws` alias, so an S3 Control failure there is not reproduced here.
