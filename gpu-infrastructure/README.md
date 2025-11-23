# GPU Infrastructure

Setting up GPU clusters on Kubernetes is harder than it should be. You need to handle node drivers, device plugins, scheduling, and cost management before you can even run your first GPU workload.

## Examples

| Example | Problem It Solves |
|---------|-------------------|
| [EKS GPU Clusters](./eks-gpu-clusters/) | Terraform module for production-ready GPU clusters on EKS |
| [Node Pools & Scheduling](./node-pools-scheduling/) | Scheduling strategies for mixed GPU workloads |
| [Multi-tenancy](./multi-tenancy/) | Resource quotas, priority classes, and namespace isolation |

## GPU Instance Types

Quick reference for AWS GPU instances commonly used for AI workloads:

| Instance | GPUs | GPU Type | VRAM | Use Case | On-Demand (us-east-1) |
|----------|------|----------|------|----------|----------------------|
| g4dn.xlarge | 1 | T4 | 16GB | Light inference | ~$0.53/hr |
| g4dn.12xlarge | 4 | T4 | 64GB | Batch inference | ~$3.91/hr |
| g5.xlarge | 1 | A10G | 24GB | Medium inference | ~$1.01/hr |
| g5.12xlarge | 4 | A10G | 96GB | Multi-model serving | ~$5.67/hr |
| p3.2xlarge | 1 | V100 | 16GB | Training | ~$3.06/hr |
| p3.8xlarge | 4 | V100 | 64GB | Distributed training | ~$12.24/hr |
| p4d.24xlarge | 8 | A100 | 320GB | Large model training | ~$32.77/hr |
| p5.48xlarge | 8 | H100 | 640GB | Frontier model training | ~$98.32/hr |

## Key Considerations

**Driver management:** NVIDIA drivers need to match your GPU type and CUDA version. The examples use the NVIDIA device plugin DaemonSet which handles this automatically.

**Capacity planning:** GPU instances have limited availability in most regions. Use capacity reservations for critical workloads, and consider multiple availability zones.

**Spot vs On-demand:** GPU spot instances can save 60-70%, but interruption rates vary significantly by instance type and region. The [spot instances guide](../cost-optimisation/spot-instances/) covers this in detail.

**Overprovisioning:** Unlike CPU, GPU memory cannot be overcommitted. If a pod requests 16GB VRAM, that memory is reserved even if unused.
