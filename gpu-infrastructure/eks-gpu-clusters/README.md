# EKS GPU Clusters

## Problem

Setting up an EKS cluster with GPU nodes involves more than just adding a node group with GPU instances. You need:

- NVIDIA device plugin DaemonSet for GPU discovery
- Correct AMI with pre-installed drivers
- Node labels and taints for GPU scheduling
- Cluster autoscaler configuration that understands GPU nodes
- Proper IAM roles for node groups
- Security groups that allow pod networking

Getting any of these wrong means your GPU pods either won't schedule, won't see GPUs, or will have networking issues.

## Solution

A Terraform module that provisions a production-ready EKS cluster with GPU node pools, including all the necessary components. The module handles:

- EKS cluster with managed node groups for GPU instances
- NVIDIA device plugin deployment
- Cluster autoscaler with GPU-aware configuration
- Node labels, taints, and tolerations
- VPC and networking setup (or use existing VPC)
- IAM roles with least-privilege permissions

## Usage

```hcl
module "gpu_cluster" {
  source = "./modules/eks-gpu-cluster"

  cluster_name    = "ai-workloads-prod"
  cluster_version = "1.29"

  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  gpu_node_groups = {
    inference = {
      instance_types = ["g5.xlarge", "g5.2xlarge"]
      capacity_type  = "SPOT"
      min_size       = 0
      max_size       = 10
      desired_size   = 2
      labels = {
        "workload-type" = "inference"
      }
      taints = [{
        key    = "nvidia.com/gpu"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }

    training = {
      instance_types = ["p3.8xlarge"]
      capacity_type  = "ON_DEMAND"
      min_size       = 0
      max_size       = 4
      desired_size   = 0
      labels = {
        "workload-type" = "training"
      }
      taints = [{
        key    = "nvidia.com/gpu"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }
  }

  tags = {
    Environment = "production"
    Team        = "ml-platform"
  }
}
```

## Files

```
eks-gpu-clusters/
├── modules/
│   └── eks-gpu-cluster/
│       ├── main.tf           # EKS cluster and node groups
│       ├── variables.tf      # Input variables
│       ├── outputs.tf        # Cluster outputs
│       ├── iam.tf            # IAM roles and policies
│       ├── nvidia.tf         # NVIDIA device plugin
│       └── autoscaler.tf     # Cluster autoscaler
├── examples/
│   ├── basic/                # Minimal GPU cluster
│   └── production/           # Full production setup
└── README.md
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5
- kubectl for cluster access after provisioning

## Deployment

```bash
cd examples/production
terraform init
terraform plan
terraform apply
```

After deployment, configure kubectl:

```bash
aws eks update-kubeconfig --name ai-workloads-prod --region us-east-1
```

Verify GPU nodes are ready:

```bash
kubectl get nodes -l nvidia.com/gpu=true
kubectl describe nodes | grep -A5 "Allocatable:" | grep nvidia
```

## Architecture

The module creates:

1. **EKS Control Plane** with private API endpoint
2. **Managed Node Groups** for each GPU configuration
3. **NVIDIA Device Plugin** as a DaemonSet on GPU nodes
4. **Cluster Autoscaler** configured for GPU-aware scaling
5. **IAM Roles** for nodes, autoscaler, and add-ons

```
┌─────────────────────────────────────────────────────────────┐
│                         VPC                                  │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │  Private Subnet │  │  Private Subnet │                   │
│  │     (AZ-a)      │  │     (AZ-b)      │                   │
│  │                 │  │                 │                   │
│  │ ┌─────────────┐ │  │ ┌─────────────┐ │                   │
│  │ │ GPU Node    │ │  │ │ GPU Node    │ │                   │
│  │ │ g5.xlarge   │ │  │ │ g5.xlarge   │ │                   │
│  │ └─────────────┘ │  │ └─────────────┘ │                   │
│  │                 │  │                 │                   │
│  └─────────────────┘  └─────────────────┘                   │
│                                                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                  EKS Control Plane                     │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │  │
│  │  │ API Server  │  │    etcd     │  │ Controllers │    │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘    │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Node Group Configuration

### Instance Selection

Choose instance types based on your workload:

| Workload | Recommended Instances | Reason |
|----------|----------------------|--------|
| Light inference | g5.xlarge, g4dn.xlarge | Cost-effective single GPU |
| Heavy inference | g5.12xlarge | High VRAM, good for large models |
| Fine-tuning | p3.2xlarge, p3.8xlarge | V100s balance cost and capability |
| Pre-training | p4d.24xlarge, p5.48xlarge | Maximum throughput |

### Spot vs On-Demand

The module supports mixed capacity types:

```hcl
gpu_node_groups = {
  inference_spot = {
    instance_types = ["g5.xlarge", "g5.2xlarge"]
    capacity_type  = "SPOT"
  }
  inference_ondemand = {
    instance_types = ["g5.xlarge"]
    capacity_type  = "ON_DEMAND"
  }
}
```

Use spot for:
- Stateless inference with graceful shutdown handling
- Training with checkpointing
- Development and testing

Use on-demand for:
- Latency-sensitive inference
- Jobs that cannot tolerate interruption
- When spot capacity is unavailable

## Customisation

### Existing VPC

To use an existing VPC:

```hcl
module "gpu_cluster" {
  source = "./modules/eks-gpu-cluster"

  create_vpc = false
  vpc_id     = "vpc-existing123"
  subnet_ids = ["subnet-a", "subnet-b"]

  # ... rest of configuration
}
```

### Custom AMI

For specific driver versions or custom configurations:

```hcl
gpu_node_groups = {
  custom = {
    ami_id = "ami-custom123"
    # ...
  }
}
```

### Additional IAM Policies

```hcl
gpu_node_groups = {
  inference = {
    additional_iam_policies = [
      "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    ]
  }
}
```

## Troubleshooting

### GPUs Not Visible

Check the NVIDIA device plugin is running:

```bash
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
```

Check device plugin logs:

```bash
kubectl logs -n kube-system -l name=nvidia-device-plugin-ds
```

### Nodes Not Scaling

Check cluster autoscaler logs:

```bash
kubectl logs -n kube-system -l app=cluster-autoscaler
```

Common issues:
- ASG limits too low
- Instance type unavailable in region
- IAM permissions missing

### Pods Not Scheduling to GPU Nodes

Ensure pods have the correct toleration:

```yaml
tolerations:
- key: nvidia.com/gpu
  operator: Exists
  effect: NoSchedule
```

And request GPU resources:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
```
