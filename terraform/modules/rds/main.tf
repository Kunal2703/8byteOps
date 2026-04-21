resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  description = "Subnet group for ${var.project_name} ${var.environment} RDS instance"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name        = "${var.project_name}-${var.environment}-db-subnet-group"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "aws_db_parameter_group" "postgres15" {
  name        = "${var.project_name}-${var.environment}-postgres15"
  family      = "postgres15"
  description = "Custom parameter group for ${var.project_name} ${var.environment} PostgreSQL 15"

  # log slow queries (>1s) and connections
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-postgres15"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-postgres"

  # Engine
  engine         = "postgres"
  engine_version = "15.17"

  # Sizing
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  # Credentials
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false
  multi_az = false

  parameter_group_name = aws_db_parameter_group.postgres15.name

  # free tier only allows 0; set to 7+ for paid accounts
  backup_retention_period = 0
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Snapshots
  skip_final_snapshot = true

  deletion_protection = false

  # CloudWatch log exports
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Performance Insights (free tier: 7 days retention)
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  tags = {
    Name        = "${var.project_name}-${var.environment}-postgres"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}
