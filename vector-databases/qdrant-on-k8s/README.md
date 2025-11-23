# Qdrant on Kubernetes

## Problem

You need a vector database for your RAG application that:
- Handles millions of vectors with sub-100ms query latency
- Survives pod restarts without data loss
- Scales horizontally as data grows
- Supports filtering alongside vector search

## Solution

Deploy Qdrant on Kubernetes with:
- StatefulSet for stable network identities
- Persistent volumes for durability
- Horizontal scaling with sharding
- Prometheus metrics for monitoring

## Architecture

### Single Node (Development)

```
┌─────────────────────────────────────────┐
│            Kubernetes Cluster            │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │           Qdrant Pod               │ │
│  │  ┌──────────────────────────────┐  │ │
│  │  │         Qdrant Server        │  │ │
│  │  │                              │  │ │
│  │  │  Collections:                │  │ │
│  │  │  - documents (1M vectors)    │  │ │
│  │  │  - products (500K vectors)   │  │ │
│  │  └──────────────────────────────┘  │ │
│  │               │                    │ │
│  │               ▼                    │ │
│  │  ┌──────────────────────────────┐  │ │
│  │  │      Persistent Volume       │  │ │
│  │  │         (100GB EBS)          │  │ │
│  │  └──────────────────────────────┘  │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### Distributed (Production)

```
┌─────────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                          │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │  Qdrant-0   │  │  Qdrant-1   │  │  Qdrant-2   │              │
│  │  (Shard 0)  │  │  (Shard 1)  │  │  (Shard 2)  │              │
│  │             │  │             │  │             │              │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │              │
│  │ │ Replica │ │  │ │ Replica │ │  │ │ Replica │ │              │
│  │ │   0,1   │ │  │ │   1,2   │ │  │ │   2,0   │ │              │
│  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │              │
│  │      │      │  │      │      │  │      │      │              │
│  │      ▼      │  │      ▼      │  │      ▼      │              │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │              │
│  │ │   PVC   │ │  │ │   PVC   │ │  │ │   PVC   │ │              │
│  │ │  200GB  │ │  │ │  200GB  │ │  │ │  200GB  │ │              │
│  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│         │                │                │                      │
│         └────────────────┼────────────────┘                      │
│                          │                                       │
│                    ┌─────┴─────┐                                 │
│                    │  Service  │                                 │
│                    │ (qdrant)  │                                 │
│                    └───────────┘                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Using Helm

```bash
helm repo add qdrant https://qdrant.github.io/qdrant-helm
helm install qdrant qdrant/qdrant \
  --namespace vector-db \
  --create-namespace \
  --values values.yaml
```

### Using Manifests

```bash
kubectl apply -f manifests/
```

## Configuration

### Sizing

| Vectors | Dimensions | Memory | Storage | Nodes |
|---------|------------|--------|---------|-------|
| 1M | 1536 | 16GB | 50GB | 1 |
| 10M | 1536 | 96GB | 300GB | 3 |
| 100M | 1536 | 1TB | 3TB | 10+ |

### Resource Requests

```yaml
resources:
  requests:
    cpu: "2"
    memory: "8Gi"
  limits:
    cpu: "4"
    memory: "16Gi"
```

For 10M vectors at 1536 dimensions, plan for ~10GB RAM per million vectors.

### Storage Class

Use fast storage (gp3 or io2 on AWS):

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: qdrant-storage
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

## Operations

### Creating Collections

```python
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams

client = QdrantClient(host="qdrant.vector-db.svc.cluster.local", port=6333)

client.create_collection(
    collection_name="documents",
    vectors_config=VectorParams(
        size=1536,  # OpenAI embedding dimensions
        distance=Distance.COSINE,
    ),
    # For distributed setup
    shard_number=3,
    replication_factor=2,
)
```

### Backup to S3

```bash
# Snapshot collection
curl -X POST "http://qdrant:6333/collections/documents/snapshots"

# Download snapshot
curl "http://qdrant:6333/collections/documents/snapshots/snapshot-name" -o backup.snapshot

# Upload to S3
aws s3 cp backup.snapshot s3://your-bucket/qdrant-backups/
```

Automated backup CronJob included in manifests.

### Scaling

Add more nodes:

```bash
kubectl scale statefulset qdrant --replicas=5 -n vector-db
```

Then redistribute shards:

```python
# Qdrant will automatically rebalance on scale-up
# For manual control:
client.update_collection(
    collection_name="documents",
    shard_number=5,  # Increase shards
)
```

## Monitoring

### Prometheus Metrics

Qdrant exposes metrics on `:6333/metrics`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: qdrant
spec:
  selector:
    matchLabels:
      app: qdrant
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

Key metrics:
- `qdrant_collections_total` - Number of collections
- `qdrant_vectors_total` - Total vectors stored
- `qdrant_search_latency_seconds` - Search latency histogram
- `qdrant_grpc_requests_total` - Request count by method

### Alerting

```yaml
- alert: QdrantHighLatency
  expr: histogram_quantile(0.95, rate(qdrant_search_latency_seconds_bucket[5m])) > 0.1
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Qdrant P95 search latency above 100ms"

- alert: QdrantDiskSpaceLow
  expr: qdrant_disk_free_bytes / qdrant_disk_total_bytes < 0.1
  for: 10m
  labels:
    severity: critical
  annotations:
    summary: "Qdrant disk space below 10%"
```

## Files

```
qdrant-on-k8s/
├── manifests/
│   ├── namespace.yaml
│   ├── statefulset.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── pdb.yaml
│   ├── servicemonitor.yaml
│   └── backup-cronjob.yaml
├── helm/
│   └── values.yaml
└── README.md
```

## Troubleshooting

### High Memory Usage

Qdrant keeps vectors in memory for fast access. Options:
- Add more RAM
- Enable disk-based storage (slower)
- Shard across more nodes

### Slow Searches

1. Check index type (HNSW parameters)
2. Review filter complexity
3. Consider payload indexing for filtered fields
4. Monitor query patterns

### Data Loss After Restart

Ensure:
- PVC is configured correctly
- Storage class supports persistence
- WAL is enabled (default)
