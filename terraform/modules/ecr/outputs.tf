output "repository_url" {
  description = "URL of the ECR repository (used as the Docker image base URL)"
  value       = aws_ecr_repository.app.repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.app.arn
}

output "repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.app.name
}
