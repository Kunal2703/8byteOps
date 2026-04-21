#!/bin/bash
# Run this on the bastion to install tools and configure EKS/RDS access.
# Safe to re-run.

set -e

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-devops-demo-production}"

echo "Bastion setup - region: $AWS_REGION, cluster: $CLUSTER_NAME"
echo ""

echo "Updating system..."
sudo dnf update -y -q

if command -v kubectl > /dev/null 2>&1; then
  echo "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
  echo "Installing kubectl..."
  KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  sudo curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    -o /usr/local/bin/kubectl
  sudo chmod +x /usr/local/bin/kubectl
  echo "kubectl $KUBECTL_VERSION installed"
fi

if command -v helm > /dev/null 2>&1; then
  echo "helm already installed: $(helm version --short)"
else
  echo "Installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

if command -v psql > /dev/null 2>&1; then
  echo "psql already installed"
else
  echo "Installing psql..."
  sudo dnf install -y postgresql15 -q
fi

sudo dnf install -y git jq unzip -q

if aws --version 2>&1 | grep -q "aws-cli/2"; then
  echo "AWS CLI v2 already installed"
else
  echo "Installing AWS CLI v2..."
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install --update
  rm -rf /tmp/awscliv2.zip /tmp/aws
fi

echo ""
echo "AWS identity:"
aws sts get-caller-identity --region "$AWS_REGION"

echo ""
echo "Configuring kubectl..."
mkdir -p /home/ec2-user/.kube /root/.kube

aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --kubeconfig /home/ec2-user/.kube/config
chown -R ec2-user:ec2-user /home/ec2-user/.kube

aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --kubeconfig /root/.kube/config

grep -q "KUBECONFIG" /home/ec2-user/.bashrc 2>/dev/null || \
  echo 'export KUBECONFIG=/home/ec2-user/.kube/config' >> /home/ec2-user/.bashrc

grep -q "KUBECONFIG" /root/.bashrc 2>/dev/null || \
  echo 'export KUBECONFIG=/root/.kube/config' >> /root/.bashrc

export KUBECONFIG=/root/.kube/config

echo ""
echo "Cluster access check:"
kubectl cluster-info
kubectl get nodes -o wide

echo ""
REPO_DIR="/home/ec2-user/devops-demo"
if [ -d "$REPO_DIR/.git" ]; then
  echo "Pulling latest repo..."
  git -C "$REPO_DIR" pull
else
  echo "Repo not found at $REPO_DIR"
  echo "Clone it: git clone https://github.com/Kunal2703/8byteOps.git $REPO_DIR"
fi

if ! grep -q "DevOps Demo aliases" /home/ec2-user/.bashrc 2>/dev/null; then
  cat >> /home/ec2-user/.bashrc << 'EOF'

# DevOps Demo aliases
export KUBECONFIG=/home/ec2-user/.kube/config
export AWS_REGION=us-east-1
export CLUSTER_NAME=devops-demo-production

alias k='kubectl'
alias kgp='kubectl get pods -n production'
alias kgs='kubectl get svc -n production'
alias kgi='kubectl get ingress -n production'
alias kgn='kubectl get nodes -o wide'
alias klogs='kubectl logs -n production -l app=devops-demo --tail=100 -f'
alias kdesc='kubectl describe -n production'
alias kroll='kubectl rollout status deployment/devops-demo -n production'

dbconnect() {
  SECRET=$(aws secretsmanager get-secret-value \
    --secret-id devops-demo/production/db-credentials \
    --region us-east-1 --query SecretString --output text)
  PGPASSWORD=$(echo "$SECRET" | jq -r .password) \
    psql -h "$(echo "$SECRET" | jq -r .host)" \
         -U "$(echo "$SECRET" | jq -r .username)" \
         -d "$(echo "$SECRET" | jq -r .dbname)"
}

alburl() {
  kubectl get ingress devops-demo-ingress -n production \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null
  echo ""
}

echo "aliases loaded - kgp, kgn, klogs, dbconnect, alburl"
EOF
fi

chown ec2-user:ec2-user /home/ec2-user/.bashrc

sudo tee /etc/motd > /dev/null << 'EOF'
DevOps Demo - Bastion Host

kubectl: kgp, kgn, klogs, kroll, kdesc
database: dbconnect (pulls creds from Secrets Manager)
alb url: alburl

deployments via GitHub Actions:
https://github.com/Kunal2703/8byteOps/actions
EOF

echo ""
echo "Setup complete."
echo "Run: source ~/.bashrc"
echo ""
