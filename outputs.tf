# outputs.tf

# -- VPC Outputs --
output "vpc_id" {
  description = "The ID of the created VPC."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "A list of IDs for the public subnets."
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "A list of IDs for the private subnets."
  value       = module.vpc.private_subnets
}

# -- Application Outputs --
output "strapi_url" {
  description = "The URL of the Strapi application."
  value       = "http://${aws_lb.main.dns_name}" # Assumes your LB is named 'aws_lb.main'
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository to push the Docker image to."
  value       = aws_ecr_repository.app.repository_url
}