# ─────────────────────────────────────────────────────────────────────────────
# Latest Amazon Linux 2023 AMI
# ─────────────────────────────────────────────────────────────────────────────
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM Role for Bastion
# Grants: SSM Session Manager, EKS access, Secrets Manager read, RDS describe
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "bastion" {
  name = "${var.project_name}-${var.environment}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-bastion-role"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# Full SSM managed instance core — enables Session Manager (no SSH needed),
# Run Command, Patch Manager, and Parameter Store access
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EKS cluster policy — required to call eks:DescribeCluster for kubeconfig
resource "aws_iam_role_policy_attachment" "bastion_eks" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Inline policy — scoped access to EKS API, Secrets Manager, RDS, STS
resource "aws_iam_role_policy" "bastion_access" {
  name = "${var.project_name}-${var.environment}-bastion-access"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:${var.project_name}/${var.environment}/*"
      },
      {
        Sid    = "RDSDescribe"
        Effect = "Allow"
        Action = ["rds:DescribeDBInstances"]
        Resource = "*"
      },
      {
        Sid    = "STSIdentity"
        Effect = "Allow"
        Action = ["sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })
}

# Instance profile — wraps the role so EC2 can assume it
resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project_name}-${var.environment}-bastion-profile"
  role = aws_iam_role.bastion.name

  tags = {
    Name        = "${var.project_name}-${var.environment}-bastion-profile"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS Access Entry — grants the bastion role cluster-admin on EKS
# Without this, kubectl commands fail with "credentials" error even if
# the IAM role has EKS permissions.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_eks_access_entry" "bastion" {
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.bastion.arn
  type          = "STANDARD"

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "aws_eks_access_policy_association" "bastion_admin" {
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.bastion.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.bastion]
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS Cluster SG Rule — allow bastion public subnets to reach EKS private API
# The EKS private endpoint resolves to IPs in private subnets; the bastion
# sits in public subnets and needs inbound 443 allowed on the cluster SG.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group_rule" "eks_api_from_bastion_subnet1" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.public_subnet_cidr_1]
  security_group_id = var.eks_cluster_sg_id
  description       = "Allow bastion public subnet 1 to reach EKS API"
}

resource "aws_security_group_rule" "eks_api_from_bastion_subnet2" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.public_subnet_cidr_2]
  security_group_id = var.eks_cluster_sg_id
  description       = "Allow bastion public subnet 2 to reach EKS API"
}

# ─────────────────────────────────────────────────────────────────────────────
# User-data script
# Installs: kubectl, helm, psql, git, jq
# Configures kubeconfig for both ec2-user and root (root = SSM sessions)
# ─────────────────────────────────────────────────────────────────────────────
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    exec > /var/log/bastion-bootstrap.log 2>&1

    echo "=== Bastion bootstrap started at $(date) ==="

    # ── System update ──────────────────────────────────────────────────────
    dnf update -y

    # ── kubectl ────────────────────────────────────────────────────────────
    KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
    curl -fsSL "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
      -o /usr/local/bin/kubectl
    chmod +x /usr/local/bin/kubectl
    echo "kubectl $${KUBECTL_VERSION} installed"

    # ── Helm ───────────────────────────────────────────────────────────────
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo "helm installed"

    # ── PostgreSQL client ──────────────────────────────────────────────────
    dnf install -y postgresql15
    echo "psql installed"

    # ── Git + jq ───────────────────────────────────────────────────────────
    dnf install -y git jq
    echo "git + jq installed"

    # ── Configure kubeconfig for ec2-user ─────────────────────────────────
    mkdir -p /home/ec2-user/.kube
    aws eks update-kubeconfig \
      --region "${var.aws_region}" \
      --name   "${var.eks_cluster_name}" \
      --kubeconfig /home/ec2-user/.kube/config || true
    chown -R ec2-user:ec2-user /home/ec2-user/.kube
    echo 'export KUBECONFIG=/home/ec2-user/.kube/config' >> /home/ec2-user/.bashrc

    # ── Configure kubeconfig for root (used by SSM Run Command sessions) ───
    mkdir -p /root/.kube
    aws eks update-kubeconfig \
      --region "${var.aws_region}" \
      --name   "${var.eks_cluster_name}" \
      --kubeconfig /root/.kube/config || true
    echo 'export KUBECONFIG=/root/.kube/config' >> /root/.bashrc

    # ── MOTD ───────────────────────────────────────────────────────────────
    cat > /etc/motd << 'MOTD'
╔══════════════════════════════════════════════════════════════════════╗
║                  DevOps Demo — Bastion Host                         ║
╠══════════════════════════════════════════════════════════════════════╣
║  EKS kubectl (already configured):                                  ║
║    kubectl get nodes                                                 ║
║    kubectl get pods -A                                               ║
║                                                                      ║
║  RDS access (creds from Secrets Manager):                           ║
║    SECRET=$(aws secretsmanager get-secret-value \                   ║
║      --secret-id devops-demo/production/db-credentials \            ║
║      --region us-east-1 --query SecretString --output text)         ║
║    PGPASSWORD=$(echo $SECRET | jq -r .password) \                   ║
║      psql -h $(echo $SECRET | jq -r .host) -U dbadmin -d tododb    ║
║                                                                      ║
║  SSM Session (no SSH key needed):                                   ║
║    aws ssm start-session --target <instance-id> --region us-east-1  ║
╚══════════════════════════════════════════════════════════════════════╝
MOTD

    echo "=== Bastion bootstrap complete at $(date) ==="
  EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# Bastion EC2 Instance
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = var.public_subnet_ids[0]
  vpc_security_group_ids      = [var.bastion_sg_id]
  key_name                    = var.key_name
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.bastion.name

  user_data                   = base64encode(local.user_data)
  user_data_replace_on_change = true

  # IMDSv2 only — security best practice
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-bastion"
    Role        = "bastion"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }

  depends_on = [
    aws_iam_instance_profile.bastion,
    aws_iam_role_policy_attachment.bastion_ssm,
    aws_iam_role_policy_attachment.bastion_eks,
    aws_iam_role_policy.bastion_access
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Elastic IP — stable public IP across stop/start cycles
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_eip" "bastion" {
  domain = "vpc"

  tags = {
    Name        = "${var.project_name}-${var.environment}-bastion-eip"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}
