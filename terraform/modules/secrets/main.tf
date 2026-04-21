resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/${var.environment}/db-credentials"
  description             = "RDS PostgreSQL connection credentials for ${var.project_name} ${var.environment}"
  recovery_window_in_days = 0   # Allow immediate re-creation on terraform destroy + apply

  tags = {
    Name        = "${var.project_name}/${var.environment}/db-credentials"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = var.db_host
    port     = "5432"
    dbname   = var.db_name
    url      = "postgresql://${var.db_username}:${var.db_password}@${var.db_host}:5432/${var.db_name}"
  })

  # Prevent Terraform from showing the secret value in plan/apply output
  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "${var.project_name}/${var.environment}/app-secrets"
  description             = "Application-level secrets for ${var.project_name} ${var.environment} (JWT keys, API tokens, etc.)"
  recovery_window_in_days = 0   # Allow immediate re-creation on terraform destroy + apply

  tags = {
    Name        = "${var.project_name}/${var.environment}/app-secrets"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id

  # initial placeholder — update via AWS Console or CLI
  secret_string = jsonencode({
    JWT_SECRET = "REPLACE_ME_WITH_A_STRONG_RANDOM_SECRET"
    NODE_ENV   = var.environment
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
