terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket         = "devops-demo-tfstate-283800772211"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    }
  }
}

# Retrieve current AWS account ID and caller identity
data "aws_caller_identity" "current" {}

# ─────────────────────────────────────────────
# VPC
# ─────────────────────────────────────────────
module "vpc" {
  source = "../modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

# ─────────────────────────────────────────────
# Security Groups
# ─────────────────────────────────────────────
module "security_groups" {
  source = "../modules/security_groups"

  project_name              = var.project_name
  environment               = var.environment
  vpc_id                    = module.vpc.vpc_id
  vpc_cidr_block            = module.vpc.vpc_cidr_block
  # EKS cluster primary SG is created by the EKS module.
  # Managed node groups attach this SG (not eks_nodes_sg), so it must be
  # allowed to reach RDS on 5432 and be reachable from the ALB on 3000.
  eks_cluster_primary_sg_id = module.eks.cluster_primary_sg_id
}

# ─────────────────────────────────────────────
# IAM roles (created before EKS so we can pass
# the node role ARN to ECR)
# ─────────────────────────────────────────────
module "iam" {
  source = "../modules/iam"

  project_name   = var.project_name
  environment    = var.environment
  aws_account_id = data.aws_caller_identity.current.account_id
  # OIDC values are populated after EKS cluster creation.
  # On first apply these will be empty strings; a second apply
  # (or targeted apply of the EKS module first) will wire them up.
  eks_cluster_oidc_provider_arn = module.eks.oidc_provider_arn
  eks_cluster_oidc_provider_url = module.eks.cluster_oidc_issuer_url
}

# ─────────────────────────────────────────────
# ECR
# ─────────────────────────────────────────────
module "ecr" {
  source = "../modules/ecr"

  project_name      = var.project_name
  environment       = var.environment
  eks_node_role_arn = module.iam.eks_node_role_arn
}

# ─────────────────────────────────────────────
# EKS Cluster
# ─────────────────────────────────────────────
module "eks" {
  source = "../modules/eks"

  project_name                    = var.project_name
  environment                     = var.environment
  eks_cluster_version             = var.eks_cluster_version
  node_instance_type              = var.eks_node_instance_type
  node_desired                    = var.eks_node_desired
  node_min                        = var.eks_node_min
  node_max                        = var.eks_node_max
  private_subnet_ids              = module.vpc.private_subnet_ids
  vpc_id                          = module.vpc.vpc_id
  eks_nodes_sg_id                 = module.security_groups.eks_nodes_sg_id
  eks_cluster_role_arn            = module.iam.eks_cluster_role_arn
  eks_node_role_arn               = module.iam.eks_node_role_arn
  aws_lb_controller_irsa_role_arn = module.iam.aws_lb_controller_irsa_role_arn
  external_secrets_irsa_role_arn  = module.iam.external_secrets_irsa_role_arn
  fluent_bit_irsa_role_arn        = module.iam.fluent_bit_irsa_role_arn
  aws_region                      = var.aws_region
  aws_account_id                  = data.aws_caller_identity.current.account_id
}

# ─────────────────────────────────────────────
# RDS PostgreSQL
# ─────────────────────────────────────────────
module "rds" {
  source = "../modules/rds"

  project_name       = var.project_name
  environment        = var.environment
  db_instance_class  = var.db_instance_class
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  private_subnet_ids = module.vpc.private_subnet_ids
  rds_sg_id          = module.security_groups.rds_sg_id
  aws_region         = var.aws_region
}

# ─────────────────────────────────────────────
# Secrets Manager
# ─────────────────────────────────────────────
module "secrets" {
  source = "../modules/secrets"

  project_name = var.project_name
  environment  = var.environment
  db_username  = var.db_username
  db_password  = var.db_password
  db_host      = module.rds.db_endpoint
  db_name      = var.db_name
}

# ─────────────────────────────────────────────
# Bastion Host
# ─────────────────────────────────────────────
module "bastion" {
  source = "../modules/bastion"

  project_name         = var.project_name
  environment          = var.environment
  public_subnet_ids    = module.vpc.public_subnet_ids
  bastion_sg_id        = module.security_groups.bastion_sg_id
  key_name             = var.bastion_key_name
  eks_cluster_name     = module.eks.cluster_name
  eks_cluster_sg_id    = module.eks.cluster_primary_sg_id
  public_subnet_cidr_1 = var.public_subnet_cidrs[0]
  public_subnet_cidr_2 = var.public_subnet_cidrs[1]
  aws_region           = var.aws_region
  bastion_instance_type = var.bastion_instance_type
}

# ─────────────────────────────────────────────
# ALB — Application Load Balancer
# Provisioned via Kubernetes Ingress + AWS LB Controller
# ─────────────────────────────────────────────
module "alb" {
  source = "../modules/alb"

  project_name      = var.project_name
  environment       = var.environment
  app_namespace     = var.environment
  app_port          = 3000
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security_groups.alb_sg_id

  # Ensures the LB controller Helm chart is deployed before the Ingress is created
  lb_controller_depends_on = module.eks
}

# ─────────────────────────────────────────────
# CloudWatch Monitoring
# ─────────────────────────────────────────────
module "monitoring" {
  source = "../modules/monitoring"

  project_name     = var.project_name
  environment      = var.environment
  eks_cluster_name = module.eks.cluster_name
  rds_instance_id  = module.rds.db_instance_id
  # alb_arn_suffix is populated after the ALB is provisioned by the LB controller.
  # On first apply it will be empty — alarms use treat_missing_data=notBreaching so no false alerts.
  # Run `terraform refresh` after first apply to populate the real ARN suffix.
  alb_arn_suffix   = module.alb.alb_arn_suffix
  alert_email      = var.alert_email
  aws_region       = var.aws_region
}

# ─────────────────────────────────────────────
# Kubernetes & Helm providers (depend on EKS)
# ─────────────────────────────────────────────
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "/usr/local/bin/aws"
      args = [
        "eks", "get-token",
        "--cluster-name", module.eks.cluster_name,
        "--region", var.aws_region
      ]
    }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "/usr/local/bin/aws"
      args = [
        "eks", "get-token",
        "--cluster-name", module.eks.cluster_name,
        "--region", var.aws_region
      ]
    }
  }
}

# ─────────────────────────────────────────────
# db_password variable (sensitive, not in
# variables.tf to keep it out of tfvars)
# ─────────────────────────────────────────────
variable "db_password" {
  description = "Master password for the RDS instance. Supply via TF_VAR_db_password env var or -var flag."
  type        = string
  sensitive   = true
}
