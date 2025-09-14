# --- 1. Provider and Terraform Configuration ---
terraform {
  required_providers {
    aws = {
      source  = "hashorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- 2. Foundational Network (VPC) ---
# Creates a secure network with public and private subnets.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.3"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = true
}

# --- 3. Security Group Rules ---
# These rules allow services inside our VPC to communicate with each other.
resource "aws_security_group_rule" "allow_self_db_access" {
  type                     = "ingress"
  from_port                = 5432 # Port for PostgreSQL
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.vpc.default_security_group_id
  source_security_group_id = module.vpc.default_security_group_id
}

resource "aws_security_group_rule" "allow_self_https_access" {
  type                     = "ingress"
  from_port                = 443 # Port for HTTPS (for ECR Endpoints)
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = module.vpc.default_security_group_id
  source_security_group_id = module.vpc.default_security_group_id
}


# --- 4. VPC Endpoints for Private Connectivity ---
# Required to allow the ECS task in a private subnet to pull images from ECR.
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [module.vpc.default_security_group_id]
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [module.vpc.default_security_group_id]
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
}

# --- 5. Container Registry (ECR) ---
# Creates a private repository to store your Strapi Docker image.
resource "aws_ecr_repository" "app" {
  name = "${var.project_name}-repo"
}

# --- 6. Database (RDS PostgreSQL) ---
# Creates a managed PostgreSQL database in the private subnets.
resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "aws_db_subnet_group" "default" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_db_instance" "strapi_db" {
  identifier           = "${var.project_name}-db"
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "16.3"
  instance_class       = "db.t3.micro"
  db_name              = "${replace(var.project_name, "-", "")}db"
  username             = replace(var.project_name, "-", "")
  password             = random_password.db_password.result
  vpc_security_group_ids = [module.vpc.default_security_group_id]
  db_subnet_group_name = aws_db_subnet_group.default.name
  skip_final_snapshot  = true
  publicly_accessible  = false
}

# --- 7. Container Orchestration (ECS) ---
# Defines the cluster and the blueprint (Task Definition) for our Strapi container.
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"  # 0.25 vCPU
  memory                   = "512"  # 0.5 GB
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name  = "${var.project_name}-container"
    image = "${aws_ecr_repository.app.repository_url}:latest"
    portMappings = [{
      containerPort = 1337
    }]
    environment = [
      { name = "NODE_ENV", value = "production" },
      { name = "DATABASE_CLIENT", value = "postgres" },
      { name = "DATABASE_HOST", value = aws_db_instance.strapi_db.address },
      { name = "DATABASE_PORT", value = tostring(aws_db_instance.strapi_db.port) },
      { name = "DATABASE_NAME", value = aws_db_instance.strapi_db.db_name },
      { name = "DATABASE_USERNAME", value = aws_db_instance.strapi_db.username },
      { name = "DATABASE_PASSWORD", value = aws_db_instance.strapi_db.password },
      { name = "JWT_SECRET", value = random_password.db_password.result },
      { name = "ADMIN_JWT_SECRET", value = random_password.db_password.result }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.project_name}"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# --- 8. Permissions (IAM) ---
# Creates a role that allows ECS to pull images and write logs.
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-ecs-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- 9. Networking (Load Balancer) ---
# Creates a public-facing load balancer to distribute traffic to the container.
resource "aws_lb" "main" {
  name               = "${var.project_name}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.vpc.default_security_group_id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = 1337
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"
  health_check {
    path = "/" # Corrected health check path
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# --- 10. Service Deployment (ECS Service) ---
# Launches and maintains our Strapi container on AWS Fargate.
resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [module.vpc.default_security_group_id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "${var.project_name}-container"
    container_port   = 1337
  }

  # This dependency ensures the endpoints are created before the service tries to start a task.
  depends_on = [
    aws_vpc_endpoint.ecr_api,
    aws_vpc_endpoint.ecr_dkr,
    aws_vpc_endpoint.s3
  ]
}

# Create a log group for the ECS container
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name = "/ecs/${var.project_name}"
}