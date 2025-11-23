# Cost Optimisation

GPU infrastructure is expensive. A single p4d.24xlarge costs about £25/hour. Most AI infrastructure wastes 60-70% of GPU capacity through poor scheduling, idle resources, and missed optimisation opportunities.

## The Problem

| Issue | Typical Waste |
|-------|---------------|
| GPUs idle overnight/weekends | 30-40% of spend |
| No request batching | 20-30% throughput loss |
| On-demand when spot would work | 60-70% premium |
| Over-provisioned for peak | 40-50% underutilisation |

## Examples

| Example | What It Covers |
|---------|----------------|
| [GPU Scheduling](./gpu-scheduling/) | Maximise GPU utilisation through better scheduling |
| [Spot Instances](./spot-instances/) | When and how to use spot for AI workloads |
| [Inference Batching](./inference-batching/) | Batch requests to improve throughput and reduce cost |

## Quick Wins

### 1. Scale to Zero

If you don't need 24/7 inference, scale to zero when idle:

```yaml
# KEDA ScaledObject with scale-to-zero
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: inference-scaler
spec:
  scaleTargetRef:
    name: inference
  minReplicaCount: 0  # Scale to zero
  maxReplicaCount: 10
  idleReplicaCount: 0
  triggers:
    - type: prometheus
      metadata:
        query: sum(rate(http_requests_total{service="inference"}[5m]))
        threshold: "1"
```

### 2. Use Spot for Stateless Inference

Spot instances are 60-70% cheaper. For inference:
- Requests are short (seconds to minutes)
- State is external (model weights from S3/HuggingFace)
- Multiple replicas provide redundancy

### 3. Right-Size Instances

Don't use p4d.24xlarge for a 7B model:

| Model Size | Right-Sized Instance | Over-Provisioned | Monthly Savings |
|------------|---------------------|------------------|-----------------|
| 7B | g5.xlarge ($730/mo) | p3.2xlarge ($2,200/mo) | £1,470 |
| 13B | g5.2xlarge ($1,460/mo) | p3.8xlarge ($8,800/mo) | £7,340 |
| 70B | p4d.24xlarge ($23,600/mo) | Already minimal | - |

### 4. Enable Request Batching

vLLM and TGI batch requests automatically. Ensure it's configured:

```yaml
env:
  - name: MAX_BATCH_SIZE
    value: "32"
  - name: MAX_WAITING_TOKENS
    value: "20"
```

### 5. Use Quantisation

4-bit quantised models use ~75% less memory:

```yaml
args:
  - --model
  - TheBloke/Llama-2-70B-Chat-AWQ
  - --quantization
  - awq
```

This lets you run on smaller (cheaper) instances with minimal quality impact.

## Cost Attribution

Tag everything for chargeback:

```yaml
metadata:
  labels:
    team: ml-platform
    project: recommendation-engine
    environment: production
    cost-center: product
```

Use Kubecost or similar to track per-team, per-project costs.

## Monitoring Cost

Key metrics to track:

| Metric | Target |
|--------|--------|
| GPU utilisation | > 70% during active hours |
| Cost per 1K tokens | Depends on model, track trends |
| Spot interruption rate | < 10% |
| Scale-to-zero savings | Track hours at zero |
