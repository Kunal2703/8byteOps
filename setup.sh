#!/bin/bash
# Full infrastructure setup - run once from repo root.
# Needs: aws cli v2, terraform >= 1.5, git, jq, curl
# gh cli is optional (used to set GitHub Actions secrets automatically)
#
# SKIP_TERRAFORM=true ./setup.sh  - skip infra if already exists
# SKIP_GITHUB=true ./setup.sh     - skip GitHub secrets step

set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$REPO_ROOT/terraform/production"
SKIP_TERRAFORM="${SKIP_TERRAFORM:-false}"
SKIP_GITHUB="${SKIP_GITHUB:-false}"

echo "8byteOps infrastructure setup"
echo "Takes around 20-30 min, EKS alone is ~15 min"
echo ""
read -p "Press enter to continue or Ctrl+C to stop... "
echo ""

# check tools
echo "Checking tools..."
for tool in aws terraform git jq curl; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "$tool is not installed, please install it first"
    exit 1
  fi
done

TF_VER=$(terraform version -json | jq -r '.terraform_version')
TF_MAJOR=$(echo "$TF_VER" | cut -d. -f1)
TF_MINOR=$(echo "$TF_VER" | cut -d. -f2)
if [ "$TF_MAJOR" -lt 1 ] || { [ "$TF_MAJOR" -eq 1 ] && [ "$TF_MINOR" -lt 5 ]; }; then
  echo "Need terraform >= 1.5.0, found $TF_VER"
  exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
  echo "AWS credentials not working, run 'aws configure' first"
  exit 1
}
echo "AWS account: $AWS_ACCOUNT_ID ($(aws sts get-caller-identity --query Arn --output text))"

GH_AVAILABLE=false
if command -v gh > /dev/null 2>&1; then
  GH_AVAILABLE=true
  echo "GitHub CLI found"
else
  echo "GitHub CLI not found - you'll need to set GitHub secrets manually"
fi
echo ""

# collect inputs
echo "Enter configuration values (nothing is applied yet):"
echo ""

read -p "AWS region [us-east-1]: " INPUT_REGION
AWS_REGION="${INPUT_REGION:-us-east-1}"

read -p "EC2 key pair name [devops-demo-key]: " INPUT_KEY
KEY_NAME="${INPUT_KEY:-devops-demo-key}"
KEY_FILE="$REPO_ROOT/${KEY_NAME}.pem"

while true; do
  read -s -p "DB password (min 12 chars, no spaces or quotes): " DB_PASSWORD
  echo ""
  if [ ${#DB_PASSWORD} -lt 12 ]; then
    echo "Too short, try again"
    continue
  fi
  case "$DB_PASSWORD" in
    *\'* | *\"* | *\ *) echo "No spaces or quotes allowed"; continue ;;
  esac
  read -s -p "Confirm DB password: " DB_PASSWORD2
  echo ""
  if [ "$DB_PASSWORD" = "$DB_PASSWORD2" ]; then
    break
  fi
  echo "Passwords don't match, try again"
done

read -p "Alert email for CloudWatch alarms: " ALERT_EMAIL
if [ -z "$ALERT_EMAIL" ]; then
  echo "Alert email is required"
  exit 1
fi

GH_PAT=""
GH_AWS_KEY_ID=""
GH_AWS_SECRET=""

if [ "$GH_AVAILABLE" = "true" ] && [ "$SKIP_GITHUB" = "false" ]; then
  echo ""
  echo "GitHub Actions secrets needed: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, GH_PAT"
  read -s -p "GitHub Personal Access Token (repo + secrets scope): " GH_PAT
  echo ""
  if [ -z "$GH_PAT" ]; then
    echo "No PAT entered, will skip GitHub secrets"
    SKIP_GITHUB=true
  else
    read -p "AWS Access Key ID (github-actions-ci user): " GH_AWS_KEY_ID
    read -s -p "AWS Secret Access Key: " GH_AWS_SECRET
    echo ""
  fi
fi

echo ""
echo "Starting setup..."
echo ""

# EC2 key pair
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" > /dev/null 2>&1; then
  echo "Key pair $KEY_NAME already exists"
  if [ ! -f "$KEY_FILE" ]; then
    echo "Warning: .pem file not found at $KEY_FILE, you'll need it for SSH"
  fi
else
  echo "Creating key pair $KEY_NAME..."
  aws ec2 create-key-pair \
    --key-name "$KEY_NAME" \
    --region "$AWS_REGION" \
    --query 'KeyMaterial' \
    --output text > "$KEY_FILE"
  chmod 400 "$KEY_FILE"
  echo "Key pair created, saved to $KEY_FILE"
  echo "Keep this file safe - you can't get it back from AWS"
fi
echo ""

if [ "$SKIP_TERRAFORM" = "true" ]; then
  echo "Skipping Terraform (SKIP_TERRAFORM=true)"
else
  # S3 bucket for terraform state
  TFSTATE_BUCKET="devops-demo-tfstate-${AWS_ACCOUNT_ID}"
  TFSTATE_TABLE="terraform-state-lock"

  if aws s3api head-bucket --bucket "$TFSTATE_BUCKET" --region "$AWS_REGION" 2>/dev/null; then
    echo "S3 bucket $TFSTATE_BUCKET already exists"
  else
    echo "Creating S3 bucket $TFSTATE_BUCKET..."
    if [ "$AWS_REGION" = "us-east-1" ]; then
      aws s3api create-bucket --bucket "$TFSTATE_BUCKET" --region "$AWS_REGION" > /dev/null
    else
      aws s3api create-bucket --bucket "$TFSTATE_BUCKET" --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION" > /dev/null
    fi
    aws s3api put-bucket-versioning --bucket "$TFSTATE_BUCKET" \
      --versioning-configuration Status=Enabled
    aws s3api put-bucket-encryption --bucket "$TFSTATE_BUCKET" \
      --server-side-encryption-configuration \
      '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
    aws s3api put-public-access-block --bucket "$TFSTATE_BUCKET" \
      --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    echo "S3 bucket created"
  fi

  if aws dynamodb describe-table --table-name "$TFSTATE_TABLE" --region "$AWS_REGION" \
       --query "Table.TableStatus" --output text 2>/dev/null | grep -q "ACTIVE"; then
    echo "DynamoDB table $TFSTATE_TABLE already exists"
  else
    echo "Creating DynamoDB table $TFSTATE_TABLE..."
    aws dynamodb create-table \
      --table-name "$TFSTATE_TABLE" \
      --attribute-definitions AttributeName=LockID,AttributeType=S \
      --key-schema AttributeName=LockID,KeyType=HASH \
      --billing-mode PAY_PER_REQUEST \
      --region "$AWS_REGION" > /dev/null
    aws dynamodb wait table-exists --table-name "$TFSTATE_TABLE" --region "$AWS_REGION"
    echo "DynamoDB table created"
  fi

  CURRENT_BUCKET=$(grep 'bucket' "$TF_DIR/main.tf" | head -1 | awk -F'"' '{print $2}')
  if [ "$CURRENT_BUCKET" != "$TFSTATE_BUCKET" ]; then
    sed -i.bak "s|bucket.*=.*\"devops-demo-tfstate-.*\"|bucket         = \"${TFSTATE_BUCKET}\"|" "$TF_DIR/main.tf"
    rm -f "$TF_DIR/main.tf.bak"
    echo "Updated backend bucket in main.tf to $TFSTATE_BUCKET"
  fi

  echo ""
  echo "Running terraform init..."
  cd "$TF_DIR"
  terraform init -upgrade -reconfigure \
    -backend-config="bucket=${TFSTATE_BUCKET}" \
    -backend-config="key=production/terraform.tfstate" \
    -backend-config="region=${AWS_REGION}" \
    -backend-config="dynamodb_table=${TFSTATE_TABLE}" \
    -backend-config="encrypt=true"

  export TF_VAR_db_password="$DB_PASSWORD"
  export TF_VAR_bastion_key_name="$KEY_NAME"
  export TF_VAR_alert_email="$ALERT_EMAIL"
  export TF_VAR_aws_region="$AWS_REGION"

  echo "Running terraform plan..."
  terraform plan -out=tfplan

  echo ""
  echo "This will create AWS resources and cost money."
  read -p "Type 'yes' to apply: " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled"
    exit 0
  fi

  echo "Applying... this takes around 15-20 minutes"
  terraform apply tfplan

  TF_OUT=$(terraform output -json)
  EKS_CLUSTER=$(echo "$TF_OUT" | jq -r '.eks_cluster_name.value // "devops-demo-production"')
  BASTION_IP=$(echo "$TF_OUT" | jq -r '.bastion_public_ip.value // ""')
  ECR_URI=$(echo "$TF_OUT" | jq -r '.ecr_repository_url.value // ""')
  ALB_URL=$(echo "$TF_OUT" | jq -r '.alb_dns_name.value // ""')

  cd "$REPO_ROOT"
fi

echo ""

# configure kubectl
EKS_CLUSTER="${EKS_CLUSTER:-devops-demo-production}"
echo "Configuring kubectl for $EKS_CLUSTER..."
aws eks update-kubeconfig --name "$EKS_CLUSTER" --region "$AWS_REGION"

echo "Waiting for nodes..."
i=0
while true; do
  i=$((i+1))
  READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || true)
  if [ "$READY" -ge 1 ]; then
    echo "$READY node(s) ready"
    break
  fi
  if [ "$i" -ge 30 ]; then
    echo "Nodes not ready after 5 minutes, check EKS console"
    exit 1
  fi
  echo "Waiting... ($i/30)"
  sleep 10
done

# add IAM users to aws-auth
BASTION_ROLE="arn:aws:iam::${AWS_ACCOUNT_ID}:role/devops-demo-production-bastion-role"
kubectl patch configmap aws-auth -n kube-system --patch "
data:
  mapRoles: |
    $(kubectl get configmap aws-auth -n kube-system -o jsonpath='{.data.mapRoles}' | grep -v bastion || true)
    - rolearn: ${BASTION_ROLE}
      username: bastion
      groups:
      - system:masters
  mapUsers: |
    - userarn: arn:aws:iam::${AWS_ACCOUNT_ID}:user/kunal
      username: kunal
      groups:
      - system:masters
    - userarn: arn:aws:iam::${AWS_ACCOUNT_ID}:user/github-actions-ci
      username: github-actions-ci
      groups:
      - system:masters
" 2>/dev/null || echo "aws-auth patch skipped (may already be configured)"

echo ""

# GitHub secrets
if [ "$SKIP_GITHUB" = "true" ]; then
  echo "Skipping GitHub secrets - set these manually:"
  echo "  https://github.com/Kunal2703/8byteOps/settings/secrets/actions"
  echo "  AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, GH_PAT"
else
  echo "$GH_PAT" | gh auth login --with-token
  gh secret set AWS_ACCESS_KEY_ID     --body "$GH_AWS_KEY_ID" --repo "Kunal2703/8byteOps"
  gh secret set AWS_SECRET_ACCESS_KEY --body "$GH_AWS_SECRET" --repo "Kunal2703/8byteOps"
  gh secret set GH_PAT                --body "$GH_PAT"        --repo "Kunal2703/8byteOps"
  echo "GitHub secrets set"
fi

echo ""

# trigger first deploy
if [ "$SKIP_GITHUB" = "false" ] && [ "$GH_AVAILABLE" = "true" ]; then
  gh workflow run deploy-production.yml --repo "Kunal2703/8byteOps" --ref main 2>/dev/null \
    && echo "Deploy workflow triggered" \
    || echo "Could not trigger workflow - do it manually from the Actions tab"
else
  echo "Trigger deployment manually:"
  echo "  https://github.com/Kunal2703/8byteOps/actions/workflows/deploy-production.yml"
fi

echo ""

# wait for app
if [ -z "${ALB_URL:-}" ]; then
  i=0
  while true; do
    i=$((i+1))
    ALB_URL=$(kubectl get ingress devops-demo-ingress -n production \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    [ -n "$ALB_URL" ] && break
    [ "$i" -ge 20 ] && break
    echo "Waiting for ALB... ($i/20)"
    sleep 15
  done
fi

if [ -n "${ALB_URL:-}" ]; then
  HTTP_STATUS="000"
  for i in $(seq 1 20); do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${ALB_URL}/health" 2>/dev/null || echo "000")
    [ "$HTTP_STATUS" = "200" ] && break
    echo "HTTP $HTTP_STATUS, waiting... ($i/20)"
    sleep 15
  done
  if [ "$HTTP_STATUS" = "200" ]; then
    echo "App is up: http://$ALB_URL"
  else
    echo "App not responding yet - check GitHub Actions for deployment status"
  fi
fi

echo ""
echo "Done."
echo ""
echo "Account:  $AWS_ACCOUNT_ID"
echo "Region:   $AWS_REGION"
echo "Cluster:  ${EKS_CLUSTER:-devops-demo-production}"
[ -n "${BASTION_IP:-}" ] && echo "Bastion:  $BASTION_IP"
[ -n "${ALB_URL:-}" ]    && echo "App URL:  http://$ALB_URL"
echo ""
echo "Connect to bastion:"
echo "  aws ssm start-session --target <instance-id> --region $AWS_REGION"
[ -n "${BASTION_IP:-}" ] && [ -f "${KEY_FILE:-}" ] && \
  echo "  ssh -i $KEY_FILE ec2-user@$BASTION_IP"
echo ""
echo "Actions: https://github.com/Kunal2703/8byteOps/actions"
[ -f "${KEY_FILE:-}" ] && echo "Key file: $KEY_FILE  (keep this safe)"
echo ""
