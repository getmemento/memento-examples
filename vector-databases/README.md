# Vector Databases

RAG applications need vector storage that can:
- Handle millions to billions of vectors
- Return results in milliseconds
- Scale horizontally
- Survive node failures

## Examples

| Example | What It Covers |
|---------|----------------|
| [Qdrant on K8s](./qdrant-on-k8s/) | Production Qdrant deployment with persistence and HA |
| [Weaviate Deployment](./weaviate-deployment/) | Weaviate with modules and backup |
| [Milvus Production](./milvus-production/) | Distributed Milvus for large-scale deployments |

## Comparison

| Feature | Qdrant | Weaviate | Milvus |
|---------|--------|----------|--------|
| Language | Rust | Go | Go/C++ |
| Filtering | Excellent | Good | Excellent |
| Hybrid search | Yes | Yes | Yes |
| GPU acceleration | No | No | Yes |
| Kubernetes operator | Yes | Yes | Yes |
| Complexity | Low | Medium | High |
| Best for | General use | ML pipelines | Large scale |

## Sizing Guidelines

### Memory

Vector databases are memory-intensive. Rough sizing:

```
Memory = (num_vectors × vector_dim × 4 bytes) × 1.5
```

Example: 10M vectors at 1536 dimensions (OpenAI embeddings):
```
10,000,000 × 1536 × 4 × 1.5 = ~92 GB
```

### Storage

Vectors + indices + metadata:

```
Storage = Memory × 2 (for indices and overhead)
```

### Replicas

For production:
- **Minimum**: 3 replicas for HA
- **Read-heavy**: More replicas, load balance
- **Write-heavy**: Fewer replicas, shard more

## Common Patterns

### Filtering Before Search

More efficient than post-filtering:

```python
# Good: Filter during search
results = client.search(
    collection="documents",
    query_vector=embedding,
    filter={"tenant_id": "customer-123"},
    limit=10
)

# Bad: Search then filter (wastes compute)
results = client.search(collection="documents", query_vector=embedding, limit=1000)
results = [r for r in results if r.metadata["tenant_id"] == "customer-123"][:10]
```

### Batch Ingestion

Don't insert one vector at a time:

```python
# Good: Batch insert
client.upsert(
    collection="documents",
    points=[
        {"id": i, "vector": vec, "payload": meta}
        for i, (vec, meta) in enumerate(zip(vectors, metadata))
    ]
)

# Bad: Individual inserts (slow)
for i, (vec, meta) in enumerate(zip(vectors, metadata)):
    client.upsert(collection="documents", points=[{"id": i, "vector": vec, "payload": meta}])
```

### Collection Per Tenant vs Filtered

| Approach | Pros | Cons |
|----------|------|------|
| Collection per tenant | Strong isolation, easy deletion | Many collections overhead |
| Single collection + filter | Simpler management | Filter overhead, shared resources |

For < 100 tenants: Collection per tenant
For > 100 tenants: Single collection with tenant_id filter
