# Spot Instance Orchestration for Training

## Problem

GPU instances are expensive. A p4d.24xlarge costs ~£25/hour. Spot instances offer 60-70% savings but can be interrupted with 2 minutes notice.

For a 48-hour training job:
- On-demand: £1,200
- Spot: £400 (if no interruptions)
- Spot with 3 interruptions: Still ~£450 (with checkpointing)

Without proper checkpointing, a single interruption loses all progress.

## Solution

1. Checkpoint frequently to durable storage (S3, FSx)
2. Detect interruption signals (SIGTERM) and save state
3. Automatically resume from latest checkpoint
4. Use multiple spot pools to reduce interruption probability

## Spot Interruption Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        Normal Training                           │
│                                                                  │
│   ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐         │
│   │Step 1│──▶│Step 2│──▶│Step 3│──▶│Step 4│──▶│Step 5│──▶ ...  │
│   └──────┘   └──────┘   └──────┘   └──────┘   └──────┘         │
│                  │                      │                        │
│                  ▼                      ▼                        │
│            [Checkpoint]           [Checkpoint]                   │
│                  │                      │                        │
│                  ▼                      ▼                        │
│               ┌─────────────────────────────┐                   │
│               │         S3 / FSx            │                   │
│               └─────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │  SPOT INTERRUPTION │
                    │    (SIGTERM)       │
                    └─────────┬─────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Recovery Flow                               │
│                                                                  │
│   1. Save emergency checkpoint                                   │
│   2. Pod terminated                                              │
│   3. New pod scheduled (possibly different node)                 │
│   4. Load latest checkpoint from S3                              │
│   5. Resume training from Step 4                                 │
│                                                                  │
│   ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐                     │
│   │Step 4│──▶│Step 5│──▶│Step 6│──▶│Step 7│──▶ ...              │
│   └──────┘   └──────┘   └──────┘   └──────┘                     │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation

### 1. Checkpoint to S3

```python
import boto3
import torch
from pathlib import Path

class S3CheckpointManager:
    def __init__(self, bucket: str, prefix: str, local_dir: str = "/tmp/checkpoints"):
        self.s3 = boto3.client('s3')
        self.bucket = bucket
        self.prefix = prefix
        self.local_dir = Path(local_dir)
        self.local_dir.mkdir(parents=True, exist_ok=True)

    def save(self, state: dict, name: str):
        local_path = self.local_dir / name
        torch.save(state, local_path)

        s3_key = f"{self.prefix}/{name}"
        self.s3.upload_file(str(local_path), self.bucket, s3_key)
        print(f"Saved checkpoint to s3://{self.bucket}/{s3_key}")

    def load_latest(self) -> dict:
        # List checkpoints
        response = self.s3.list_objects_v2(
            Bucket=self.bucket,
            Prefix=self.prefix
        )

        if 'Contents' not in response:
            return None

        # Get most recent
        latest = max(response['Contents'], key=lambda x: x['LastModified'])
        local_path = self.local_dir / "latest.pt"

        self.s3.download_file(self.bucket, latest['Key'], str(local_path))
        return torch.load(local_path)
```

### 2. Handle SIGTERM

```python
import signal
import sys

class GracefulInterruptHandler:
    def __init__(self):
        self.interrupted = False
        signal.signal(signal.SIGTERM, self._handler)

    def _handler(self, signum, frame):
        print("Received SIGTERM - will checkpoint and exit")
        self.interrupted = True

    def check(self):
        return self.interrupted

# In training loop
interrupt_handler = GracefulInterruptHandler()

for step in range(start_step, total_steps):
    # Check for interruption every step
    if interrupt_handler.check():
        print("Saving emergency checkpoint...")
        checkpoint_manager.save({
            'step': step,
            'model': model.state_dict(),
            'optimizer': optimizer.state_dict(),
        }, f"emergency_step_{step}.pt")
        sys.exit(0)

    # Normal training step
    train_step(model, batch)

    # Regular checkpointing
    if step % checkpoint_interval == 0:
        checkpoint_manager.save(...)
```

### 3. Kubernetes Job with Restart

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: training-spot
spec:
  backoffLimit: 100  # Retry many times
  template:
    spec:
      restartPolicy: OnFailure  # Restart on spot termination
      terminationGracePeriodSeconds: 120  # Time to save checkpoint

      tolerations:
        - key: capacity-type
          operator: Equal
          value: spot
          effect: NoSchedule

      containers:
        - name: trainer
          image: your-training-image:latest
          command:
            - python
            - train.py
            - --resume-from-latest
            - --checkpoint-bucket=your-bucket
            - --checkpoint-prefix=training/run-001
          env:
            - name: AWS_DEFAULT_REGION
              value: us-east-1
          lifecycle:
            preStop:
              exec:
                command:
                  - /bin/sh
                  - -c
                  - |
                    # Give training loop time to checkpoint
                    sleep 90
```

## Checkpointing Strategies

### Frequency vs Overhead

| Strategy | Checkpoint Size | Frequency | Max Lost Work |
|----------|-----------------|-----------|---------------|
| Full (model + optimizer + data) | Large | Every N steps | N steps |
| Model only | Medium | Every epoch | 1 epoch |
| Gradient checkpointing | N/A | During forward | Memory savings |

### Distributed Checkpointing

For multi-node training, only rank 0 saves:

```python
if dist.get_rank() == 0:
    checkpoint_manager.save(state, name)

# All ranks wait for checkpoint
dist.barrier()
```

For FSDP, use distributed checkpointing:

```python
from torch.distributed.checkpoint import save, load

# Saves sharded checkpoint (each rank saves its shard)
save(
    state_dict={"model": model.state_dict()},
    storage_writer=FileSystemWriter("/checkpoints"),
)
```

## Node Termination Handler Integration

Deploy AWS Node Termination Handler to get early warning:

```yaml
# See manifests/node-termination-handler.yaml
```

The handler:
1. Watches for spot termination notices
2. Cordons the node
3. Sends SIGTERM to pods
4. Gives pods time to checkpoint

## Files

```
spot-orchestration/
├── manifests/
│   ├── training-job-spot.yaml
│   └── node-termination-handler.yaml
├── scripts/
│   └── checkpoint_manager.py
└── README.md
```

## Cost Analysis

Example: 48-hour training on p4d.24xlarge

| Scenario | Cost | Risk |
|----------|------|------|
| On-demand | £1,200 | None |
| Spot, no interruptions | £400 | - |
| Spot, 3 interruptions (30min checkpoint interval) | £460 | ~1.5hr lost work |
| Spot, catastrophic (no checkpointing) | £400 + restart | Up to 48hr lost |

With proper checkpointing, spot training is almost always worthwhile.
