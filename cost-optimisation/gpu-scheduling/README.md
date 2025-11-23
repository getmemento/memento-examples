# GPU Scheduling for Cost Optimisation

## Problem

Your GPU cluster shows 30% average utilisation, but you can't schedule more workloads because:

- Pods request full GPUs even when they only need a fraction
- Inference pods sit idle between requests
- Training jobs reserve GPUs but spend time on data loading
- No bin packing means fragmented resources

## Solution

Combine multiple scheduling strategies to maximise GPU utilisation:

1. **GPU time-slicing** for development and light workloads
2. **MIG partitioning** for hardware isolation on A100/H100
3. **Bin packing** to fill nodes before scaling out
4. **Queue-based scheduling** for batch workloads

## GPU Time-Slicing

NVIDIA's time-slicing lets multiple pods share a GPU. Each pod gets full access to GPU memory but time-shares compute.

### Configuration

```yaml
# nvidia-device-plugin-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin-config
  namespace: kube-system
data:
  config.yaml: |
    version: v1
    sharing:
      timeSlicing:
        renameByDefault: false
        failRequestsGreaterThanOne: false
        resources:
          - name: nvidia.com/gpu
            replicas: 4  # 4 pods can share each GPU
```

Deploy with the NVIDIA device plugin:

```bash
helm upgrade -i nvdp nvdp/nvidia-device-plugin \
  --namespace kube-system \
  --set config.name=nvidia-device-plugin-config
```

### When to Use

| Use Case | Time-Slicing | Dedicated GPU |
|----------|--------------|---------------|
| Development | Yes | No |
| Light inference | Yes | No |
| Production inference | No | Yes |
| Training | No | Yes |

Time-slicing adds latency variability. Don't use for latency-sensitive production workloads.

## MIG (Multi-Instance GPU)

A100 and H100 GPUs support hardware partitioning via MIG. Unlike time-slicing, MIG provides actual isolation.

### MIG Profiles (A100 80GB)

| Profile | GPU Memory | Compute | Use Case |
|---------|------------|---------|----------|
| 1g.10gb | 10GB | 1/7 | Light inference |
| 2g.20gb | 20GB | 2/7 | Small models |
| 3g.40gb | 40GB | 3/7 | Medium models |
| 4g.40gb | 40GB | 4/7 | Training |
| 7g.80gb | 80GB | 7/7 | Large models |

### Configuration

Enable MIG on nodes:

```bash
# On the GPU node
sudo nvidia-smi -mig 1

# Create MIG instances (example: 7x 1g.10gb)
sudo nvidia-smi mig -cgi 19,19,19,19,19,19,19 -C
```

Use in pods:

```yaml
resources:
  limits:
    nvidia.com/mig-1g.10gb: 1
```

## Bin Packing

Fill nodes completely before scaling out. Reduces cost by minimising node count.

### Cluster Autoscaler Configuration

```yaml
# In autoscaler deployment
args:
  - --expander=least-waste  # Prefer nodes with least wasted resources
  - --scale-down-utilization-threshold=0.5
  - --scale-down-unneeded-time=10m
```

### Pod Priority for Packing

Use pod priorities to ensure important workloads get scheduled first:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority-inference
value: 1000000
---
apiVersion: v1
kind: Pod
spec:
  priorityClassName: high-priority-inference
```

## Descheduler

Rebalance pods to improve utilisation:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: descheduler-policy
  namespace: kube-system
data:
  policy.yaml: |
    apiVersion: descheduler/v1alpha2
    kind: DeschedulerPolicy
    profiles:
      - name: default
        pluginConfig:
          - name: LowNodeUtilization
            args:
              thresholds:
                cpu: 20
                memory: 20
                nvidia.com/gpu: 20
              targetThresholds:
                cpu: 50
                memory: 50
                nvidia.com/gpu: 50
        plugins:
          balance:
            enabled:
              - LowNodeUtilization
```

## Scale-to-Zero

For non-production workloads, scale to zero when idle:

```yaml
# keda-scaledobject.yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: dev-inference
spec:
  scaleTargetRef:
    name: dev-inference
  minReplicaCount: 0
  maxReplicaCount: 5
  idleReplicaCount: 0
  cooldownPeriod: 300
  triggers:
    - type: prometheus
      metadata:
        query: sum(rate(http_requests_total{service="dev-inference"}[5m]))
        threshold: "0.1"
```

## Complete Example

See `manifests/` for:
- Time-slicing configuration
- Descheduler deployment
- KEDA scale-to-zero setup
- Priority classes for GPU workloads

## Measuring Impact

Track these metrics before and after:

| Metric | Before | Target |
|--------|--------|--------|
| GPU utilisation | 30% | 70%+ |
| Node count | N | 0.5N |
| Monthly GPU cost | £X | 0.6X |

```promql
# Average GPU utilisation
avg(DCGM_FI_DEV_GPU_UTIL)

# Nodes with GPUs
count(kube_node_status_allocatable{resource="nvidia_com_gpu"} > 0)

# GPU hours used
sum(increase(DCGM_FI_DEV_GPU_UTIL[30d])) / 100 / 60
```
