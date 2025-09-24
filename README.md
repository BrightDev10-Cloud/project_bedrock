# InnovateMart: Project Bedrock: EKS App Deployment

## Overview

This guide provides instructions to deploy a sample retail app on the cloud using Amazon EKS and Terraform.
Also due to some system limitations on my loacl machine, i decided to run all the work load on the cloud using a dedicated EC2 instance.

## Live Project External IP:

<a href="http://a8e998edb12ae495dbbbb962fa522039-2063582521.us-east-1.elb.amazonaws.com/">External IP<a/>

```
http://a8e998edb12ae495dbbbb962fa522039-2063582521.us-east-1.elb.amazonaws.com/
```

### Step 1: Launch a Dedicated EC2 Instance

- Choose at least t3.medium (4+ GB RAM) in your preferred AWS region.

- Select Amazon Linux 2 or Ubuntu 22.04 as the AMI.

- Attach an IAM role with privileges for EKS, EC2, S3, IAM, RDS, DynamoDB, ACM, KMS and Route 53.

- Open inbound SSH (port 22) only from your IP in the Security Group.

- Install Required CLI Tools on EC2

- Update system and install AWS CLI, kubectl, eksctl, and Terraform.

```

    # Update & install dependencies
    sudo yum update -y

    # AWS CLI
    sudo yum install -y awscli

    # Terraform
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    sudo yum install terraform -y

    # eksctl (latest)
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin

    # kubectl (matching your intended EKS version, e.g., 1.29)
    curl -o kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.29.0/2024-06-14/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin
```

## Step 2: Organize directories

- Create two directories, bedrock-backend-bootstrap/ (for provisioning the terraform state backend) and bedrock-infra/(for provisioning the actual infra on aws

  ```bash
  mkdir ~/project-bedrock
  cd ~/project-bedrock
  mkdir bedrock-backend-bootstrap bedrock-infra
  ```

## Step 3: Set Up Terraform State Backend

- In /state-backend folder, create `main.tf` Terraform file:

  - Create main.tf file in this directory and paste the code below. Change the S3 bucket name and the (defines S3 bucket and DynamoDB table)
  - ```bash

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
          name           = "bedrock-tfstate-lock"
          billing_mode   = "PAY_PER_REQUEST"
          hash_key       = "LockID"

          attribute {
            name = "LockID"
            type = "S"
          }
        }
    ```

- - Initialize, plan & apply:

    ```bash
      cd ~/project-bedrock/state-backend
      terraform init
      terraform plan
      terraform apply
    ```
- - Take note of the name of the S3 bucket and the name of the dynamodb table name for use in the next steps

## Step 3: Provision AWS Infrastructure with Terraform

- In /bedrock-infra, create these files:
- - Provider.tf (reference the s3 backend and the dynamodb name here so terraform uses the remote backend)
  - ```
      terraform {
        backend "s3" {
          bucket         = "bedrock-tf-state-abdul"
          key            = "bedrock/terraform.tfstate"
          region         = "us-east-1"
          dynamodb_table = "bedrock-tfstate-lock"
          encrypt        = true
        }
      }

      provider "aws" {
        region = var.region
      }
    ```
- - Variables.tf
  - ```
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

    ```
- - main.tf
  - ```
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
    ```
  ```

  ```
- - terraform.tfvars
  - ```
    region           = "us-east-1"
    eks_cluster_name = "bedrock-eks"
    ```
  ```

  ```
- - outputs.tf
  - ```
    output "eks_cluster_name" {
      value = module.eks.cluster_name
    }

    output "eks_admin_instance_profile_name" {
      description = "IAM instance profile for the management EC2"
      value       = aws_iam_instance_profile.eks_admin_instance_profile.name
    }
    ```
  ```

  ```
- - Initialize, plan & apply:
        ``bash
          cd ~/project-bedrock/bedrock-infra
          terraform init
          terraform plan
          terraform apply
    ``

## Step 4. Configure kubectl for EKS Access

- After successful provisioning: type this command in your terminal
- ```bash
      aws eks --region us-east-1 update-kubeconfig --name bedrock-eks
      kubectl get nodes
  ```
  ```
  If you can't list nodes, verify the EC2 instance role as mapped in access_entries and ensure your IAM policies and security groups are correct.
  ```

## Step 5. Deploy the Sample App and In-Cluster Dependencies

- Configure kubectl context for your EKS cluster
- ```
  aws eks --region us-east-1 update-kubeconfig --name bedrock-eks

  ```

- Verify nodes are up
- ```
  kubectl get nodess

  ```

- You will get a response like this if it's successfull
- ```
      NAME                         STATUS   ROLES    AGE   VERSION
      ip-10-0-1-201.ec2.internal   Ready    <none>   19m   v1.29.15-eks-3abbec1
      ip-10-0-3-156.ec2.internal   Ready    <none>   18m   v1.29.15-eks-3abbec1
  ```
- This shows that both Kubernetes worker nodes are in the Ready state and registered with the control plane, and everything is configured as intended

- cd/ into the root directory and clone the provided retail-store-sample-app or any other microservice application of your choice.
- ```bash
  git clone https://github.com/aws-containers/retail-store-sample-app.git
  cd retail-store-sample-app/eks

  # Deploy all manifests (for in-cluster dependencies)
  kubectl apply -f .
  ```

## Step 6: Clone Your Fork Locally

- On your EC2 or local dev workstation: run this command in the project folder to clone the application:
- ```
    git clone https://github.com/BrightDev10-Cloud/retail-store-sample-app.git
    cd retail-store-sample-app
  ```

## Step 7: How to Deploy Now (If the Manifest Isn’t in the Repo):

- Download the Manifest from the Original Repo’s Releases (replace the gitHub url with the correct project)
- ```
  curl -LO https://github.com/aws-containers/retail-store-sample-app/releases/latest/download/kubernetes.yaml
  ```

- This command above saves `kubernetes.yaml` to your current directory.
- Apply Manifest locally
- ```
    kubectl apply -f kubernetes.yaml
    kubectl wait --for=condition=available deployments --all
  ```
- After Succesfully applying the manifest configuration, check if the app has been deployed. Run the command below to expose the external IP:
- ```
    kubectl get svc ui
  ```
- You will find the url for your ui looking like this :
- ```
      http://a8e998edb12ae495dbbbb962fa522039-2063582521.us-east-1.elb.amazonaws.com/
  ```

- (Optional) Add the Manifest to Your Fork Copy the downloaded `kubernetes.yaml` into a suitable directory in your fork (for example, create a deploy/ or manifests/ directory).
- ```
    mkdir deploy
    mv kubernetes.yaml deploy/
  ```
- Commit and push
- ```
      git add deploy/kubernetes.yaml
      git commit -m "Add deployment manifest for EKS"
      git push origin main
  ```

  -Provide your credential when prompted

- Use in GitHub Actions CI/CD (Now you can reference `deploy/kubernetes.yaml` in your CI/CD workflows)
- ```
      - name: Apply manifests to EKS
      run: kubectl apply -f deploy/kubernetes.yaml
  ```

## Step 8: Setup CI/CD on GitHub actions

- on your GitHub account, create a Personal Access token to get AWS_ACCESS_KEY_ID, & AWS_SECRET_ACCESS_KEY

- Go to your app repo on GitHub.

- Go to Settings → Secrets and variables → Actions.

- Add secrets: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY.

- In .github/workflows/deploy-eks.yaml, paste the code below:
- ```
      name: Deploy App to EKS
        on:
          push:
            branches: [main]

      jobs:
        deploy:
          runs-on: ubuntu-latest
          steps:
            - name: Checkout code
              uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Set up kubectl
        uses: azure/setup-kubectl@v3
        with:
          version: "v1.29.0"

      - name: Update kubeconfig for EKS
        run: aws eks --region us-east-1 update-kubeconfig --name bedrock-eks

      - name: Deploy manifests
        run: |
          kubectl apply -f deploy/kubernetes.yaml
          kubectl wait --for=condition=available deployments --all

      - name: Apply manifests to EKS
      run: kubectl apply -f deploy/kubernetes.yaml

  ```

- Commit, push, and verify that deploys run on update.
