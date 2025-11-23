# Spot Node Group for GPU Workloads
#
# Creates a managed node group using spot instances.
# Multiple instance types improve availability.

variable "cluster_name" {
  type = string
}

variable "node_role_arn" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

resource "aws_eks_node_group" "gpu_spot" {
  cluster_name    = var.cluster_name
  node_group_name = "gpu-spot"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids

  # Spot capacity
  capacity_type = "SPOT"

  # Multiple instance types for better availability
  instance_types = [
    "g5.xlarge",
    "g5.2xlarge",
    "g4dn.xlarge",
    "g4dn.2xlarge"
  ]

  ami_type   = "AL2_x86_64_GPU"
  disk_size  = 100

  scaling_config {
    min_size     = 0
    max_size     = 20
    desired_size = 2
  }

  # Labels for scheduling
  labels = {
    "nvidia.com/gpu"   = "true"
    "capacity-type"    = "spot"
    "workload-type"    = "inference"
  }

  # Taint to ensure only spot-tolerant workloads schedule here
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

  # Tags for cluster autoscaler
  tags = {
    "k8s.io/cluster-autoscaler/enabled"                = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}"    = "owned"
    "k8s.io/cluster-autoscaler/node-template/label/capacity-type" = "spot"
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

output "node_group_name" {
  value = aws_eks_node_group.gpu_spot.node_group_name
}

output "node_group_status" {
  value = aws_eks_node_group.gpu_spot.status
}
