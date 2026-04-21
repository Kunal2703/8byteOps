output "bastion_public_ip" {
  description = "Elastic IP address of the bastion host"
  value       = aws_eip.bastion.public_ip
}

output "bastion_public_dns" {
  description = "Public DNS name of the bastion host"
  value       = aws_instance.bastion.public_dns
}

output "bastion_instance_id" {
  description = "EC2 instance ID of the bastion host"
  value       = aws_instance.bastion.id
}

output "bastion_eip" {
  description = "Elastic IP allocation ID"
  value       = aws_eip.bastion.id
}

output "bastion_role_arn" {
  description = "ARN of the IAM role attached to the bastion instance"
  value       = aws_iam_role.bastion.arn
}

output "bastion_ssm_connect_cmd" {
  description = "AWS CLI command to connect via SSM Session Manager (no SSH key needed)"
  value       = "aws ssm start-session --target ${aws_instance.bastion.id} --region ${var.aws_region}"
}
