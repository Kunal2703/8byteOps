# 8byteOps — AWS EKS Production Platform

**DevOps Engineer Assignment — Octa Byte AI Pvt Ltd**

End-to-end infrastructure automation on AWS. EKS cluster, RDS PostgreSQL, ALB, ECR, Bastion, CloudWatch monitoring, and a full GitHub Actions CI/CD pipeline — all provisioned with Terraform and deployed with a single script.

---

## Architecture

```
Internet
    |
    v
Application Load Balancer  (public subnets - us-east-1a, us-east-1b)
    |
    v
EKS Pods - 2 replicas      (private subnets - IP target mode)
    |
    |---> RDS PostgreSQL    (private subnets - SSL)
    |---> Secrets Manager   (via External Secrets Operator + IRSA)
```

**What's running:**
- EKS 1.33 with AL2023 managed node group
- RDS PostgreSQL 15 (encrypted, private subnet)
- ALB provisioned by AWS Load Balancer Controller
- External Secrets Operator syncing Secrets Manager → K8s secrets
- Fluent Bit DaemonSet shipping logs to CloudWatch
- Bastion host with SSM access, kubectl and psql pre-configured
- HPA for pod autoscaling
- CloudWatch dashboards and alarms

---

## Quick Start

Clone the repo and run the setup script. It handles everything from S3 state bucket creation to the first deployment.

```bash
git clone https://github.com/Kunal2703/8byteOps.git
cd 8byteOps
chmod +x setup.sh
./setup.sh
```

The script will ask for:
- AWS region
- EC2 key pair name
- DB password
- Alert email
- GitHub PAT and AWS credentials (for setting GitHub Actions secrets)

Total time: around 20-30 minutes. EKS takes the longest (~15 min).

**Skip flags for re-runs:**
```bash
SKIP_TERRAFORM=true ./setup.sh   # infra already exists
SKIP_GITHUB=true ./setup.sh      # GitHub secrets already set
```

---

## Repository Structure

```
.
├── setup.sh                      # run this first - sets up everything
├── app/
│   ├── src/
│   │   ├── index.js              # Express entry point
│   │   ├── db.js                 # PostgreSQL connection pool
│   │   ├── logger.js             # JSON structured logging
│   │   ├── routes/               # /health, /ready, /todos, /metrics
│   │   └── middleware/
│   ├── public/index.html         # UI
│   ├── tests/
│   └── Dockerfile
├── terraform/
│   ├── production/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfvars
│   └── modules/
│       ├── vpc/
│       ├── security_groups/
│       ├── eks/
│       ├── ecr/
│       ├── rds/
│       ├── bastion/
│       ├── alb/
│       ├── iam/
│       ├── secrets/
│       └── monitoring/
├── k8s/
│   ├── namespace.yaml
│   ├── serviceaccount.yaml
│   ├── external-secret.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   └── db-migrate-job.yaml
├── scripts/
│   └── bastion-setup.sh          # run on bastion to install tools
└── .github/
    └── workflows/
        ├── deploy-production.yml
        ├── pr-checks.yml
        └── security-scan.yml
```

---

## Manual Infrastructure Setup

If you prefer to run steps manually instead of using `setup.sh`:

**1. Create Terraform state backend**

```bash
# S3 bucket
aws s3api create-bucket --bucket devops-demo-tfstate-<account-id> --region us-east-1
aws s3api put-bucket-versioning --bucket devops-demo-tfstate-<account-id> \
  --versioning-configuration Status=Enabled

# DynamoDB for state locking
aws dynamodb create-table --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1
```

**2. Apply Terraform**

```bash
cd terraform/production
export TF_VAR_db_password='yourpassword'
export TF_VAR_bastion_key_name='devops-demo-key'
export TF_VAR_alert_email='you@example.com'
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

**3. Configure kubectl**

```bash
aws eks update-kubeconfig --name devops-demo-production --region us-east-1
kubectl get nodes
```

**4. Set GitHub Actions secrets**

Go to https://github.com/Kunal2703/8byteOps/settings/secrets/actions and add:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `GH_PAT`

**5. Trigger first deployment**

Push any change to `app/`, `k8s/`, or `terraform/` on the `main` branch, or trigger manually from the Actions tab.

---

## CI/CD

Three workflows in `.github/workflows/`:

**deploy-production.yml** — triggers on push to `main` (when `app/`, `k8s/`, or `terraform/` change)
1. Run tests against a Postgres service container
2. Build and push Docker image to ECR
3. Manual approval gate (GitHub Environment: `production`)
4. Deploy to EKS — applies all k8s manifests, runs DB migration, waits for rollout
5. Auto-rollback if deployment fails

**pr-checks.yml** — triggers on pull requests to `main`
- Tests, lint, npm audit, Docker build, Trivy container scan, Terraform validate
- Posts a summary comment on the PR

**security-scan.yml** — runs every Monday at 06:00 UTC
- Full npm audit, Trivy scan on latest ECR image, tfsec on Terraform

---

## Bastion Access

The bastion has kubectl, helm, psql, git, jq pre-installed and kubeconfig pre-configured.

```bash
# Connect via SSM (no SSH key needed)
aws ssm start-session --target <instance-id> --region us-east-1

# Or SSH
ssh -i devops-demo-key.pem ec2-user@<bastion-ip>
```

Once connected, source your profile and use the shortcuts:

```bash
source ~/.bashrc

kgp          # kubectl get pods -n production
kgn          # kubectl get nodes
klogs        # tail app logs
kroll        # rollout status
dbconnect    # connect to RDS (pulls creds from Secrets Manager)
alburl       # print the ALB endpoint
```

If you provision a new bastion or the tools need reinstalling:

```bash
./scripts/bastion-setup.sh
```

---

## Application Endpoints

| Endpoint | Description |
|---|---|
| `/` | UI dashboard |
| `/health` | Liveness probe |
| `/ready` | Readiness probe (checks DB connection) |
| `/info` | Build metadata |
| `/todos` | REST API — GET, POST, PATCH, DELETE |
| `/metrics` | Prometheus metrics |

---

## Monitoring

**CloudWatch Dashboards:**
- `devops-demo-production-infrastructure` — EKS CPU/memory, RDS metrics, ALB requests
- `devops-demo-production-application` — request rate, latency, pod count

**Alarms (→ SNS → email):**
- EKS node CPU > 80%
- RDS CPU > 75%
- RDS free storage < 5 GB
- RDS connections > 80
- ALB 5xx errors > 10/min
- ALB response time > 2s (p95)

**Logs:**
- `/aws/eks/devops-demo-production/cluster` — control plane logs
- `/app/production` — application logs via Fluent Bit

**CloudWatch Logs Insights query:**
```
fields @timestamp, level, message, requestId, statusCode
| filter level = "ERROR"
| sort @timestamp desc
```

---

## Security

| What | How |
|---|---|
| RDS not public | Private subnets, SG only allows EKS nodes and bastion |
| EKS nodes not public | Private subnets, only ALB is internet-facing |
| Secrets not in code | Secrets Manager → External Secrets Operator → K8s Secret |
| Least-privilege pods | IRSA — each service account has its own scoped IAM role |
| Bastion access | SSM Session Manager (no SSH keys required, fully audited) |
| Container scanning | ECR scan on push, Trivy in CI and weekly scheduled scan |
| Encryption at rest | RDS encrypted (KMS), S3 state bucket AES-256 |
| Non-root containers | App runs as uid 1000 |
| IMDSv2 | Enforced on bastion |

---

## Useful kubectl Commands

```bash
# pods and nodes
kubectl get pods -n production
kubectl get nodes -o wide

# logs
kubectl logs -n production -l app=devops-demo -f
kubectl logs -n production <pod-name> --previous

# scaling
kubectl scale deployment/devops-demo -n production --replicas=4
kubectl get hpa -n production

# rollback
kubectl rollout history deployment/devops-demo -n production
kubectl rollout undo deployment/devops-demo -n production

# ingress and services
kubectl get ingress -n production
kubectl describe ingress devops-demo-ingress -n production
```

---

## Terraform Outputs

```bash
cd terraform/production
terraform output
```

Key outputs: `eks_cluster_name`, `bastion_public_ip`, `ecr_repository_url`, `alb_dns_name`, `rds_endpoint`

---

## Destroy

```bash
cd terraform/production
export TF_VAR_db_password='yourpassword'
export TF_VAR_bastion_key_name='devops-demo-key'
export TF_VAR_alert_email='you@example.com'
terraform destroy
```

If the destroy gets stuck on the ingress or namespace, see CHALLENGES.md for the manual cleanup steps.

Clean up state backend (optional):
```bash
aws s3 rb s3://devops-demo-tfstate-<account-id> --force --region us-east-1
aws dynamodb delete-table --table-name terraform-state-lock --region us-east-1
```

---

## Cost (us-east-1, approximate)

| Resource | Monthly |
|---|---|
| EKS control plane | $73 |
| EKS nodes (2x t3.small) | ~$30 |
| RDS db.t3.micro | ~$15 |
| ALB | ~$18 |
| NAT Gateway | ~$32 |
| CloudWatch | ~$5 |
| **Total** | **~$173** |

Free tier reduces this significantly if the account qualifies.

---

## Author

**Kunal**
Assignment for Octa Byte AI Pvt Ltd
Completed: April 2026
