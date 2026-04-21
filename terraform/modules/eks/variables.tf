variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. production, staging)"
  type        = string
}

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
}

variable "node_desired" {
  description = "Desired number of worker nodes"
  type        = number
}

variable "node_min" {
  description = "Minimum number of worker nodes"
  type        = number
}

variable "node_max" {
  description = "Maximum number of worker nodes"
  type        = number
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS nodes"
  type        = list(string)
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "eks_nodes_sg_id" {
  description = "ID of the security group for EKS worker nodes"
  type        = string
}

variable "eks_cluster_role_arn" {
  description = "ARN of the IAM role for the EKS cluster control plane"
  type        = string
}

variable "eks_node_role_arn" {
  description = "ARN of the IAM role for EKS worker nodes"
  type        = string
}

variable "aws_lb_controller_irsa_role_arn" {
  description = "ARN of the IRSA role for the AWS Load Balancer Controller"
  type        = string
}

variable "external_secrets_irsa_role_arn" {
  description = "ARN of the IRSA role for the External Secrets Operator"
  type        = string
}

variable "fluent_bit_irsa_role_arn" {
  description = "ARN of the IRSA role for Fluent Bit"
  type        = string
}

variable "aws_region" {
  description = "AWS region where the cluster is deployed"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}
