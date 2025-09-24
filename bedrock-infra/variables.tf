variable "region" {
  default = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "eks_cluster_name" {
  default = "bedrock-eks"
}

variable "db_username" {
  description = "Username for the RDS DB"
  default     = "adminuser"
}

variable "db_password" {
  description = "Password for the RDS DB"
  sensitive   = true
}

variable "admin_instance_profile" {
  description = "Name of the IAM instance profile for EKS admin instance"
  default     = "bedrock-eks-admin-instance-profile"
}

variable "dev_user_name" {
  description = "Name of the developer IAM user"
  default     = "innovatemart-dev"
}

