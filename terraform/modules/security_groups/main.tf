# ─────────────────────────────────────────────────────────────────────────────
# ALB Security Group
# Allows inbound HTTP/HTTPS from the internet; all outbound traffic permitted.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Security group for the Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb-sg"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS Worker Nodes Security Group
# Allows all intra-VPC traffic and NodePort range from the ALB.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-${var.environment}-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow all traffic within the VPC CIDR"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr_block]
  }

  ingress {
    description     = "Allow NodePort traffic from ALB"
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-nodes-sg"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Bastion Host Security Group
# NOTE: Allowing SSH from 0.0.0.0/0 is intentional for this demo assignment.
# In a real production environment, restrict this to your corporate IP range
# or use AWS Systems Manager Session Manager instead of SSH.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-${var.environment}-bastion-sg"
  description = "Security group for the bastion host. RESTRICT SSH CIDR IN PRODUCTION."
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH access - restrict to known IPs in production"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-bastion-sg"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# RDS Security Group
# Accepts PostgreSQL connections from EKS nodes, EKS cluster primary SG,
# and the bastion host.
# Note: EKS managed node groups attach the cluster primary SG (not eks_nodes),
# so both must be allowed for pod → RDS connectivity.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Security group for the RDS PostgreSQL instance"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS worker nodes SG"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  ingress {
    description     = "PostgreSQL from EKS cluster primary SG (used by managed node groups)"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_cluster_primary_sg_id]
  }

  ingress {
    description     = "PostgreSQL from bastion host for admin access"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS Control Plane Security Group
# Allows the API server to receive HTTPS from worker nodes.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "eks_control_plane" {
  name        = "${var.project_name}-${var.environment}-eks-control-plane-sg"
  description = "Security group for the EKS control plane"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS from EKS worker nodes to API server"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-control-plane-sg"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS Cluster Primary SG — allow ALB to reach pods on app port 3000
# EKS managed node groups use the cluster primary SG (not eks_nodes_sg).
# The ALB uses target-type=ip so it hits pod IPs directly on port 3000.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group_rule" "eks_cluster_sg_from_alb" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = var.eks_cluster_primary_sg_id
  description              = "Allow ALB to reach app pods on port 3000"
}
