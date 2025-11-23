# Memento AI Infrastructure Examples

Production-ready patterns for running AI workloads at scale. No toy demos, no theoretical architectures. Every example here solves a real problem.

## Philosophy

Most AI infrastructure advice is either too basic ("here's how to deploy a Docker container") or too abstract ("design for scale from day one"). Neither helps when you're trying to figure out why your inference costs are 3x what they should be, or why your training jobs keep getting preempted.

These examples sit in the middle ground: practical patterns that work in production, with enough context to understand why they work and when to use them.

## What's Here

| Category | What It Covers |
|----------|----------------|
| [GPU Infrastructure](./gpu-infrastructure/) | EKS clusters with GPU node pools, scheduling strategies, multi-tenancy |
| [Model Serving](./model-serving/) | vLLM, TGI, Ray Serve deployments with autoscaling and optimisation |
| [Vector Databases](./vector-databases/) | Qdrant, Weaviate, Milvus on Kubernetes with production configurations |
| [Training Infrastructure](./training-infrastructure/) | Distributed training, spot orchestration, checkpointing |
| [Cost Optimisation](./cost-optimisation/) | GPU scheduling, spot instances, request batching |
| [Observability](./observability/) | GPU metrics, inference monitoring, cost attribution |

## Quick Start

Each example has its own README explaining the problem, solution, and usage. Pick what's relevant:

**Running inference at scale?** Start with [vLLM deployment](./model-serving/vllm-deployment/) and [GPU scheduling](./cost-optimisation/gpu-scheduling/).

**Setting up GPU clusters?** Start with [EKS GPU clusters](./gpu-infrastructure/eks-gpu-clusters/) and [node pool scheduling](./gpu-infrastructure/node-pools-scheduling/).

**Burning money on GPUs?** Start with [cost optimisation patterns](./cost-optimisation/) and [spot instances](./cost-optimisation/spot-instances/).

**Need RAG infrastructure?** Start with [Qdrant on K8s](./vector-databases/qdrant-on-k8s/).

## Prerequisites

Most examples assume:

- AWS account with appropriate permissions
- Terraform >= 1.5
- kubectl and helm configured
- Basic familiarity with Kubernetes

Specific requirements are listed in each example's README.

## Technical Stack

- **Cloud:** AWS (primary), with notes for GCP/Azure where relevant
- **Kubernetes:** EKS, vanilla Kubernetes patterns
- **IaC:** Terraform for infrastructure, Helm/Kustomize for K8s
- **Monitoring:** Prometheus, Grafana, DCGM for GPU metrics
- **Model Serving:** vLLM, TGI, Ray Serve
- **Training:** PyTorch, distributed training patterns
- **Vector DBs:** Qdrant, Weaviate, Milvus

## Contributing

Found a bug? Have a pattern that's saved you time? PRs welcome. Keep it practical, keep it production-ready.

## Licence

MIT. Use it, adapt it, ship it.
