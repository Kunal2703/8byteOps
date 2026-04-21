output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "List of IDs of the public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "List of IDs of the private subnets"
  value       = module.vpc.private_subnets
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "nat_gateway_ip" {
  description = "Public IP address of the NAT gateway"
  value       = module.vpc.nat_public_ips[0]
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway attached to the VPC"
  value       = module.vpc.igw_id
}
