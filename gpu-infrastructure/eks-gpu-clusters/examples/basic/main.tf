# Basic GPU Cluster Example
#
# Minimal configuration for a GPU-enabled EKS cluster.
# Use this as a starting point and customise as needed.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

module "gpu_cluster" {
  source = "../../modules/eks-gpu-cluster"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  # Create a new VPC (default behaviour)
  create_vpc           = true
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["${var.region}a", "${var.region}b"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24"]

  # Single GPU node group for inference
  gpu_node_groups = {
    inference = {
      instance_types = ["g5.xlarge"]
      capacity_type  = "ON_DEMAND"
      min_size       = 0
      max_size       = 3
      desired_size   = 1

      labels = {
        "workload-type" = "inference"
      }

      taints = [{
        key    = "nvidia.com/gpu"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }
  }

  tags = {
    Environment = "development"
    Project     = var.cluster_name
  }
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "gpu-cluster-basic"
}

output "cluster_endpoint" {
  value = module.gpu_cluster.cluster_endpoint
}

output "kubeconfig_command" {
  value = module.gpu_cluster.kubeconfig_command
}
