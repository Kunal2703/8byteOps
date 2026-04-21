output "sns_topic_arn" {
  description = "ARN of the SNS topic used for CloudWatch alarm notifications"
  value       = aws_sns_topic.alerts.arn
}

output "infrastructure_dashboard_name" {
  description = "Name of the infrastructure CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.infrastructure.dashboard_name
}

output "application_dashboard_name" {
  description = "Name of the application CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.application.dashboard_name
}

output "log_group_app" {
  description = "Name of the application CloudWatch log group"
  value       = aws_cloudwatch_log_group.app.name
}
