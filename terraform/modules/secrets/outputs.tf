output "db_secret_arn" {
  description = "ARN of the database credentials secret"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_secret_name" {
  description = "Name of the database credentials secret"
  value       = aws_secretsmanager_secret.db_credentials.name
}

output "app_secret_arn" {
  description = "ARN of the application-level secrets"
  value       = aws_secretsmanager_secret.app_secrets.arn
}
