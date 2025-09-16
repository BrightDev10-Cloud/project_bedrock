terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.58.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" 
}

# A new S3 bucket resource without the 'versioning' argument
resource "aws_s3_bucket" "tf_state" {
  bucket = "tf-state-bedrock"
}

# The new resource for S3 bucket versioning
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}



resource "aws_dynamodb_table" "tf_lock" {
  name           = "your-tf-state-lock-table"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}




