variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. production, staging)"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance class (e.g. db.t3.micro)"
  type        = string
}

variable "db_name" {
  description = "Name of the PostgreSQL database to create"
  type        = string
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
}

variable "db_password" {
  description = "Master password for the RDS instance"
  type        = string
  sensitive   = true
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "rds_sg_id" {
  description = "ID of the security group to attach to the RDS instance"
  type        = string
}

variable "aws_region" {
  description = "AWS region where the RDS instance is deployed"
  type        = string
}
