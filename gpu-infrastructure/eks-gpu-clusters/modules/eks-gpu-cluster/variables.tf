variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "create_vpc" {
  description = "Whether to create a new VPC or use existing"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "ID of existing VPC (required if create_vpc is false)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster"
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (if creating new VPC)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "gpu_node_groups" {
  description = "Map of GPU node group configurations"
  type = map(object({
    instance_types         = list(string)
    capacity_type          = optional(string, "ON_DEMAND")
    min_size               = optional(number, 0)
    max_size               = optional(number, 10)
    desired_size           = optional(number, 0)
    disk_size              = optional(number, 100)
    ami_id                 = optional(string, null)
    labels                 = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    additional_iam_policies = optional(list(string), [])
  }))
  default = {}
}

variable "cpu_node_groups" {
  description = "Map of CPU node group configurations for non-GPU workloads"
  type = map(object({
    instance_types = list(string)
    capacity_type  = optional(string, "ON_DEMAND")
    min_size       = optional(number, 1)
    max_size       = optional(number, 10)
    desired_size   = optional(number, 2)
    disk_size      = optional(number, 50)
    labels         = optional(map(string), {})
  }))
  default = {
    system = {
      instance_types = ["m5.large"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      labels = {
        "workload-type" = "system"
      }
    }
  }
}

variable "enable_cluster_autoscaler" {
  description = "Whether to deploy the cluster autoscaler"
  type        = bool
  default     = true
}

variable "enable_nvidia_device_plugin" {
  description = "Whether to deploy the NVIDIA device plugin"
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Enable private API server endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
