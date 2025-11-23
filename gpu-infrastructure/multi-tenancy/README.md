# Multi-Tenancy for GPU Clusters

## Problem

Multiple teams need to share a GPU cluster without stepping on each other:

- Team A's runaway training job shouldn't consume all GPUs
- Team B's experiments shouldn't affect Team C's production inference
- Cost attribution needs to be clear for chargeback
- Teams need isolation but shouldn't have to manage their own clusters

## Solution

Use Kubernetes namespaces with resource quotas, network policies, and RBAC to create logical separation. Combined with priority classes and scheduling rules, this gives teams independent environments on shared infrastructure.

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                     Shared GPU Cluster                         │
│                                                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │  team-alpha  │  │  team-beta   │  │  team-gamma  │         │
│  │              │  │              │  │              │         │
│  │ Quota: 8 GPU │  │ Quota: 4 GPU │  │ Quota: 12 GPU│         │
│  │ Priority: Hi │  │ Priority: Md │  │ Priority: Hi │         │
│  │              │  │              │  │              │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│                                                                │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                   Shared Node Pools                      │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐        │  │
│  │  │ g5.xlrg │ │ g5.xlrg │ │ p3.8xlrg│ │ g5.2xlrg│        │  │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘        │  │
│  └─────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

## Implementation

### 1. Namespace Setup

Create isolated namespaces per team:

```yaml
# namespaces.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team-alpha
  labels:
    team: alpha
    cost-center: ml-platform
---
apiVersion: v1
kind: Namespace
metadata:
  name: team-beta
  labels:
    team: beta
    cost-center: research
---
apiVersion: v1
kind: Namespace
metadata:
  name: team-gamma
  labels:
    team: gamma
    cost-center: product
```

### 2. Resource Quotas

Limit what each team can consume:

```yaml
# quotas/team-alpha.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gpu-quota
  namespace: team-alpha
spec:
  hard:
    # GPU limits
    requests.nvidia.com/gpu: "8"
    limits.nvidia.com/gpu: "8"
    # CPU/Memory limits
    requests.cpu: "64"
    requests.memory: 256Gi
    limits.cpu: "128"
    limits.memory: 512Gi
    # Object count limits
    pods: "50"
    persistentvolumeclaims: "20"
    services: "10"
```

### 3. RBAC

Give teams access only to their namespace:

```yaml
# rbac/team-alpha.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: team-admin
  namespace: team-alpha
rules:
  - apiGroups: ["", "apps", "batch"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: [""]
    resources: ["resourcequotas"]
    verbs: ["get", "list"]  # Read-only for quotas
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-alpha-admins
  namespace: team-alpha
subjects:
  - kind: Group
    name: team-alpha-admins
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: team-admin
  apiGroup: rbac.authorization.k8s.io
```

### 4. Network Policies

Isolate network traffic between namespaces:

```yaml
# network-policies/default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: team-alpha
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
# Allow internal traffic within namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: team-alpha
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}
  egress:
    - to:
        - podSelector: {}
---
# Allow egress to DNS and external
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: team-alpha
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
```

### 5. Priority Classes Per Team

Allow teams to prioritise their own workloads:

```yaml
# priorities/team-alpha.yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: team-alpha-critical
value: 500000
globalDefault: false
description: "Team Alpha critical workloads"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: team-alpha-standard
value: 100000
globalDefault: false
description: "Team Alpha standard workloads"
```

## GPU Sharing Options

### Time-Slicing

Multiple pods share a GPU by time-slicing. Useful for development:

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
            replicas: 4
```

This lets 4 pods share each physical GPU. Good for development, bad for production inference (unpredictable latency).

### MIG (Multi-Instance GPU)

A100 and H100 GPUs support hardware partitioning:

```yaml
# MIG partitioning example (requires MIG-capable GPUs)
resources:
  limits:
    nvidia.com/mig-1g.5gb: 1  # 1/7 of an A100
```

## Cost Attribution

Label all resources for cost tracking:

```yaml
metadata:
  labels:
    team: alpha
    cost-center: ml-platform
    project: recommendation-engine
    environment: production
```

Use these labels with:
- Kubecost for Kubernetes cost allocation
- AWS Cost Explorer tags (propagated via node labels)
- Custom Prometheus metrics

## Files

```
multi-tenancy/
├── manifests/
│   ├── namespaces.yaml
│   ├── quotas/
│   │   ├── team-alpha.yaml
│   │   ├── team-beta.yaml
│   │   └── team-gamma.yaml
│   ├── rbac/
│   │   ├── team-alpha.yaml
│   │   ├── team-beta.yaml
│   │   └── team-gamma.yaml
│   ├── network-policies/
│   │   └── default-deny.yaml
│   └── priorities/
│       └── team-priorities.yaml
└── README.md
```

## Best Practices

1. **Start with quotas** - easier to increase than decrease later
2. **Use labels consistently** - enables cost attribution and policy enforcement
3. **Default deny networking** - add explicit allows as needed
4. **Separate production namespaces** - different quotas and priorities
5. **Monitor quota usage** - alert before teams hit limits
6. **Document allocation process** - how teams request quota increases
