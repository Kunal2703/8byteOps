variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. production, staging)"
  type        = string
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "db_host" {
  description = "RDS instance endpoint (hostname)"
  type        = string
}

variable "db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
}
