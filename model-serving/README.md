# Model Serving

Running LLM inference in production is different from running a Jupyter notebook. You need to handle:

- Autoscaling based on request queue depth, not just CPU
- Graceful handling of long-running requests during scale-down
- Model loading time (minutes) vs pod startup time (seconds)
- GPU memory management and batching
- Multiple model versions for A/B testing

## Examples

| Example | What It Covers |
|---------|----------------|
| [vLLM Deployment](./vllm-deployment/) | Production vLLM setup with autoscaling and optimisation |
| [TGI Autoscaling](./tgi-autoscaling/) | Text Generation Inference with custom metrics |
| [Ray Serve Patterns](./ray-serve-patterns/) | Multi-model serving and routing |
| [Inference Optimisation](./inference-optimization/) | Batching, quantisation, KV cache tuning |

## Choosing a Serving Framework

| Framework | Best For | Trade-offs |
|-----------|----------|------------|
| vLLM | High-throughput LLM inference | Limited to transformer models |
| TGI | HuggingFace models, easy setup | Less flexible than vLLM |
| Ray Serve | Multi-model, complex routing | More operational complexity |
| Triton | Multi-framework, batching | Steeper learning curve |

## Key Metrics

For LLM serving, standard CPU/memory metrics aren't enough. Track:

| Metric | Why It Matters |
|--------|---------------|
| Time to First Token (TTFT) | User-perceived latency |
| Tokens per Second (TPS) | Throughput for streaming |
| Queue Depth | Leading indicator for scaling |
| GPU Memory Utilisation | Capacity planning |
| KV Cache Hit Rate | Efficiency of prefix caching |

## Common Patterns

### Request Batching

vLLM and TGI handle batching automatically, but you control the parameters:

```yaml
env:
  - name: MAX_BATCH_SIZE
    value: "32"
  - name: MAX_WAITING_TOKENS
    value: "20"
```

Larger batches = higher throughput, higher latency. Tune based on your SLOs.

### Model Preloading

Models take minutes to load. Use init containers or readiness probes:

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 300  # 5 minutes for large models
  periodSeconds: 10
```

### Graceful Shutdown

Long-running requests need time to complete:

```yaml
terminationGracePeriodSeconds: 300  # 5 minutes
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 30"]
```
