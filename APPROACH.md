# Process Documentation

DevOps Engineer Assignment — Octa Byte AI Pvt Ltd

This document covers the decisions made, the implementation approach, and the reasoning behind the architecture.

---

## What Was Built

A production-grade platform on AWS for a Node.js REST API (Todo app). The application itself is simple by design — the focus is entirely on the infrastructure and automation around it.

**Infrastructure:**
- VPC with public and private subnets across two AZs
- EKS 1.33 cluster with managed node group (AL2023, t3.small)
- RDS PostgreSQL 15 in private subnets
- ALB provisioned by the AWS Load Balancer Controller
- ECR repository with image scanning
- Bastion host with SSM access
- CloudWatch monitoring (dashboards, alarms, logs)
- Secrets Manager with External Secrets Operator

**Automation:**
- Terraform modules for all infrastructure
- GitHub Actions for CI/CD (tests, build, push, deploy, rollback)
- `setup.sh` for one-command full environment setup

---

## Technology Decisions

### EKS over ECS
EKS was chosen over ECS because Kubernetes is the industry standard for container orchestration. It demonstrates more depth — IRSA, External Secrets Operator, HPA, Ingress controllers — and the skills transfer across cloud providers. ECS would have been simpler but less representative of real production environments.

### AL2023 over AL2
Amazon Linux 2 is end-of-life for EKS 1.33+. AL2023 is the required AMI type for EKS 1.33 managed node groups.

### t3.small over t3.micro
t3.micro has a VPC CNI pod limit of 4 per node. System pods (coredns, kube-proxy, aws-node, ebs-csi) already consume those slots, leaving no room for application pods. t3.small supports 11 pods per node and is still free-tier eligible.

### External Secrets Operator over direct SDK calls
The app reads secrets from environment variables, not from the AWS SDK. ESO handles the sync from Secrets Manager to Kubernetes Secrets at the platform layer. This keeps the application code cloud-agnostic and means secret rotation doesn't require code changes.

### IP target mode on ALB
The ALB registers pod IPs directly in the target group, bypassing kube-proxy. This gives better performance and simpler security group rules compared to NodePort mode.

### Secrets Manager over SSM Parameter Store
Secrets Manager has better support for automatic rotation, a cleaner audit trail, and native integration with External Secrets Operator. For this use case the cost difference is negligible.

### Single NAT Gateway
One NAT Gateway instead of one per AZ. This is a cost optimization — a second NAT Gateway adds ~$32/month for HA that isn't needed in a demo environment. In production, `one_nat_gateway_per_az = true` should be used.

### HTTP only on ALB
HTTPS requires an ACM certificate which requires a registered domain. Since this is a demo without a domain, HTTP is used. In production, request an ACM cert and add an HTTPS listener with HTTP → HTTPS redirect.

---

## Architecture

```
Internet
    |
    v
ALB (public subnets, us-east-1a + us-east-1b)
    |
    v
EKS pods (private subnets, IP target mode)
    |
    |---> RDS PostgreSQL (private subnets, SSL)
    |---> Secrets Manager (via ESO + IRSA)
    |---> CloudWatch Logs (via Fluent Bit DaemonSet)
```

**Networking:**
- Public subnets: `10.0.1.0/24`, `10.0.2.0/24` — ALB and bastion
- Private subnets: `10.0.10.0/24`, `10.0.11.0/24` — EKS nodes and RDS
- NAT Gateway in public subnet for outbound traffic from private subnets (ECR pulls, API calls)

**Security groups:**
- ALB SG: inbound 80/443 from internet, outbound to EKS cluster SG
- EKS cluster SG: inbound from ALB on port 3000, inbound 443 from public subnets (bastion → API server)
- RDS SG: inbound 5432 from EKS cluster SG and bastion SG only

**IRSA (IAM Roles for Service Accounts):**

Each service account has its own scoped IAM role. No broad node-level permissions.

| Service Account | Permissions |
|---|---|
| `devops-demo-app` | `secretsmanager:GetSecretValue` for app secrets |
| `external-secrets` | `secretsmanager:GetSecretValue`, `ListSecrets`, `DescribeSecret` |
| `aws-load-balancer-controller` | Full ELB management |
| `fluent-bit` | CloudWatch Logs write |
| `ebs-csi-controller-sa` | EBS volume management |

---

## Terraform Structure

All infrastructure is in Terraform modules under `terraform/modules/`. The `terraform/production/` directory is the root module that wires everything together.

**Modules:**
- `vpc` — VPC, subnets, IGW, NAT GW, route tables, EKS subnet tags
- `security_groups` — all security groups and rules
- `iam` — IRSA roles for app, ESO, LB controller, Fluent Bit
- `ecr` — ECR repository, lifecycle policy, IAM access
- `eks` — EKS cluster, managed node group, OIDC provider, Helm charts (LB controller, ESO, Fluent Bit, Metrics Server)
- `rds` — RDS instance, subnet group, parameter group
- `bastion` — EC2, EIP, IAM role, SSM, EKS access entry, SG rules
- `secrets` — Secrets Manager secrets for DB credentials and app config
- `alb` — Kubernetes Ingress resource that triggers ALB creation
- `monitoring` — CloudWatch log groups, dashboards, alarms, SNS

**Remote state:**
- S3 bucket: `devops-demo-tfstate-<account-id>` (versioned, encrypted, public access blocked)
- DynamoDB table: `terraform-state-lock` (prevents concurrent applies)

---

## CI/CD Pipeline

**deploy-production.yml** — push to `main` (app/, k8s/, terraform/ paths)

```
push to main
    |
    v
Run Tests (Jest + Postgres service container)
    |
    v
Build & Push to ECR (tagged with git SHA)
    |
    v
Manual Approval (GitHub Environment: production)
    |
    v
Deploy to EKS
  - kubectl apply all manifests
  - run DB migration job
  - wait for rollout
    |
    v
Auto-rollback if deploy fails
```

**pr-checks.yml** — pull requests to `main`
- Tests, lint, npm audit, Docker build, Trivy scan, Terraform validate
- Posts a summary comment on the PR

**security-scan.yml** — weekly (Monday 06:00 UTC)
- npm audit, Trivy scan on latest ECR image, tfsec on Terraform

**Image tagging:** every image is tagged with the full git SHA. The `latest` tag is also pushed for convenience but production deploys always use the SHA tag.

**GitHub secrets required:**
- `AWS_ACCESS_KEY_ID` — IAM user `github-actions-ci`
- `AWS_SECRET_ACCESS_KEY` — same user
- `GH_PAT` — Personal Access Token with repo + workflow scope

**GitHub Environment:** `production` environment with required reviewers configured. This creates the manual approval gate before the deploy job runs.

---

## Secret Management

Secrets flow:

```
AWS Secrets Manager
    |
    | (IRSA - ESO service account assumes IAM role)
    v
External Secrets Operator (running in cluster)
    |
    | (syncs every 1 hour)
    v
Kubernetes Secret (db-credentials, app-secrets)
    |
    | (mounted as env vars)
    v
Application Pod
```

The app reads `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` from environment variables. It has no knowledge of Secrets Manager or Kubernetes secrets — it just reads env vars.

Secrets stored:
- `devops-demo/production/db-credentials` — host, username, password, dbname, port
- `devops-demo/production/app-secrets` — NODE_ENV

---

## Monitoring

**CloudWatch Container Insights** is enabled on the EKS cluster. It automatically collects node and pod CPU, memory, network, and disk metrics.

**Fluent Bit** runs as a DaemonSet on every node and ships container logs to `/app/production` in CloudWatch Logs. The app outputs structured JSON logs, making them queryable with CloudWatch Logs Insights.

**Dashboards:**
- `devops-demo-production-infrastructure` — node/pod metrics, RDS, ALB
- `devops-demo-production-application` — request rate, latency, error rate

**Alarms → SNS → email:**
- EKS node CPU > 80%
- RDS CPU > 75%
- RDS free storage < 5 GB
- RDS connections > 80
- ALB 5xx > 10/min
- ALB p95 latency > 2s

---

## Deployment Flow

When a push hits `main` with changes in `app/`, `k8s/`, or `terraform/`:

1. Tests run against a Postgres container in the GitHub Actions runner
2. Docker image is built and pushed to ECR with the git SHA as the tag
3. Trivy scans the image for HIGH/CRITICAL CVEs (non-blocking, reported only)
4. The workflow pauses at the manual approval gate
5. After approval, the deploy job runs:
   - Updates kubeconfig
   - Applies all k8s manifests with `--validate=false`
   - Deletes any existing `db-migrate` job
   - Runs the migration job and waits for completion
   - Applies the deployment with the new image tag
   - Waits for rollout to complete
6. If the rollout fails, the rollback job runs automatically

---

## Bastion

The bastion is in a public subnet with an Elastic IP. It has:
- IAM role with EKS cluster admin access (via `aws-auth` ConfigMap)
- SSM Session Manager enabled (no SSH key required)
- kubectl, helm, psql, git, jq installed via user-data on first boot
- kubeconfig pre-configured for the EKS cluster
- Shell aliases for common operations

The bastion is the only way to access RDS directly (psql). The `dbconnect` alias pulls credentials from Secrets Manager automatically.

---

## Production Hardening (not in demo)

Things that would be added before this goes to real production:

- Restrict bastion SSH to known IP ranges (currently open to 0.0.0.0/0)
- HTTPS on ALB with ACM certificate
- RDS Multi-AZ for high availability
- RDS `backup_retention_period = 7`, `deletion_protection = true`
- VPC Flow Logs for network audit trail
- WAF on ALB
- Kubernetes Network Policies (restrict pod-to-pod traffic)
- Pod Security Standards (enforce `restricted` profile)
- Spot instances for cost savings on non-critical workloads
- Karpenter for better node autoscaling

---

*Last updated: April 2026*
