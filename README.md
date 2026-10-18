# IaC comparison demo

The same AWS stack, built three times with three different infrastructure-as-code
tools — CloudFormation, CDK, and Terraform — so the tools can be compared side by
side.

## The stack

Each variant provisions an identical, self-contained HTTP service in `us-east-1`:

- An internet-facing Application Load Balancer (HTTP :80), reachable only from the
  deploying host's public IP, fronting a target group that health-checks
  `GET /health.php`.
- An auto scaling group of 1–3 `t2.micro` instances launched from a pre-baked
  Amazon Linux image that runs the PHP web server (`index.php`, `health.php`).
- Step-scaling policies driven by CloudWatch CPU alarms: scale out by one instance
  above 40% average CPU, scale in by one below 10%.
- No IAM roles or SSH key pairs.

Every resource is tagged with `ProvisionedBy` set to the tool that created it.

## Layout

| Directory | Tool |
| --- | --- |
| `cloudformation/` | YAML template |
| `cdk/` | AWS CDK (TypeScript) |
| `terraform/` | Terraform (HCL) |

Each directory is self-contained: it holds the stack definition, a `deploy.sh`, a
`destroy.sh`, and a `verify.sh` gate that asserts the real AWS resources match the
intended design (ALB, target health, alarms, scaling policies, locked-down ingress,
tags). The repository root has `deploy-all.sh` and `teardown-all.sh` to drive all
three variants at once.

The goal is not the service itself but the comparison: how each tool expresses the
same design, and how long each takes to go from running the deploy to the first
successful load balancer response.
