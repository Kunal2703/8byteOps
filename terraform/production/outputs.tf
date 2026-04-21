output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint URL of the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority" {
  description = "Base64-encoded certificate authority data for the EKS cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = module.ecr.repository_url
}

output "rds_endpoint" {
  description = "Connection endpoint for the RDS instance"
  value       = module.rds.db_endpoint
}

output "rds_port" {
  description = "Port number for the RDS instance"
  value       = module.rds.db_port
}

output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = module.bastion.bastion_public_ip
}

output "bastion_public_dns" {
  description = "Public DNS name of the bastion host"
  value       = module.bastion.bastion_public_dns
}

output "bastion_instance_id" {
  description = "EC2 instance ID of the bastion host"
  value       = module.bastion.bastion_instance_id
}

output "bastion_role_arn" {
  description = "IAM role ARN attached to the bastion"
  value       = module.bastion.bastion_role_arn
}

output "bastion_ssm_connect" {
  description = "SSM Session Manager connect command (no SSH key needed)"
  value       = module.bastion.bastion_ssm_connect_cmd
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "alb_app_url" {
  description = "Full HTTP URL of the application via ALB"
  value       = "http://${module.alb.alb_dns_name}"
}

output "app_namespace" {
  description = "Kubernetes namespace where the app is deployed"
  value       = module.alb.app_namespace
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for the application"
  value       = module.monitoring.log_group_app
}
