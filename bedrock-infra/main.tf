# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name                 = "bedrock-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets       = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets      = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
  enable_nat_gateway   = false
  single_nat_gateway   = false
  map_public_ip_on_launch = true
}

# EKS
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.eks_cluster_name
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  cluster_endpoint_private_access = true

  cluster_security_group_additional_rules = {
    allow_api_from_vpc = {
      description = "Allow K8s API access from within the VPC"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  access_entries = {
    admin_instance_role = {
      principal_arn = aws_iam_role.eks_admin_instance_role.arn
      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    },
    local_admin_user = {
      principal_arn = "arn:aws:iam::221693237976:user/terraform-infra-user"
      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      min_size       = 1
      desired_size   = 2
      max_size       = 3
    }
  }
}

# IAM Role and Instance Profile (for management EC2)
resource "aws_iam_role" "eks_admin_instance_role" {
  name = "bedrock-eks-admin-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_admin_instance_admin_policy" {
  role       = aws_iam_role.eks_admin_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "eks_admin_instance_profile" {
  name = var.admin_instance_profile
  role = aws_iam_role.eks_admin_instance_role.name
}

# Read-Only Dev IAM User & Policy
resource "aws_iam_user" "dev" {
  name = var.dev_user_name
}

resource "aws_iam_policy" "eks_read_only_custom" {
  name        = "bedrock-eks-read-only-custom"
  description = "Custom policy for EKS read-only access"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "eks:Describe*",
        "eks:List*",
        "logs:FilterLogEvents"
      ],
      Resource = "*"
    }]
  })
}

resource "aws_iam_user_policy_attachment" "dev-readonly" {
  user       = aws_iam_user.dev.name
  policy_arn = aws_iam_policy.eks_read_only_custom.arn
}
