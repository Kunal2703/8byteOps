output "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "ARN of the EKS worker node IAM role"
  value       = aws_iam_role.eks_node.arn
}

output "app_irsa_role_arn" {
  description = "ARN of the IRSA role for the application service account"
  value       = aws_iam_role.app_irsa.arn
}

output "external_secrets_irsa_role_arn" {
  description = "ARN of the IRSA role for the External Secrets Operator"
  value       = aws_iam_role.external_secrets_irsa.arn
}

output "aws_lb_controller_irsa_role_arn" {
  description = "ARN of the IRSA role for the AWS Load Balancer Controller"
  value       = aws_iam_role.aws_lb_controller_irsa.arn
}

output "fluent_bit_irsa_role_arn" {
  description = "ARN of the IRSA role for Fluent Bit log shipping"
  value       = aws_iam_role.fluent_bit_irsa.arn
}
