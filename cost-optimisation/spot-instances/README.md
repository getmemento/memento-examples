# Spot Instances for AI Workloads

## Problem

GPU instances are expensive. A p4d.24xlarge costs ~£25/hour on-demand. Running 24/7, that's £18,000/month for a single node.

Spot instances offer the same hardware at 60-70% discount, but:
- They can be interrupted with 2 minutes notice
- Availability varies by instance type and region
- Not all workloads can tolerate interruption

## Solution

Use spot instances strategically:
- Inference with multiple replicas (interrupt one, others handle traffic)
- Training with checkpointing (resume from checkpoint after interruption)
- Development and testing (interruption is acceptable)

## Spot Savings by Instance Type

| Instance | On-Demand | Spot (typical) | Savings |
|----------|-----------|----------------|---------|
| g4dn.xlarge | $0.53/hr | $0.16/hr | 70% |
| g5.xlarge | $1.01/hr | $0.40/hr | 60% |
| g5.12xlarge | $5.67/hr | $1.70/hr | 70% |
| p3.2xlarge | $3.06/hr | $0.92/hr | 70% |
| p3.8xlarge | $12.24/hr | $3.67/hr | 70% |
| p4d.24xlarge | $32.77/hr | $13.11/hr | 60% |

Spot prices fluctuate. Check current prices in your region.

## EKS Spot Configuration

### Node Group with Spot

```hcl
# Terraform
resource "aws_eks_node_group" "inference_spot" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "inference-spot"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  capacity_type  = "SPOT"
  instance_types = ["g5.xlarge", "g5.2xlarge"]  # Multiple types for availability

  scaling_config {
    min_size     = 0
    max_size     = 20
    desired_size = 5
  }

  labels = {
    "capacity-type" = "spot"
    "workload-type" = "inference"
  }

  taint {
    key    = "capacity-type"
    value  = "spot"
    effect = "NO_SCHEDULE"
  }
}
```

### Pod Configuration

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-spot
spec:
  replicas: 5
  template:
    spec:
      # Tolerate spot taint
      tolerations:
        - key: capacity-type
          operator: Equal
          value: spot
          effect: NoSchedule
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule

      # Prefer spot nodes
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: capacity-type
                    operator: In
                    values:
                      - spot

      # Handle interruption gracefully
      terminationGracePeriodSeconds: 120

      containers:
        - name: inference
          lifecycle:
            preStop:
              exec:
                command:
                  - /bin/sh
                  - -c
                  - |
                    # Drain in-flight requests
                    curl -X POST localhost:8000/drain
                    sleep 30
```

## Spot Interruption Handling

### AWS Node Termination Handler

Detects spot interruptions and cordons/drains nodes:

```yaml
# Install via Helm
helm repo add eks https://aws.github.io/eks-charts
helm install aws-node-termination-handler eks/aws-node-termination-handler \
  --namespace kube-system \
  --set enableSpotInterruptionDraining=true \
  --set enableScheduledEventDraining=true
```

### Application-Level Handling

For training jobs, checkpoint frequently:

```python
# PyTorch training with checkpointing
import torch
import signal
import sys

class SpotInterruptionHandler:
    def __init__(self, checkpoint_path):
        self.checkpoint_path = checkpoint_path
        self.interrupted = False
        signal.signal(signal.SIGTERM, self._handler)

    def _handler(self, signum, frame):
        print("Received SIGTERM, saving checkpoint...")
        self.interrupted = True

    def should_stop(self):
        return self.interrupted

# In training loop
handler = SpotInterruptionHandler("/checkpoints/model.pt")
for epoch in range(num_epochs):
    for batch in dataloader:
        # Training step
        loss = model(batch)
        loss.backward()
        optimizer.step()

        if handler.should_stop():
            torch.save({
                'epoch': epoch,
                'model_state_dict': model.state_dict(),
                'optimizer_state_dict': optimizer.state_dict(),
            }, handler.checkpoint_path)
            sys.exit(0)

    # Checkpoint every epoch anyway
    torch.save({...}, f"/checkpoints/epoch_{epoch}.pt")
```

## Mixed On-Demand and Spot

For production inference, use a mix:

```yaml
# On-demand for baseline capacity
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-baseline
spec:
  replicas: 2  # Always-on capacity
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: capacity-type
                    operator: In
                    values:
                      - on-demand
---
# Spot for burst capacity
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-spot
spec:
  replicas: 5  # Scales based on demand
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: capacity-type
                    operator: In
                    values:
                      - spot
```

## Spot Availability Strategy

Improve availability by:

1. **Multiple instance types**: Request g5.xlarge, g5.2xlarge, g4dn.xlarge
2. **Multiple AZs**: Spread across availability zones
3. **Capacity-optimised allocation**: Let AWS choose from available capacity

```hcl
# Terraform - capacity-optimised spot
resource "aws_launch_template" "spot" {
  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type             = "one-time"
      instance_interruption_behavior = "terminate"
    }
  }
}
```

## When NOT to Use Spot

| Scenario | Use On-Demand | Reason |
|----------|---------------|--------|
| Latency-critical production | Yes | Interruption causes latency spike |
| Single-replica services | Yes | No redundancy during interruption |
| Long training without checkpointing | Yes | Lost progress is expensive |
| Stateful workloads | Yes | State recovery is complex |

## Files

```
spot-instances/
├── terraform/
│   ├── spot-node-group.tf
│   └── mixed-capacity.tf
├── manifests/
│   ├── inference-spot.yaml
│   ├── training-spot.yaml
│   └── node-termination-handler.yaml
└── README.md
```

## Cost Tracking

Track spot vs on-demand usage:

```promql
# Spot node count
count(kube_node_labels{label_capacity_type="spot"})

# On-demand node count
count(kube_node_labels{label_capacity_type="on-demand"})

# Spot interruptions (requires node-termination-handler)
sum(increase(aws_node_termination_handler_actions_total{action="cordon-and-drain"}[24h]))
```
