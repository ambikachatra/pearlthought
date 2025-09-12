# variables.tf

# -- AWS Provider Variables --
variable "aws_region" {
  description = "The AWS region where all resources will be created."
  type        = string
  default     = "us-east-1"
}

# -- Project-wide Variables --
variable "project_name" {
  description = "A name for the project to prefix all resources."
  type        = string
  default     = "strapi-app"
}

# -- VPC Configuration Variables --
variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "A list of Availability Zones to use for the subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnets" {
  description = "A list of CIDR blocks for the public subnets."
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "private_subnets" {
  description = "A list of CIDR blocks for the private subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}