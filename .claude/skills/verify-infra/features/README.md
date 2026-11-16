# verify-infra feature map

User-facing features of infra_template, from the point of view of an engineer running `make` targets. Each file says how to reach the feature, how to drive it with `scripts/verify.sh`, and what end state proves it.

| Feature | File | Drive | Real-target equivalent |
|---|---|---|---|
| Local AWS via Terraform (floci) | [local-aws.md](local-aws.md) | `drive local-aws` | `make local-aws-up` |
| Terraform static checks, all roots | [tf-static.md](tf-static.md) | `drive tf-static` | `make tf-validate`, CI `terraform` fmt/validate |
| Ansible site.yml on the lab container | [ansible-lab.md](ansible-lab.md) | `drive ansible-lab` | `make ansible-run ENV=local` (dev/prod use SSM, not drivable) |
| Local app + postgres stack | [local-app.md](local-app.md) | `drive local-app` | `make local-up` |
| AI_auto_pipeline EKS (base + cluster) | [aiops-eks.md](aiops-eks.md) | `drive aiops-eks` | `make eks-base-up`, `make eks-up`/`eks-down` |

Not mapped (cannot be driven locally without real AWS or GitHub, so do not claim them proven):

- `make tf-plan/tf-apply ENV=dev|prod`, `terraform/bootstrap` apply, the CI `plan`/`apply` jobs (need OIDC roles and real accounts).
- `make eks-up`/`eks-down`, `eks.sh down` ordering, the `eks` schedule workflow (need a real account and kubectl against real EKS). The operator ran them once on the lab account; [aiops-eks.md](aiops-eks.md) lists what that run proved and what it caught.
- `make ansible-ping/run ENV=dev|prod` (aws_ec2 dynamic inventory + SSM connection).
- `make scan` (Trivy + Checkov). Drivable with Docker, but it is a static scan, not app behaviour; run it directly when a change touches security config.
- LocalStack profile (`make local-localstack-up`): same port as floci, image may need an auth token.
