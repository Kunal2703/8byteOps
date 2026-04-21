variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. production, staging)"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster (used in CloudWatch metric dimensions)"
  type        = string
}

variable "rds_instance_id" {
  description = "Identifier of the RDS instance (used in CloudWatch metric dimensions)"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB (the part after 'loadbalancer/'). Leave empty until the ALB is created by the LB controller."
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Email address to receive CloudWatch alarm notifications via SNS"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used in dashboard widget configurations)"
  type        = string
}
