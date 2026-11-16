# aiops-eks (AI_auto_pipeline 4단계 EKS)

`terraform/envs/aiops-eks` builds the AWS side of AI_auto_pipeline stage 4 in two states. `base` (ECR `aiops`, Loki bucket, secret `ai-incident/aiops`, Pod Identity roles, budget) lives for the whole project. `cluster` (VPC, NAT, EKS 1.35, node groups `app`/`monitoring`, add-ons, Pod Identity associations, ArgoCD, root app `aiops-root`) runs only in core time and reads `base` through `terraform_remote_state`. Operations and the consumer contract are in `docs/aiops-eks.md`.

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
- **Proof.** `base-apply.txt` and `cluster-apply.txt` end with `Apply complete!`; `root-app.json`, `argocd-pods.txt`, `eks-*.json`, `nodegroup-*.json`, `pod-identity.json` are read from floci and k3s, not from state; `*-replan.txt` say `No changes.`; `drain.txt` shows `application.argoproj.io "aiops-root" deleted` and `apps-after-drain.txt` is empty; `leftovers-up.txt` lists cluster ARNs, `leftovers-down.txt` says `leftovers: 0`.
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
- Not proven locally: real nodes joining, NAT egress, Pod Identity credential injection (floci serves no https webhook), EBS volumes from PVCs, `eks.sh up`/`down`/`sweep` against real EKS (endpoint allow-list update, kubeconfig from `aws eks`), the `eks` workflow.
