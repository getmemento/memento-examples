# Distributed Training on Kubernetes

## Problem

You need to train a model that either:
- Doesn't fit on a single GPU
- Takes too long on a single GPU
- Requires larger batch sizes than one GPU can handle

Coordinating multiple GPUs across multiple nodes on Kubernetes requires careful setup of networking, storage, and job management.

## Solution

Use PyTorch's native distributed training (DDP/FSDP) with Kubernetes Jobs or the Kubeflow Training Operator for multi-node orchestration.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                            │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Training Job                            │   │
│  │                                                           │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │   │
│  │  │   Worker 0  │  │   Worker 1  │  │   Worker 2  │       │   │
│  │  │   (rank 0)  │  │   (rank 1)  │  │   (rank 2)  │       │   │
│  │  │             │  │             │  │             │       │   │
│  │  │ ┌───┐ ┌───┐ │  │ ┌───┐ ┌───┐ │  │ ┌───┐ ┌───┐ │       │   │
│  │  │ │GPU│ │GPU│ │  │ │GPU│ │GPU│ │  │ │GPU│ │GPU│ │       │   │
│  │  │ │ 0 │ │ 1 │ │  │ │ 0 │ │ 1 │ │  │ │ 0 │ │ 1 │ │       │   │
│  │  │ └───┘ └───┘ │  │ └───┘ └───┘ │  │ └───┘ └───┘ │       │   │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘       │   │
│  │         │                │                │              │   │
│  │         └────────────────┼────────────────┘              │   │
│  │                          │                               │   │
│  │                    NCCL AllReduce                        │   │
│  │                   (gradient sync)                        │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Shared Storage (FSx / EFS / S3)              │   │
│  │         Checkpoints │ Datasets │ Logs                     │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Option 1: Native Kubernetes Job

For simpler setups, use indexed Jobs with a headless service:

```yaml
# See manifests/pytorch-job.yaml
```

This approach:
- Works with vanilla Kubernetes
- Requires manual MASTER_ADDR/MASTER_PORT configuration
- Suitable for single-node multi-GPU or simple multi-node

## Option 2: Kubeflow Training Operator

For production multi-node training:

```yaml
# See manifests/pytorchjob.yaml
```

Benefits:
- Automatic rank assignment
- Built-in failure handling
- Gang scheduling support
- Cleaner abstraction

## PyTorch DDP Setup

### Training Script Requirements

```python
# train.py
import os
import torch
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP

def setup():
    # Environment variables set by Kubernetes/Training Operator
    dist.init_process_group(
        backend="nccl",
        init_method="env://",
        world_size=int(os.environ["WORLD_SIZE"]),
        rank=int(os.environ["RANK"])
    )

def cleanup():
    dist.destroy_process_group()

def train():
    setup()

    local_rank = int(os.environ["LOCAL_RANK"])
    torch.cuda.set_device(local_rank)

    model = YourModel().to(local_rank)
    model = DDP(model, device_ids=[local_rank])

    # Training loop
    for epoch in range(num_epochs):
        for batch in dataloader:
            loss = model(batch)
            loss.backward()
            optimizer.step()

        # Save checkpoint (rank 0 only)
        if dist.get_rank() == 0:
            save_checkpoint(model, optimizer, epoch)

    cleanup()
```

### Environment Variables

The training operator sets these automatically:

| Variable | Description |
|----------|-------------|
| MASTER_ADDR | IP of rank 0 worker |
| MASTER_PORT | Port for rendezvous |
| WORLD_SIZE | Total number of processes |
| RANK | Global rank of this process |
| LOCAL_RANK | Rank within this node |

## PyTorch FSDP Setup

For models that don't fit on one GPU:

```python
from torch.distributed.fsdp import FullyShardedDataParallel as FSDP
from torch.distributed.fsdp import ShardingStrategy

def train_fsdp():
    setup()

    local_rank = int(os.environ["LOCAL_RANK"])
    torch.cuda.set_device(local_rank)

    model = YourLargeModel()

    # Wrap with FSDP
    model = FSDP(
        model,
        sharding_strategy=ShardingStrategy.FULL_SHARD,
        device_id=local_rank,
        # Shard by transformer layers
        auto_wrap_policy=transformer_auto_wrap_policy,
    )

    # Training loop (same as DDP)
    ...
```

## Networking for Multi-Node

### NCCL Configuration

```yaml
env:
  # Use all available NICs
  - name: NCCL_SOCKET_IFNAME
    value: "eth0"
  # Enable debug logging (remove in production)
  - name: NCCL_DEBUG
    value: "INFO"
  # Timeout for operations
  - name: NCCL_TIMEOUT
    value: "1800"
```

### EFA (Elastic Fabric Adapter)

For p4d/p5 instances with EFA:

```yaml
env:
  - name: FI_PROVIDER
    value: "efa"
  - name: FI_EFA_USE_DEVICE_RDMA
    value: "1"
  - name: NCCL_NET
    value: "efa"
resources:
  limits:
    vpc.amazonaws.com/efa: 4  # Number of EFA interfaces
```

## Storage Configuration

### FSx for Lustre (High Performance)

```yaml
volumes:
  - name: fsx
    persistentVolumeClaim:
      claimName: fsx-training-data
containers:
  - volumeMounts:
      - name: fsx
        mountPath: /data
```

### Checkpoints to S3

```python
import boto3
import torch

def save_checkpoint_to_s3(model, optimizer, epoch, bucket, prefix):
    if dist.get_rank() != 0:
        return

    checkpoint = {
        'epoch': epoch,
        'model_state_dict': model.state_dict(),
        'optimizer_state_dict': optimizer.state_dict(),
    }

    # Save locally first
    local_path = f"/tmp/checkpoint_{epoch}.pt"
    torch.save(checkpoint, local_path)

    # Upload to S3
    s3 = boto3.client('s3')
    s3.upload_file(local_path, bucket, f"{prefix}/checkpoint_{epoch}.pt")
```

## Files

```
distributed-training/
├── manifests/
│   ├── pytorch-job.yaml        # Native K8s Job
│   ├── pytorchjob.yaml         # Kubeflow Training Operator
│   ├── headless-service.yaml   # For worker discovery
│   └── storage.yaml            # PVC for checkpoints
├── scripts/
│   ├── train_ddp.py            # DDP training script
│   └── train_fsdp.py           # FSDP training script
└── README.md
```

## Troubleshooting

### NCCL Timeout

```
NCCL error: unhandled system error, NCCL version 2.x.x
```

Causes:
- Network connectivity between nodes
- Firewall blocking NCCL ports
- Mismatched CUDA/NCCL versions

Fix:
- Check security groups allow all traffic within cluster
- Verify nodes can ping each other
- Use `NCCL_DEBUG=INFO` to see connection attempts

### Rank Mismatch

```
RuntimeError: Invalid rank -1, expected 0-N
```

Causes:
- Environment variables not set
- Pods started before service was ready

Fix:
- Use init containers to wait for all workers
- Verify RANK, WORLD_SIZE, LOCAL_RANK are set

### OOM on Backward Pass

Training starts but OOMs during backward:

- Gradients require same memory as forward activations
- Optimizer states (Adam) require 2x model parameters
- Use gradient checkpointing to reduce memory
- Use FSDP to shard optimizer states
