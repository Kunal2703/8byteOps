variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. production, staging)"
  type        = string
}

variable "eks_cluster_oidc_provider_arn" {
  description = "ARN of the EKS cluster OIDC provider (used in IRSA trust policies)"
  type        = string
}

variable "eks_cluster_oidc_provider_url" {
  description = "URL of the EKS cluster OIDC provider (https://... format)"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID, used to scope IAM policy resource ARNs"
  type        = string
}
