# Node Pools & Scheduling

## Problem

You have multiple types of GPU workloads (inference, training, fine-tuning) competing for the same nodes. Without proper scheduling configuration:

- Training jobs starve inference pods of resources
- Expensive GPUs sit idle while pods wait in queue
- Wrong workloads end up on wrong instance types
- Spot interruptions affect critical services

## Solution

Use Kubernetes scheduling primitives (node selectors, affinity, taints, tolerations, and priority classes) to route workloads to appropriate nodes and ensure fair resource allocation.

## Scheduling Strategies

### 1. Node Selectors (Simple)

Basic label matching. Use when you have distinct node pools:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: inference-pod
spec:
  nodeSelector:
    workload-type: inference
    nvidia.com/gpu: "true"
  containers:
    - name: model
      image: your-model:latest
      resources:
        limits:
          nvidia.com/gpu: 1
```

### 2. Node Affinity (Flexible)

More expressive than node selectors. Supports required and preferred rules:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: training-pod
spec:
  affinity:
    nodeAffinity:
      # Must be on a training node
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: workload-type
                operator: In
                values:
                  - training
                  - finetuning
      # Prefer on-demand over spot for long jobs
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          preference:
            matchExpressions:
              - key: capacity-type
                operator: In
                values:
                  - on-demand
  containers:
    - name: trainer
      image: training-job:latest
      resources:
        limits:
          nvidia.com/gpu: 4
```

### 3. Taints and Tolerations (Isolation)

Prevent non-GPU workloads from landing on expensive GPU nodes:

```yaml
# Node taint (applied via node group config)
# key: nvidia.com/gpu, value: true, effect: NoSchedule

# Pod toleration
apiVersion: v1
kind: Pod
metadata:
  name: gpu-pod
spec:
  tolerations:
    - key: nvidia.com/gpu
      operator: Equal
      value: "true"
      effect: NoSchedule
  containers:
    - name: gpu-workload
      resources:
        limits:
          nvidia.com/gpu: 1
```

### 4. Pod Anti-Affinity (Spread)

Spread pods across nodes for high availability:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-service
spec:
  replicas: 4
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app: inference-service
                topologyKey: kubernetes.io/hostname
      containers:
        - name: model
          resources:
            limits:
              nvidia.com/gpu: 1
```

## Priority Classes

Ensure critical workloads get scheduled first:

```yaml
# priorities.yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: inference-critical
value: 1000000
globalDefault: false
description: "Critical inference workloads"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: inference-standard
value: 100000
globalDefault: false
description: "Standard inference workloads"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: training-batch
value: 10000
globalDefault: false
description: "Batch training jobs"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: development
value: 1000
globalDefault: true
description: "Development and experimentation"
```

Use in pods:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: critical-inference
spec:
  priorityClassName: inference-critical
  containers:
    - name: model
      image: production-model:latest
```

## Bin Packing vs Spread

### Bin Packing (Cost Optimisation)

Fill nodes completely before using new ones. Better for cost but worse for availability:

```yaml
# Use with cluster autoscaler expander: least-waste
apiVersion: v1
kind: Pod
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 1
          preference:
            matchExpressions:
              - key: node.kubernetes.io/instance-type
                operator: In
                values:
                  - g5.xlarge  # Prefer smaller instances first
```

### Spread (High Availability)

Distribute across nodes and zones. Better for availability but higher cost:

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: inference-service
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: inference-service
```

## Complete Example: Mixed Workload Scheduling

See `manifests/` for a complete setup with:
- Priority classes for different workload types
- Node affinity rules for GPU scheduling
- Topology spread for high availability
- Resource quotas per namespace

## Files

```
node-pools-scheduling/
├── manifests/
│   ├── priority-classes.yaml
│   ├── inference-deployment.yaml
│   ├── training-job.yaml
│   └── resource-quotas.yaml
└── README.md
```

## Best Practices

1. **Always taint GPU nodes** - prevents non-GPU workloads from wasting expensive resources
2. **Use priority classes** - ensures critical inference isn't blocked by batch jobs
3. **Prefer affinity over nodeSelector** - more flexible, supports soft constraints
4. **Spread critical workloads** - don't put all replicas on one node
5. **Label nodes consistently** - use standard labels like `workload-type`, `capacity-type`
