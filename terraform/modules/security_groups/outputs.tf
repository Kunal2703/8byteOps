output "alb_sg_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "eks_nodes_sg_id" {
  description = "ID of the EKS worker nodes security group"
  value       = aws_security_group.eks_nodes.id
}

output "bastion_sg_id" {
  description = "ID of the bastion host security group"
  value       = aws_security_group.bastion.id
}

output "rds_sg_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "eks_control_plane_sg_id" {
  description = "ID of the EKS control plane security group"
  value       = aws_security_group.eks_control_plane.id
}
