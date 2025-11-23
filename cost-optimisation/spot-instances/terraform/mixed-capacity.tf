# Mixed On-Demand and Spot Configuration
#
# Baseline on-demand capacity with spot for burst.

variable "cluster_name" {
  type = string
}

variable "node_role_arn" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

# On-demand baseline - always available
resource "aws_eks_node_group" "gpu_ondemand" {
  cluster_name    = var.cluster_name
  node_group_name = "gpu-ondemand"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids

  capacity_type  = "ON_DEMAND"
  instance_types = ["g5.xlarge"]
  ami_type       = "AL2_x86_64_GPU"
  disk_size      = 100

  scaling_config {
    min_size     = 2   # Always-on baseline
    max_size     = 5
    desired_size = 2
  }

  labels = {
    "nvidia.com/gpu"   = "true"
    "capacity-type"    = "on-demand"
    "workload-type"    = "inference"
  }

  taint {
    key    = "nvidia.com/gpu"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = {
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# Spot burst capacity
resource "aws_eks_node_group" "gpu_spot" {
  cluster_name    = var.cluster_name
  node_group_name = "gpu-spot-burst"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids

  capacity_type = "SPOT"
  instance_types = [
    "g5.xlarge",
    "g5.2xlarge",
    "g4dn.xlarge",
    "g4dn.2xlarge"
  ]
  ami_type  = "AL2_x86_64_GPU"
  disk_size = 100

  scaling_config {
    min_size     = 0   # Scale to zero when not needed
    max_size     = 20
    desired_size = 0
  }

  labels = {
    "nvidia.com/gpu"   = "true"
    "capacity-type"    = "spot"
    "workload-type"    = "inference"
  }

  taint {
    key    = "capacity-type"
    value  = "spot"
    effect = "NO_SCHEDULE"
  }

  taint {
    key    = "nvidia.com/gpu"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = {
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
