output "db_endpoint" {
  description = "Connection endpoint for the RDS instance (hostname only, no port)"
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "Port number the RDS instance listens on"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Name of the PostgreSQL database"
  value       = aws_db_instance.main.db_name
}

output "db_instance_id" {
  description = "Identifier of the RDS instance (used for CloudWatch metrics)"
  value       = aws_db_instance.main.identifier
}

output "db_arn" {
  description = "ARN of the RDS instance"
  value       = aws_db_instance.main.arn
}
