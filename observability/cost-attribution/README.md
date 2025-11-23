# Cost Attribution for AI Workloads

## Problem

Your GPU bill is £50k/month but you have no idea:
- Which team is responsible for what portion?
- Which models are most expensive to run?
- What's the cost per inference request?
- Are development workloads using production resources?

Without cost attribution, you can't optimise, you can't chargeback, and teams have no incentive to be efficient.

## Solution

Implement cost attribution at multiple levels:
1. **Infrastructure level**: Tag AWS resources, use Kubecost
2. **Application level**: Track cost per request, per model
3. **Team level**: Aggregate by namespace/labels for chargeback

## Labelling Strategy

Consistent labels across all resources:

```yaml
metadata:
  labels:
    # Required
    team: ml-platform
    cost-center: product
    environment: production

    # Recommended
    project: recommendation-engine
    model: mistral-7b
    workload-type: inference
```

### AWS Resource Tags

Propagate labels to AWS for Cost Explorer:

```hcl
# In EKS node group
tags = {
  Team        = "ml-platform"
  CostCenter  = "product"
  Environment = "production"
  Project     = "recommendation-engine"
}
```

## Kubecost Setup

Kubecost provides Kubernetes-native cost allocation:

```bash
helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --create-namespace \
  --set kubecostToken="YOUR_TOKEN" \
  --set prometheus.enabled=false \
  --set prometheus.fqdn="http://prometheus-server.monitoring.svc.cluster.local:9090"
```

### GPU Cost Allocation

Kubecost tracks GPU costs if DCGM metrics are available:

```yaml
# kubecost-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kubecost-config
  namespace: kubecost
data:
  GPU_ENABLED: "true"
  GPU_LABEL: "nvidia.com/gpu"
```

## Cost Per Request

Calculate inference cost per request:

```promql
# GPU cost per hour (example: g5.xlarge at £0.80/hr)
# Adjust based on your instance type and region

# Cost per 1000 tokens
(0.80 / 3600) *  # Cost per second
  (1000 / sum(rate(vllm:generation_tokens_total[5m])))  # Seconds per 1000 tokens
```

### Custom Metrics for Cost

Export cost metrics from your application:

```python
from prometheus_client import Counter, Histogram

# Track token costs
tokens_generated = Counter(
    'inference_tokens_generated_total',
    'Total tokens generated',
    ['model', 'team', 'project']
)

request_cost_dollars = Histogram(
    'inference_request_cost_dollars',
    'Cost per request in dollars',
    ['model', 'team'],
    buckets=[0.001, 0.01, 0.05, 0.1, 0.5, 1.0]
)

def track_request(model, team, project, input_tokens, output_tokens):
    tokens_generated.labels(
        model=model,
        team=team,
        project=project
    ).inc(output_tokens)

    # Calculate cost (adjust rates per model)
    cost = calculate_cost(model, input_tokens, output_tokens)
    request_cost_dollars.labels(model=model, team=team).observe(cost)
```

## Recording Rules for Cost

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cost-recording-rules
spec:
  groups:
    - name: cost
      rules:
        # GPU hours by namespace
        - record: cost:gpu_hours:by_namespace
          expr: |
            sum by (namespace) (
              increase(
                kube_pod_container_resource_requests{resource="nvidia_com_gpu"}[1h]
              )
            )

        # Estimated GPU cost by namespace (adjust rate)
        - record: cost:gpu_dollars:by_namespace
          expr: |
            cost:gpu_hours:by_namespace * 1.00  # £1/GPU-hour, adjust as needed

        # Tokens by team
        - record: cost:tokens:by_team
          expr: |
            sum by (team) (
              increase(inference_tokens_generated_total[24h])
            )

        # Cost per 1M tokens by model
        - record: cost:per_million_tokens:by_model
          expr: |
            1000000 * (
              sum by (model) (rate(inference_request_cost_dollars_sum[1h])) /
              sum by (model) (rate(inference_tokens_generated_total[1h]))
            )
```

## Chargeback Report

Generate monthly chargeback data:

```promql
# Total GPU cost by team (30 days)
sum by (team) (
  cost:gpu_dollars:by_namespace *
  on(namespace) group_left(team)
  kube_namespace_labels
) * 720  # hours in 30 days

# Token cost by team
sum by (team) (
  increase(inference_request_cost_dollars_sum[30d])
)
```

### Grafana Dashboard Panels

Key panels for cost dashboard:

1. **Total GPU spend** (current month)
2. **Cost by team** (pie chart)
3. **Cost trend** (time series)
4. **Cost per request by model** (table)
5. **Idle GPU cost** (wasted spend)

## Cost Alerts

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cost-alerts
spec:
  groups:
    - name: cost-alerts
      rules:
        - alert: HighGPUSpend
          expr: |
            sum(cost:gpu_dollars:by_namespace) * 720 > 10000
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "Projected monthly GPU spend exceeds £10k"

        - alert: TeamOverBudget
          expr: |
            sum by (team) (cost:gpu_dollars:by_namespace) * 720 > 5000
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "Team {{ $labels.team }} projected to exceed £5k/month"

        - alert: HighCostPerRequest
          expr: |
            histogram_quantile(0.95, rate(inference_request_cost_dollars_bucket[1h])) > 0.10
          for: 1h
          labels:
            severity: info
          annotations:
            summary: "P95 cost per request is £{{ $value }}"
```

## Best Practices

1. **Label everything** - consistent labels enable accurate attribution
2. **Start with namespace-level** - easiest to implement
3. **Add application-level metrics** - for per-request accuracy
4. **Review monthly** - costs change, attribution should too
5. **Automate reports** - send to Slack/email monthly
6. **Include idle cost** - GPU hours allocated but unused

## Files

```
cost-attribution/
├── manifests/
│   ├── kubecost-values.yaml
│   ├── recording-rules.yaml
│   └── cost-alerts.yaml
├── dashboards/
│   └── cost-overview.json
└── README.md
```
