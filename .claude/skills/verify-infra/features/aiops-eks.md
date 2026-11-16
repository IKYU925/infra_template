# aiops-eks (AI_auto_pipeline 4단계 EKS)

`terraform/envs/aiops-eks` builds the AWS side of AI_auto_pipeline stage 4 in two states. `base` (ECR `aiops`, Loki bucket, secret `ai-incident/aiops`, Pod Identity roles for External Secrets, Loki and EBS CSI, budget) lives for the whole project. `cluster` (VPC, NAT, EKS 1.35, node groups `app`/`monitoring`, add-ons, Pod Identity associations, ArgoCD, root app `aiops-root`) runs only in core time and reads `base` through `terraform_remote_state`. Operations and the consumer contract are in `docs/aiops-eks.md`.

## Sub-features

- `eks-base-apply` base creates against floci.
- `eks-cluster-apply` cluster creates against floci, including both helm releases.
- `eks-outputs` the seven contract outputs exist with the contract names and values.
- `eks-aws-shape` ECR is IMMUTABLE, Loki lifecycle is 7 days, EKS is 1.35, node groups carry `workload=app|monitoring`, the five add-ons exist, Pod Identity covers `external-secrets`, `loki`, `ebs-csi-controller-sa`.
- `eks-argocd` ArgoCD pods run in floci's k3s and `aiops-root` points at `AI_auto_pipeline` `deploy/argocd` with `targetRevision`, `region`, `ecrRepositoryUrl`, `lokiBucket`, automated prune/selfHeal, and the resources finalizer.
- `eks-idempotent` re-plan of both roots reports no changes.
- `eks-drain` `eks.sh drain` (the in-cluster half of `eks.sh down`) deletes `aiops-root`, ArgoCD cascades through every child app, and no Application is left.
- `eks-leftovers` `eks.sh leftovers` fails while the cluster layer exists and passes after the cluster layer is destroyed with base still present.

## How to get to it (user POV)

- `make eks-base-up` once, then `make eks-up` / `make eks-down` (or the `eks` workflow) against the real account.

## Driving it with verify.sh

Preconditions: `$S launch` done (it mounts the docker socket into floci), `$S doctor` green.

- **Run.** `$S drive aiops-eks`. Writes `floci_override.tf` into the run's terraform copy only: floci endpoints, local backends, `terraform_remote_state` from `../base/terraform.tfstate`, helm via k3s's admin kubeconfig, no creator access entry, and no upgrade policy.
- **Two-step cluster apply.** `-target=module.eks -target=aws_eks_pod_identity_association.workload` first, then the kubeconfig is copied out of `floci-aws-eks-ai-incident` (server rewritten to `host.docker.internal:<port>`, TLS verify off), then the full apply.
- **Proof.** `base-apply.txt` and `cluster-apply.txt` end with `Apply complete!`; `root-app.json`, `argocd-pods.txt`, `eks-*.json`, `nodegroup-*.json`, `pod-identity.json` are read from floci and k3s, not from state; `*-replan.txt` say `No changes.`; `drain.txt` shows `application.argoproj.io "aiops-root" deleted` and `apps-after-drain.txt` is empty or `No resources found`; `leftovers-up.txt` lists cluster ARNs, `leftovers-down.txt` says `leftovers: 0`.
- **Ad hoc.** `docker exec floci-aws-eks-ai-incident kubectl -n argocd get applications`, `$S aws eks list-nodegroups --cluster-name ai-incident`.

## Gotchas

- The docker socket mount gives floci control of the host's docker daemon. That is what lets EKS run a real API server; cleanup removes the containers it starts by the `floci=true` label.
- floci only knows the account root as caller, and EKS access entries reject root, so the override turns off `enable_cluster_creator_admin_permissions`. Real runs keep it on.
- floci does not return `upgrade_policy` and does not implement `UpdateClusterConfig`, so the override sets `upgrade_policy = null`. `support_type = STANDARD` is proven only on a real account.
- The AWS provider calls S3 Control at `<account-id>.<endpoint host>`, so floci gets the network alias `000000000000.aws`.
- floci has no `/aws/service/...` public SSM parameters and refuses to create them. The node groups use `use_latest_ami_release_version = false` (EKS picks the latest AMI when it creates a node group), so no lookup happens.
- The root app syncs AI_auto_pipeline's real `deploy/argocd` from `main` into k3s, so child apps (`aiops`, `external-secrets`, `loki`, and others) appear and start pulling images. The drive checks the root app's spec only. Child app health in floci means nothing (no EBS, no Pod Identity).
- The k3s node has no `workload` label, so child app pods stay Pending and their syncs never finish. ArgoCD does not delete an app while its sync is running; `drain` terminates running operations until `aiops-root` is gone. This is the same path a stuck sync on real EKS takes.
- Without `drain` first, `terraform destroy` hits the helm uninstall timeout (5 minutes) while ArgoCD is still cascading through child apps. That is why `eks.sh down` drains before destroy.
- Not proven locally: real nodes joining, NAT egress, Pod Identity credential injection (floci serves no https webhook), EBS volumes from PVCs, add-on configuration schemas, `eks.sh up`/`down`/`sweep` against real EKS (endpoint allow-list update, kubeconfig from `aws eks`), the `eks` workflow. The next section lists which of these the real account has since shown.

## Real-account findings (2026-11-17, first `make eks-up`)

floci passed all of these. Each one broke the first real run.

- **Add-on `configuration_values` is schema-checked by EKS, not by floci.** `controller.k8sTagClusterId` was rejected for `aws-ebs-csi-driver` v1.68.0. Before changing any add-on configuration, read the real schema (read-only, needs AWS credentials): `aws eks describe-addon-configuration --addon-name <addon> --addon-version <v> --query configurationSchema --output text`.
- **GitHub OIDC immutable subject.** This repo's token `sub` is `repo:IKYU925@89255853/infra_template@1443078776:...`, not `repo:IKYU925/infra_template:...`. bootstrap takes it as `github_oidc_sub_prefix`. A role that trusts the old form fails with `Not authorized to perform sts:AssumeRoleWithWebIdentity`.
- **AWS Free plan accounts cannot start t4g.large.** The node group sits in `CREATING` with no health issue and zero EC2 instances. The cause is only in CloudTrail `RunInstances`: `not eligible for Free Tier`. After the upgrade the ASG retried on its own backoff (about 16 minutes after the first failure).
- **ExternalSecrets created before the ClusterSecretStore fail with `not found`** and retry with backoff. They recovered within about 3 minutes; `postgres-0` and alertmanager waited on the missing Secret meanwhile. Not a bug, but it looks like one in the first minutes.
- **The tagging API keeps returning deleted resources.** After the real `eks-down` (`Destroy complete! Resources: 65 destroyed`, 960 s) `leftovers` counted 7 (EBS volumes, a security group, a subnet, a Pod Identity association) that the service APIs reported `NotFound`. floci drops tags immediately, so the drive never saw it. `eks.sh` now checks each ARN with its service API (`gone()`).
- **No metrics-server.** `kubectl top` returns `Metrics API not available`, so node memory for the t4g.medium question has to come from elsewhere.

Proven on the real account: nodes join and go Ready, NAT egress (images pulled from quay.io), Pod Identity (External Secrets read `ai-incident/aiops`), EBS volumes from PVCs carrying `Project=ai-incident`/`Layer=cluster`, `eks.sh up`, `eks.sh down` (drain, destroy, then `leftovers: 0` after the fix), and the `eks` workflow assuming `gha-apply` (`leftovers`, `sweep`).
