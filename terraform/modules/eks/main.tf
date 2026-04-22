# ─────────────────────────────────────────────────────────────────────────────
# EKS Cluster (terraform-aws-modules/eks/aws ~> 20.0)
# ─────────────────────────────────────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project_name}-${var.environment}"
  cluster_version = var.eks_cluster_version

  # Networking
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # API server access
  cluster_endpoint_public_access  = true # Allows kubectl from bastion / CI runners
  cluster_endpoint_private_access = true # Allows in-cluster communication

  # Cluster add-ons — use most recent approved versions
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true # Must be ready before nodes join
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = aws_iam_role.ebs_csi_irsa.arn
    }
  }

  # Managed node group
  eks_managed_node_groups = {
    main = {
      instance_types = [var.node_instance_type]
      min_size       = var.node_min
      max_size       = var.node_max
      desired_size   = var.node_desired

      # AL2023 is the required AMI for EKS 1.33+ (AL2 is end-of-life for 1.33)
      ami_type = "AL2023_x86_64_STANDARD"

      # Let the EKS module create the node IAM role — simpler and avoids
      # launch template conflicts. The ECR read policy is attached below.
      iam_role_additional_policies = {
        ecr_read = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }

      # Disable custom launch template so EKS uses the managed default
      use_custom_launch_template = false
      disk_size                  = 50

      labels = {
        environment = var.environment
        role        = "application"
      }

      tags = {
        Environment = var.environment
        Project     = var.project_name
        ManagedBy   = "Terraform"
      }
    }
  }

  # Grant the Terraform caller admin access to the cluster
  enable_cluster_creator_admin_permissions = true

  # Grant GitHub Actions CI user admin access
  access_entries = {
    github_actions = {
      kubernetes_groups = []
      principal_arn     = "arn:aws:iam::283800772211:user/github-actions-ci"

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # Control plane logging
  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# IRSA for EBS CSI Driver
# ─────────────────────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_irsa" {
  name               = "${var.project_name}-${var.environment}-ebs-csi-irsa"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role       = aws_iam_role.ebs_csi_irsa.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ─────────────────────────────────────────────────────────────────────────────
# Helm: AWS Load Balancer Controller
# ─────────────────────────────────────────────────────────────────────────────
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.aws_lb_controller_irsa_role_arn
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "image.repository"
    value = "602401143452.dkr.ecr.${var.aws_region}.amazonaws.com/amazon/aws-load-balancer-controller"
  }

  depends_on = [module.eks]
}

# ─────────────────────────────────────────────────────────────────────────────
# Helm: External Secrets Operator
# ─────────────────────────────────────────────────────────────────────────────
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  version          = "0.9.13"
  create_namespace = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.external_secrets_irsa_role_arn
  }

  set {
    name  = "webhook.port"
    value = "9443"
  }

  depends_on = [module.eks]
}

# ─────────────────────────────────────────────────────────────────────────────
# Helm: Metrics Server
# ─────────────────────────────────────────────────────────────────────────────
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.0"

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [module.eks]
}

# ─────────────────────────────────────────────────────────────────────────────
# Namespace: logging (for Fluent Bit)
# ─────────────────────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "logging" {
  metadata {
    name = "logging"
    labels = {
      environment = var.environment
      project     = var.project_name
    }
  }

  depends_on = [module.eks]
}

# ─────────────────────────────────────────────────────────────────────────────
# Helm: AWS for Fluent Bit (log shipping to CloudWatch)
# ─────────────────────────────────────────────────────────────────────────────
resource "helm_release" "aws_for_fluent_bit" {
  name       = "aws-for-fluent-bit"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-for-fluent-bit"
  namespace  = "logging"
  version    = "0.1.32"

  # DaemonSet — don't wait for all pods to be ready (some nodes may be at capacity)
  wait    = false
  timeout = 300

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "fluent-bit"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.fluent_bit_irsa_role_arn
  }

  set {
    name  = "cloudWatch.enabled"
    value = "true"
  }

  set {
    name  = "cloudWatch.region"
    value = var.aws_region
  }

  set {
    name  = "cloudWatch.logGroupName"
    value = "/app/${var.environment}"
  }

  set {
    name  = "cloudWatch.logStreamPrefix"
    value = "eks-"
  }

  set {
    name  = "firehose.enabled"
    value = "false"
  }

  set {
    name  = "kinesis.enabled"
    value = "false"
  }

  set {
    name  = "elasticsearch.enabled"
    value = "false"
  }

  depends_on = [
    module.eks,
    kubernetes_namespace.logging
  ]
}
