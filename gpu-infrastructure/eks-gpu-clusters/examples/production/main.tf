# Production GPU Cluster Example
#
# Full production setup with multiple node groups, spot instances,
# and high availability configuration.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Uncomment for remote state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "gpu-cluster/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.region
}

module "gpu_cluster" {
  source = "../../modules/eks-gpu-cluster"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  # VPC Configuration - 3 AZs for high availability
  create_vpc           = true
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # Security - restrict public access to known IPs
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.allowed_cidrs

  # GPU Node Groups - separate pools for different workloads
  gpu_node_groups = {
    # Inference on spot - cost effective for stateless workloads
    inference_spot = {
      instance_types = ["g5.xlarge", "g5.2xlarge"]
      capacity_type  = "SPOT"
      min_size       = 0
      max_size       = 20
      desired_size   = 2
      disk_size      = 100

      labels = {
        "workload-type" = "inference"
        "capacity-type" = "spot"
      }

      taints = [{
        key    = "nvidia.com/gpu"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]

      additional_iam_policies = [
        "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
      ]
    }

    # Inference on-demand - for latency-sensitive or critical workloads
    inference_ondemand = {
      instance_types = ["g5.xlarge"]
      capacity_type  = "ON_DEMAND"
      min_size       = 1
      max_size       = 10
      desired_size   = 2
      disk_size      = 100

      labels = {
        "workload-type" = "inference"
        "capacity-type" = "on-demand"
      }

      taints = [{
        key    = "nvidia.com/gpu"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }

    # Training - larger instances with more VRAM
    training = {
      instance_types = ["p3.8xlarge", "p3.16xlarge"]
      capacity_type  = "ON_DEMAND"
      min_size       = 0
      max_size       = 8
      desired_size   = 0
      disk_size      = 500

      labels = {
        "workload-type" = "training"
      }

      taints = [
        {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        },
        {
          key    = "workload-type"
          value  = "training"
          effect = "NO_SCHEDULE"
        }
      ]

      additional_iam_policies = [
        "arn:aws:iam::aws:policy/AmazonS3FullAccess"
      ]
    }

    # Fine-tuning - medium instances, can use spot with checkpointing
    finetuning_spot = {
      instance_types = ["p3.2xlarge", "g5.4xlarge"]
      capacity_type  = "SPOT"
      min_size       = 0
      max_size       = 10
      desired_size   = 0
      disk_size      = 200

      labels = {
        "workload-type" = "finetuning"
        "capacity-type" = "spot"
      }

      taints = [
        {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        },
        {
          key    = "workload-type"
          value  = "finetuning"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  }

  # CPU Node Groups
  cpu_node_groups = {
    system = {
      instance_types = ["m5.large", "m5.xlarge"]
      capacity_type  = "ON_DEMAND"
      min_size       = 2
      max_size       = 6
      desired_size   = 3
      disk_size      = 50

      labels = {
        "workload-type" = "system"
      }
    }

    workers = {
      instance_types = ["m5.2xlarge", "m5.4xlarge"]
      capacity_type  = "SPOT"
      min_size       = 0
      max_size       = 20
      desired_size   = 2
      disk_size      = 100

      labels = {
        "workload-type" = "worker"
      }
    }
  }

  enable_cluster_autoscaler    = true
  enable_nvidia_device_plugin  = true

  tags = {
    Environment = var.environment
    Project     = var.cluster_name
    Team        = "ml-platform"
    CostCenter  = "ai-infrastructure"
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "ai-workloads-prod"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to access the cluster API"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.gpu_cluster.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.gpu_cluster.cluster_name
}

output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = module.gpu_cluster.kubeconfig_command
}

output "gpu_node_groups" {
  description = "GPU node group details"
  value       = module.gpu_cluster.gpu_node_groups
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.gpu_cluster.oidc_provider_arn
}
