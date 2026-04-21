aws_region   = "us-east-1"
project_name = "devops-demo"
environment  = "production"

# Networking
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
availability_zones   = ["us-east-1a", "us-east-1b"]

# EKS
eks_cluster_version    = "1.33"
eks_node_instance_type = "t3.small"
eks_node_desired       = 2
eks_node_min           = 1
eks_node_max           = 4

# RDS
db_instance_class = "db.t3.micro"
db_name           = "tododb"
db_username       = "dbadmin"

# Bastion
bastion_instance_type = "t3.micro"
bastion_key_name      = "devops-demo-key"

# Application
app_image_tag = "latest"

# Alerting
alert_email = "devops@example.com"
