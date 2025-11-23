# Inference Monitoring

## Problem

Standard HTTP metrics (request count, latency) miss what matters for LLM inference:

- Time to First Token (TTFT) vs total latency
- Token throughput (tokens per second)
- Queue depth and wait time
- KV cache efficiency
- Per-model performance

## Solution

Collect LLM-specific metrics from vLLM/TGI and create dashboards that show actual inference performance.

## vLLM Metrics

vLLM exposes metrics on `/metrics`:

| Metric | Description |
|--------|-------------|
| `vllm:num_requests_running` | Currently processing requests |
| `vllm:num_requests_waiting` | Requests in queue |
| `vllm:gpu_cache_usage_perc` | KV cache utilisation |
| `vllm:num_preemptions_total` | Requests preempted (memory pressure) |
| `vllm:prompt_tokens_total` | Total input tokens processed |
| `vllm:generation_tokens_total` | Total output tokens generated |
| `vllm:request_latency_seconds` | End-to-end request latency |
| `vllm:time_to_first_token_seconds` | Time to first token |
| `vllm:time_per_output_token_seconds` | Per-token generation time |

## TGI Metrics

TGI exposes similar metrics:

| Metric | Description |
|--------|-------------|
| `tgi_request_count` | Total requests |
| `tgi_request_duration_seconds` | Request latency histogram |
| `tgi_queue_size` | Current queue size |
| `tgi_batch_current_size` | Current batch size |
| `tgi_batch_inference_duration_seconds` | Batch inference time |

## Collection Setup

### ServiceMonitor for vLLM

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vllm-metrics
  namespace: inference
spec:
  selector:
    matchLabels:
      app: vllm
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

### Recording Rules

Pre-calculate common metrics:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: inference-recording-rules
spec:
  groups:
    - name: inference
      rules:
        # Tokens per second
        - record: inference:tokens_per_second
          expr: sum(rate(vllm:generation_tokens_total[5m]))

        # Average TTFT
        - record: inference:ttft:avg
          expr: |
            histogram_quantile(0.5,
              rate(vllm:time_to_first_token_seconds_bucket[5m]))

        # P95 TTFT
        - record: inference:ttft:p95
          expr: |
            histogram_quantile(0.95,
              rate(vllm:time_to_first_token_seconds_bucket[5m]))

        # Queue depth
        - record: inference:queue_depth
          expr: sum(vllm:num_requests_waiting)

        # Request rate
        - record: inference:request_rate
          expr: sum(rate(vllm:request_latency_seconds_count[5m]))
```

## Key Metrics to Track

### Latency

```promql
# P50 TTFT (Time to First Token)
histogram_quantile(0.5, rate(vllm:time_to_first_token_seconds_bucket[5m]))

# P95 End-to-end latency
histogram_quantile(0.95, rate(vllm:request_latency_seconds_bucket[5m]))

# Average generation time per token
rate(vllm:time_per_output_token_seconds_sum[5m]) /
rate(vllm:time_per_output_token_seconds_count[5m])
```

### Throughput

```promql
# Tokens generated per second
sum(rate(vllm:generation_tokens_total[5m]))

# Requests per second
sum(rate(vllm:request_latency_seconds_count[5m]))

# Input tokens processed per second
sum(rate(vllm:prompt_tokens_total[5m]))
```

### Queue Health

```promql
# Current queue depth
sum(vllm:num_requests_waiting)

# Queue growth rate
rate(vllm:num_requests_waiting[5m])

# Average wait time (if queue depth > 0)
avg(vllm:request_latency_seconds_sum / vllm:request_latency_seconds_count)
  - avg(vllm:time_to_first_token_seconds_sum / vllm:time_to_first_token_seconds_count)
```

### Efficiency

```promql
# KV cache utilisation
avg(vllm:gpu_cache_usage_perc)

# Preemption rate (should be near 0)
rate(vllm:num_preemptions_total[5m])

# Batch efficiency
avg(vllm:num_requests_running)
```

## Alerting Rules

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: inference-alerts
spec:
  groups:
    - name: inference-alerts
      rules:
        - alert: HighInferenceLatency
          expr: |
            histogram_quantile(0.95,
              rate(vllm:request_latency_seconds_bucket[5m])) > 10
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "P95 inference latency is {{ $value }}s"

        - alert: InferenceQueueBuildingUp
          expr: sum(vllm:num_requests_waiting) > 20
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "{{ $value }} requests waiting in queue"

        - alert: InferenceQueueCritical
          expr: sum(vllm:num_requests_waiting) > 50
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "Critical queue depth: {{ $value }} requests"

        - alert: HighKVCacheUsage
          expr: avg(vllm:gpu_cache_usage_perc) > 95
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "KV cache usage at {{ $value }}%"

        - alert: FrequentPreemptions
          expr: rate(vllm:num_preemptions_total[5m]) > 0.1
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High preemption rate indicates memory pressure"

        - alert: LowTokenThroughput
          expr: |
            sum(rate(vllm:generation_tokens_total[5m])) < 100
            and sum(vllm:num_requests_running) > 0
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Token throughput below 100 tok/s"
```

## SLO Tracking

Define and track SLOs:

```yaml
# SLO: 95% of requests complete in < 5s
- record: inference:slo:latency_5s
  expr: |
    sum(rate(vllm:request_latency_seconds_bucket{le="5"}[5m])) /
    sum(rate(vllm:request_latency_seconds_count[5m]))

# SLO: 99% of TTFTs < 500ms
- record: inference:slo:ttft_500ms
  expr: |
    sum(rate(vllm:time_to_first_token_seconds_bucket{le="0.5"}[5m])) /
    sum(rate(vllm:time_to_first_token_seconds_count[5m]))

# Error budget remaining (30 day window)
- record: inference:error_budget:remaining
  expr: |
    1 - (
      (1 - avg_over_time(inference:slo:latency_5s[30d])) /
      (1 - 0.95)
    )
```

## Files

```
inference-monitoring/
├── manifests/
│   ├── servicemonitor.yaml
│   ├── recording-rules.yaml
│   └── alerting-rules.yaml
├── dashboards/
│   └── inference-overview.json
└── README.md
```
