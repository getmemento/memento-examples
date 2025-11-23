# vLLM Production Deployment

## Problem

You want to deploy an LLM for production inference. The challenges:

- Standard HPA doesn't understand LLM workloads (queue depth matters more than CPU)
- Model loading takes 2-10 minutes, making cold starts painful
- GPU memory needs careful management (KV cache, model weights)
- Autoscaling needs to be responsive but not wasteful
- You need observability into token throughput, not just request count

## Solution

A production-ready vLLM deployment with:

- Custom metrics autoscaling based on request queue depth
- Prometheus metrics for inference monitoring
- Proper resource limits and GPU scheduling
- Graceful shutdown for in-flight requests
- Health checks that verify model loading

## Quick Start

```bash
# Deploy the stack
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/

# Check deployment status
kubectl -n inference get pods

# Test the endpoint
kubectl -n inference port-forward svc/vllm 8000:8000
curl http://localhost:8000/v1/models
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                        │
│                                                                  │
│  ┌──────────────┐     ┌──────────────────────────────────────┐  │
│  │   Ingress    │────▶│           vLLM Service               │  │
│  │  Controller  │     │        (ClusterIP/LoadBalancer)      │  │
│  └──────────────┘     └──────────────────────────────────────┘  │
│                                      │                           │
│                       ┌──────────────┴──────────────┐           │
│                       ▼                              ▼           │
│               ┌──────────────┐              ┌──────────────┐    │
│               │  vLLM Pod 1  │              │  vLLM Pod 2  │    │
│               │  GPU: 1xA10G │              │  GPU: 1xA10G │    │
│               │  Model: 7B   │              │  Model: 7B   │    │
│               └──────────────┘              └──────────────┘    │
│                       │                              │           │
│                       └──────────────┬──────────────┘           │
│                                      ▼                           │
│                       ┌──────────────────────────────┐          │
│                       │      Prometheus/KEDA         │          │
│                       │   (metrics & autoscaling)    │          │
│                       └──────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

## Files

```
vllm-deployment/
├── manifests/
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── hpa.yaml
│   ├── keda-scaledobject.yaml
│   ├── servicemonitor.yaml
│   └── pdb.yaml
├── helm/
│   └── vllm/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
└── README.md
```

## Configuration

### Model Selection

Update `deployment.yaml` with your model:

```yaml
args:
  - --model
  - mistralai/Mistral-7B-Instruct-v0.2
  - --max-model-len
  - "8192"
```

Model size determines GPU requirements:

| Model Size | Min GPU Memory | Recommended Instance |
|------------|----------------|---------------------|
| 7B | 16GB | g5.xlarge (A10G) |
| 13B | 28GB | g5.2xlarge (A10G) |
| 34B | 80GB | p4d.24xlarge (A100) |
| 70B | 140GB+ | 2x A100 (tensor parallel) |

### Tensor Parallelism

For models that don't fit on one GPU:

```yaml
args:
  - --model
  - meta-llama/Llama-2-70b-chat-hf
  - --tensor-parallel-size
  - "2"
resources:
  limits:
    nvidia.com/gpu: 2
```

### Quantisation

Reduce memory requirements with quantisation:

```yaml
args:
  - --model
  - TheBloke/Llama-2-70B-Chat-AWQ
  - --quantization
  - awq
```

AWQ models typically use 4-bit weights, reducing memory by ~75%.

## Autoscaling

### Standard HPA (CPU-based)

Works but not ideal for LLM workloads:

```yaml
# hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: vllm-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: vllm
  minReplicas: 1
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

### KEDA (Queue-based)

Better for LLM workloads - scales on pending requests:

```yaml
# keda-scaledobject.yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: vllm-scaledobject
spec:
  scaleTargetRef:
    name: vllm
  minReplicaCount: 1
  maxReplicaCount: 10
  pollingInterval: 15
  cooldownPeriod: 300
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://prometheus:9090
        metricName: vllm_pending_requests
        query: sum(vllm:num_requests_waiting{namespace="inference"})
        threshold: "10"
```

## Monitoring

vLLM exposes Prometheus metrics on `/metrics`:

```yaml
# servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vllm
spec:
  selector:
    matchLabels:
      app: vllm
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

Key metrics to track:

| Metric | Description |
|--------|-------------|
| `vllm:num_requests_running` | Currently processing requests |
| `vllm:num_requests_waiting` | Requests in queue |
| `vllm:gpu_cache_usage_perc` | KV cache utilisation |
| `vllm:avg_generation_throughput_toks_per_s` | Token throughput |

## Production Checklist

- [ ] Resource limits set (CPU, memory, GPU)
- [ ] Readiness probe with sufficient initial delay
- [ ] Liveness probe to restart stuck pods
- [ ] PodDisruptionBudget to prevent all pods going down
- [ ] Graceful shutdown configured (terminationGracePeriodSeconds)
- [ ] GPU node toleration configured
- [ ] HuggingFace token secret created (if using gated models)
- [ ] ServiceMonitor for Prometheus metrics
- [ ] Autoscaling configured (HPA or KEDA)

## Troubleshooting

### Model Loading Fails

Check logs:
```bash
kubectl -n inference logs -l app=vllm --tail=100
```

Common issues:
- Insufficient GPU memory (try smaller model or quantisation)
- HuggingFace token not set (for gated models)
- Network issues downloading model (check egress)

### High Latency

Check queue depth:
```bash
curl http://localhost:8000/metrics | grep num_requests
```

If queue is growing, scale up or optimise:
- Enable continuous batching (default in vLLM)
- Increase `--max-num-seqs` for more concurrent requests
- Use quantised models

### OOM Kills

GPU memory is the bottleneck. Options:
- Reduce `--max-model-len`
- Reduce `--max-num-seqs`
- Use quantisation
- Use larger GPU instance
