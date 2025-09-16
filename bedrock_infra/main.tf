# VPC using official module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.0"
  name    = "bedrock-vpc"
  cidr    = var.vpc_cidr

  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

# EKS using official module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.1.5"
  name    = var.eks_cluster_name
  kubernetes_version = "1.29" # Specify preferred version

  endpoint_public_access = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      instance_types = ["t2.micro"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
    }
  }

  # EKS Access Entry for the developer user (Replaces aws-auth configmap)
  access_entries = {
    developer = {
      kubernetes_groups = ["view-only-group"]
      principal_arn     = aws_iam_user.developer.arn
    }
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

# Developer Access (Requirement 3.3)

resource "aws_iam_user" "developer" {
  name = "eks-developer"
  tags = {
    Name = "EKS Read-Only Developer"
  }
}

# In a real scenario, you would provide credentials securely.
# For this project, we will output them.
resource "aws_iam_access_key" "developer" {
  user = aws_iam_user.developer.name
}


# Persistence Layer (Bonus Objective 4.1)


# Subnet group for all RDS instances
resource "aws_db_subnet_group" "main" {
  name       = "bedrock-rds-subnet-group"
  subnet_ids = module.vpc.private_subnets
  tags = {
    Name = "Bedrock RDS Subnet Group"
  }
}

# RDS for MySQL (for catalog service)
resource "aws_db_instance" "mysql" {
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "bedrock_catalog"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [module.vpc.default_security_group_id]
  skip_final_snapshot    = true
}

# RDS for PostgreSQL (for orders service)
resource "aws_db_instance" "postgres" {
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  db_name                = "bedrock_orders"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [module.vpc.default_security_group_id]
  skip_final_snapshot    = true
}

# DynamoDB table for carts service
resource "aws_dynamodb_table" "carts" {
  name         = "bedrock-carts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "cart_id"

  attribute {
    name = "cart_id"
    type = "S"
  }

  tags = {
    Name        = "bedrock-carts"
    Environment = "dev"
  }
}

