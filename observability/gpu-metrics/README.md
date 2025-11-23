# GPU Metrics with DCGM Exporter

## Problem

Standard Kubernetes metrics (CPU, memory) don't tell you anything useful about GPU workloads:

- Is the GPU actually being used, or just allocated?
- How much GPU memory is consumed vs available?
- Are there thermal throttling issues?
- Which processes are using the GPU?

## Solution

Deploy NVIDIA DCGM Exporter to collect GPU metrics and expose them to Prometheus.

## Metrics Available

| Metric | Description | Unit |
|--------|-------------|------|
| DCGM_FI_DEV_GPU_UTIL | GPU compute utilisation | % |
| DCGM_FI_DEV_MEM_COPY_UTIL | Memory copy utilisation | % |
| DCGM_FI_DEV_FB_FREE | Free GPU memory | MB |
| DCGM_FI_DEV_FB_USED | Used GPU memory | MB |
| DCGM_FI_DEV_GPU_TEMP | GPU temperature | °C |
| DCGM_FI_DEV_POWER_USAGE | Power consumption | W |
| DCGM_FI_DEV_SM_CLOCK | Streaming multiprocessor clock | MHz |
| DCGM_FI_DEV_MEM_CLOCK | Memory clock | MHz |
| DCGM_FI_DEV_PCIE_TX_THROUGHPUT | PCIe transmit throughput | MB/s |
| DCGM_FI_DEV_PCIE_RX_THROUGHPUT | PCIe receive throughput | MB/s |

## Deployment

### DaemonSet

```bash
kubectl apply -f manifests/dcgm-exporter.yaml
```

Or via Helm:

```bash
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts
helm install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --namespace monitoring \
  --set serviceMonitor.enabled=true
```

### Verify Metrics

```bash
# Port-forward to a DCGM exporter pod
kubectl port-forward -n monitoring ds/dcgm-exporter 9400:9400

# Check metrics
curl localhost:9400/metrics | grep DCGM
```

## Prometheus Configuration

### ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: dcgm-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: dcgm-exporter
  endpoints:
    - port: metrics
      interval: 15s
```

### Recording Rules

Pre-calculate common queries:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gpu-recording-rules
spec:
  groups:
    - name: gpu
      rules:
        # Average GPU utilisation across cluster
        - record: gpu:utilization:avg
          expr: avg(DCGM_FI_DEV_GPU_UTIL)

        # Total GPU memory used
        - record: gpu:memory:used_bytes
          expr: sum(DCGM_FI_DEV_FB_USED) * 1024 * 1024

        # GPU memory utilisation percentage
        - record: gpu:memory:utilization
          expr: |
            sum(DCGM_FI_DEV_FB_USED) /
            (sum(DCGM_FI_DEV_FB_USED) + sum(DCGM_FI_DEV_FB_FREE))

        # GPUs with high temperature
        - record: gpu:high_temp:count
          expr: count(DCGM_FI_DEV_GPU_TEMP > 80)
```

## Alerting Rules

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gpu-alerts
spec:
  groups:
    - name: gpu-alerts
      rules:
        - alert: GPUHighTemperature
          expr: DCGM_FI_DEV_GPU_TEMP > 80
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "GPU {{ $labels.gpu }} temperature is {{ $value }}°C"
            description: "GPU temperature above 80°C for 5 minutes"

        - alert: GPUMemoryNearlyFull
          expr: |
            DCGM_FI_DEV_FB_USED /
            (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) > 0.95
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "GPU {{ $labels.gpu }} memory nearly full"
            description: "GPU memory usage above 95%"

        - alert: GPULowUtilisation
          expr: |
            avg_over_time(DCGM_FI_DEV_GPU_UTIL[1h]) < 20
            and on(node) kube_node_labels{label_nvidia_com_gpu="true"}
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "GPU {{ $labels.gpu }} underutilised"
            description: "GPU utilisation below 20% for 1 hour"

        - alert: GPUXidError
          expr: increase(DCGM_FI_DEV_XID_ERRORS[5m]) > 0
          labels:
            severity: critical
          annotations:
            summary: "GPU {{ $labels.gpu }} XID error detected"
            description: "XID errors indicate GPU hardware or driver issues"
```

## Grafana Dashboard

Import the dashboard from `dashboards/gpu-overview.json` or use dashboard ID 12239 from Grafana.com.

Key panels:
- GPU utilisation over time
- Memory usage per GPU
- Temperature heatmap
- Power consumption
- Per-node GPU summary

## Useful Queries

### GPU Utilisation by Node

```promql
avg by (node) (DCGM_FI_DEV_GPU_UTIL{job="dcgm-exporter"})
```

### Memory Usage Percentage

```promql
100 * DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE)
```

### GPUs Near Thermal Limit

```promql
count(DCGM_FI_DEV_GPU_TEMP > 75)
```

### Total GPU Hours Used (30 days)

```promql
sum(increase(DCGM_FI_DEV_GPU_UTIL[30d])) / 100 / 3600
```

## Files

```
gpu-metrics/
├── manifests/
│   ├── dcgm-exporter.yaml
│   ├── servicemonitor.yaml
│   └── prometheus-rules.yaml
├── dashboards/
│   └── gpu-overview.json
└── README.md
```
