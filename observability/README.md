# Observability for AI Infrastructure

Standard Kubernetes monitoring doesn't capture what matters for AI workloads. CPU and memory metrics tell you almost nothing about GPU utilisation, inference latency, or token throughput.

## Examples

| Example | What It Covers |
|---------|----------------|
| [GPU Metrics](./gpu-metrics/) | DCGM exporter, GPU utilisation, memory, temperature |
| [Inference Monitoring](./inference-monitoring/) | Latency, throughput, queue depth, error rates |
| [Cost Attribution](./cost-attribution/) | Per-team, per-model cost tracking |

## Key Metrics by Workload

### Inference

| Metric | Why It Matters | Target |
|--------|---------------|--------|
| Time to First Token (TTFT) | User-perceived latency | < 200ms |
| Tokens per Second | Streaming experience | > 30 tok/s |
| Request Queue Depth | Capacity indicator | < 10 |
| Error Rate | Reliability | < 0.1% |
| GPU Utilisation | Efficiency | > 70% |

### Training

| Metric | Why It Matters | Target |
|--------|---------------|--------|
| GPU Utilisation | Training efficiency | > 80% |
| Samples per Second | Training throughput | Model-dependent |
| Loss | Training progress | Decreasing |
| Gradient Norm | Training stability | Stable |
| Memory Usage | OOM prevention | < 90% |

## Monitoring Stack

```
┌─────────────────────────────────────────────────────────────┐
│                       Grafana                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │ GPU Metrics │  │  Inference  │  │    Cost     │          │
│  │  Dashboard  │  │  Dashboard  │  │  Dashboard  │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Prometheus                              │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│    DCGM     │      │    vLLM     │      │  Kubecost   │
│   Exporter  │      │   Metrics   │      │             │
│             │      │             │      │             │
│ GPU metrics │      │ Inference   │      │ Cost data   │
│             │      │ metrics     │      │             │
└─────────────┘      └─────────────┘      └─────────────┘
```

## Quick Start

```bash
# Install monitoring stack
kubectl apply -f gpu-metrics/manifests/
kubectl apply -f inference-monitoring/manifests/

# Import Grafana dashboards
kubectl apply -f dashboards/

# Access Grafana
kubectl port-forward svc/grafana 3000:3000 -n monitoring
```

## Alert Examples

### GPU

```yaml
- alert: GPUHighTemperature
  expr: DCGM_FI_DEV_GPU_TEMP > 80
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: GPU temperature above 80°C

- alert: GPUMemoryNearlyFull
  expr: DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_FREE > 0.9
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: GPU memory usage above 90%
```

### Inference

```yaml
- alert: HighInferenceLatency
  expr: histogram_quantile(0.95, rate(vllm_request_latency_seconds_bucket[5m])) > 5
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: P95 inference latency above 5 seconds

- alert: InferenceQueueBuildingUp
  expr: sum(vllm:num_requests_waiting) > 50
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: Inference request queue above 50
```
