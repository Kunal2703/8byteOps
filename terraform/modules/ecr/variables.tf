variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. production, staging)"
  type        = string
}

variable "eks_node_role_arn" {
  description = "ARN of the EKS node IAM role that needs pull access to ECR"
  type        = string
}
