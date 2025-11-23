# Inference Batching

## Problem

LLM inference has two cost drivers:
1. Model loading (fixed cost per request)
2. Token generation (variable cost)

Single-request processing wastes GPU cycles. While one request waits for tokens to generate, the GPU could be processing other requests.

Without batching, you might see 30-40% GPU utilisation even under load.

## Solution

Batch multiple requests together:
- **Continuous batching**: Add new requests to running batch (vLLM, TGI default)
- **Static batching**: Fixed batch size, wait for batch to fill
- **Dynamic batching**: Adaptive batch size based on load

## How Continuous Batching Works

Traditional batching waits for all requests in a batch to complete:

```
Request 1: [=======]                    (7 tokens)
Request 2: [================]           (16 tokens)
Request 3: [========]                   (8 tokens)
           ← All wait for longest →
```

Continuous batching releases requests as they complete:

```
Request 1: [=======]
Request 2: [================]
Request 3:        [========]
Request 4:               [=========]
           ← GPU always busy →
```

vLLM and TGI implement continuous batching by default.

## Configuration

### vLLM Batching Parameters

```yaml
args:
  # Maximum sequences to batch together
  - --max-num-seqs
  - "256"

  # Maximum tokens in a batch
  - --max-num-batched-tokens
  - "8192"

  # GPU memory for KV cache (higher = more concurrent requests)
  - --gpu-memory-utilization
  - "0.9"

  # Enable prefix caching (reuse KV cache for common prefixes)
  - --enable-prefix-caching
```

### TGI Batching Parameters

```yaml
env:
  # Maximum concurrent requests
  - name: MAX_CONCURRENT_REQUESTS
    value: "128"

  # Maximum batch size
  - name: MAX_BATCH_SIZE
    value: "32"

  # Maximum tokens to prefill in one batch
  - name: MAX_BATCH_PREFILL_TOKENS
    value: "4096"

  # Maximum total tokens (input + output)
  - name: MAX_TOTAL_TOKENS
    value: "8192"

  # Wait time for batching (ms)
  - name: WAITING_SERVED_RATIO
    value: "1.2"
```

## Client-Side Batching

For workloads with many small requests, batch on the client:

```python
import asyncio
from openai import AsyncOpenAI

client = AsyncOpenAI(base_url="http://vllm:8000/v1")

async def batch_inference(prompts: list[str], batch_size: int = 10):
    """Process prompts in batches for efficiency."""
    results = []

    for i in range(0, len(prompts), batch_size):
        batch = prompts[i:i + batch_size]

        # Send batch concurrently
        tasks = [
            client.completions.create(
                model="mistralai/Mistral-7B-Instruct-v0.2",
                prompt=prompt,
                max_tokens=256
            )
            for prompt in batch
        ]

        batch_results = await asyncio.gather(*tasks)
        results.extend(batch_results)

    return results

# Usage
prompts = ["Summarise: " + doc for doc in documents]
results = asyncio.run(batch_inference(prompts, batch_size=20))
```

## Queue-Based Batching

For high-throughput batch processing, use a queue:

```yaml
# Redis queue for batch processing
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-processor
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: processor
          image: your-batch-processor:latest
          env:
            - name: REDIS_URL
              value: redis://redis:6379
            - name: BATCH_SIZE
              value: "32"
            - name: BATCH_TIMEOUT_MS
              value: "100"
            - name: VLLM_URL
              value: http://vllm:8000
```

Processor logic:

```python
import redis
import time
from collections import deque

class BatchProcessor:
    def __init__(self, batch_size=32, timeout_ms=100):
        self.batch_size = batch_size
        self.timeout_ms = timeout_ms
        self.queue = deque()
        self.redis = redis.Redis()

    def process(self):
        while True:
            # Collect batch
            batch = []
            start_time = time.time()

            while len(batch) < self.batch_size:
                elapsed_ms = (time.time() - start_time) * 1000
                if elapsed_ms > self.timeout_ms and batch:
                    break

                item = self.redis.blpop("inference_queue", timeout=0.01)
                if item:
                    batch.append(item)

            if batch:
                # Process batch
                results = self.inference_batch(batch)
                # Return results
                for item, result in zip(batch, results):
                    self.redis.set(f"result:{item['id']}", result)
```

## Measuring Batching Effectiveness

Key metrics:

```promql
# Average batch size
avg(vllm:num_requests_running)

# Tokens generated per second
sum(rate(vllm:generation_tokens_total[5m]))

# GPU utilisation
avg(DCGM_FI_DEV_GPU_UTIL)

# Time per token
histogram_quantile(0.95, rate(vllm:time_per_output_token_seconds_bucket[5m]))
```

## Batching vs Latency Trade-off

Larger batches increase throughput but also latency:

| Batch Size | Throughput (tok/s) | P95 Latency |
|------------|-------------------|-------------|
| 1 | 50 | 20ms |
| 8 | 350 | 45ms |
| 32 | 1200 | 120ms |
| 128 | 3500 | 400ms |

Choose based on your SLO:
- Real-time chat: smaller batches, lower latency
- Batch processing: larger batches, higher throughput

## Files

```
inference-batching/
├── manifests/
│   ├── vllm-batching-config.yaml
│   └── batch-processor.yaml
├── scripts/
│   └── batch_client.py
└── README.md
```
