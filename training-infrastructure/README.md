# Training Infrastructure

Training at scale is fundamentally different from inference. You're dealing with:

- Multi-node coordination (distributed training)
- Long-running jobs (hours to weeks)
- Checkpoint management (terabytes of state)
- Spot interruption recovery
- Expensive failures (a crash at hour 47 of a 48-hour job)

## Examples

| Example | What It Covers |
|---------|----------------|
| [Distributed Training](./distributed-training/) | PyTorch DDP/FSDP on Kubernetes |
| [Spot Orchestration](./spot-orchestration/) | Checkpointing and recovery for spot instances |
| [Training Pipelines](./training-pipelines/) | End-to-end training workflow automation |

## Training vs Inference

| Aspect | Inference | Training |
|--------|-----------|----------|
| Duration | Seconds | Hours to weeks |
| State | Stateless | Checkpoints (GB-TB) |
| Failure cost | Retry request | Lost GPU hours |
| Scaling | Horizontal (replicas) | Vertical (more GPUs) |
| Spot tolerance | High | Medium (with checkpointing) |

## Distributed Training Strategies

### Data Parallel (DDP)

Each GPU gets a copy of the model, different data batches. Gradients are synchronised.

```
┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐
│ GPU 0   │  │ GPU 1   │  │ GPU 2   │  │ GPU 3   │
│ Model   │  │ Model   │  │ Model   │  │ Model   │
│ Batch 0 │  │ Batch 1 │  │ Batch 2 │  │ Batch 3 │
└────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘
     │            │            │            │
     └────────────┴─────┬──────┴────────────┘
                        │
                  AllReduce
                  (sync gradients)
```

Use when: Model fits on one GPU, you want to scale throughput.

### Fully Sharded Data Parallel (FSDP)

Model parameters, gradients, and optimiser states are sharded across GPUs.

```
┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐
│ GPU 0   │  │ GPU 1   │  │ GPU 2   │  │ GPU 3   │
│ Shard 0 │  │ Shard 1 │  │ Shard 2 │  │ Shard 3 │
│ 1/4     │  │ 1/4     │  │ 1/4     │  │ 1/4     │
│ params  │  │ params  │  │ params  │  │ params  │
└─────────┘  └─────────┘  └─────────┘  └─────────┘
```

Use when: Model doesn't fit on one GPU, or to maximise batch size.

### Tensor Parallel

Individual layers are split across GPUs. Requires high-bandwidth interconnect.

Use when: Single layers are too large for one GPU (70B+ models).

## Key Considerations

### Network Bandwidth

Distributed training is network-bound. Use:
- EFA (Elastic Fabric Adapter) on AWS
- High-bandwidth instance types (p4d, p5)
- Placement groups for low latency

### Storage

Training needs fast storage for:
- Datasets (read-heavy)
- Checkpoints (write-heavy, large)
- Logs and metrics

Options:
- FSx for Lustre (high-performance parallel filesystem)
- EBS io2 (single-node, lower cost)
- S3 + caching (for datasets)

### Checkpointing

Save state frequently enough to limit lost work:

| Checkpoint Interval | Lost Work on Failure |
|--------------------|---------------------|
| Every hour | Up to 1 hour |
| Every 30 min | Up to 30 min |
| Every 1000 steps | Variable |

Balance checkpoint frequency against I/O overhead.
