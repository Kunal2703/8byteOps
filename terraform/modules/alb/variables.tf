variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "app_namespace" {
  description = "Kubernetes namespace where the app and Ingress will be created"
  type        = string
  default     = "production"
}

variable "app_port" {
  description = "Container port the app listens on"
  type        = number
  default     = 3000
}

variable "public_subnet_ids" {
  description = "Public subnet IDs where the ALB will be placed"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group ID for the ALB (allows 80/443 from internet)"
  type        = string
}

variable "lb_controller_depends_on" {
  description = "Dependency handle — pass the helm_release output of the LB controller to ensure it is ready before the Ingress is created"
  type        = any
  default     = null
}
