terraform {
        backend "s3" {
          bucket         = "tf-state-bedrock"
          key            = "bedrock/terraform.tfstate"
          region         = "us-east-1"
          dynamodb_table = "bedrock-tfstate-lock"
          encrypt        = true
        }
      }
      
provider "aws" {
  region = var.region
}

