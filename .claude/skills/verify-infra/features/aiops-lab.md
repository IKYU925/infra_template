# aiops-lab (AI_auto_pipeline 4단계)

`terraform/envs/aiops-lab` builds the AWS side of AI_auto_pipeline stage 4: one SSM-only arm64 EC2 in a public subnet, CloudWatch alarms named `<tenant>-<service>-<alertname>`, an EventBridge rule that forwards their state changes to SQS, an automation IAM user, ECR, and a budget. The consumer contract is in `docs/aiops-lab.md`.

## Sub-features

- `aiops-apply` all 31 resources create against floci.
- `aiops-outputs` `alarm_names`, `sqs_queue_url`, `log_group_name`, `ecr_repository_url`, `instance_id` are set.
- `aiops-route-own` an alarm state change event for `tenant-a-shopapi-ErrorLogs` reaches the SQS queue.
- `aiops-route-other` an event for an alarm this env does not own is not delivered.
- `aiops-leftovers` `lab.sh leftovers` ignores terminated instances and fails on anything else remaining (stub-tested only).

## How to get to it (user POV)

- Edit `terraform/envs/aiops-lab/terraform.tfvars`, then `make tf-init/tf-plan/tf-apply ENV=aiops-lab` against the real lab account, `lab.sh deploy <ecr image>`, and after destroy `lab.sh leftovers`.

## Driving it with verify.sh

Preconditions: `$S launch` done, `$S doctor` green.

- **Run.** `$S drive aiops-lab`. Writes `floci_override.tf` into the run's terraform copy only (never the repo), applies with `allowed_account_ids=["000000000000"]`.
- **Proof.** `evidence/aiops-lab/tf-apply.txt` ends `Apply complete! Resources: 31 added`; `sqs-own-alarm.json` contains a body with `"detail-type":"CloudWatch Alarm State Change"` and `tenant-a-shopapi-ErrorLogs`; `sqs-other-alarm.json` has no `someone-elses-alarm`.
- **Ad hoc.** `$S aws cloudwatch describe-alarms --query 'MetricAlarms[].AlarmName'`, `$S aws events list-targets-by-rule --rule ai-incident-lab-alarm-state-change`.

## Gotchas

- floci does not emit EventBridge events from `cloudwatch set-alarm-state`, so the drive injects the event with `events put-events`. The real alarm -> EventBridge hop is unverified until a real-account run.
- floci reports `associate_public_ip_address = false` for the instance, so a re-plan wants to replace it. Do not treat that as a repo bug; check re-plan on real AWS.
- floci ECR delete fails with "Backing registry unreachable", so `terraform destroy` hangs on `aws_ecr_repository.app` for 20 minutes. The drive does not destroy; `$S cleanup` removes floci instead.
- The provider override must not set `skip_requesting_account_id`, or `allowed_account_ids` fails with an empty account id.
- Not proven locally: EC2 user_data (dnf docker + CloudWatch Agent on AL2023 arm64), the `fstype=xfs` disk alarm dimension, `lab.sh deploy` over SSM, budgets email.
