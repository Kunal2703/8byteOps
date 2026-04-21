variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. production, staging)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC in which to create the security groups"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC, used for intra-VPC ingress rules"
  type        = string
}

variable "eks_cluster_primary_sg_id" {
  description = "ID of the EKS cluster primary security group (attached to managed node groups)"
  type        = string
}