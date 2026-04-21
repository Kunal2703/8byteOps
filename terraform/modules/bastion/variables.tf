variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. production)"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs; the bastion is placed in the first one"
  type        = list(string)
}

variable "bastion_sg_id" {
  description = "ID of the security group to attach to the bastion instance"
  type        = string
}

variable "key_name" {
  description = "Name of the EC2 key pair for SSH access to the bastion"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster (used in kubeconfig setup and EKS access entry)"
  type        = string
}

variable "eks_cluster_sg_id" {
  description = "ID of the EKS cluster primary security group (to allow bastion → API server)"
  type        = string
}

variable "public_subnet_cidr_1" {
  description = "CIDR of the first public subnet (bastion subnet) — allowed to reach EKS API"
  type        = string
}

variable "public_subnet_cidr_2" {
  description = "CIDR of the second public subnet — allowed to reach EKS API"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used in kubeconfig setup)"
  type        = string
}

variable "bastion_instance_type" {
  description = "EC2 instance type for the bastion host"
  type        = string
  default     = "t3.micro"
}
