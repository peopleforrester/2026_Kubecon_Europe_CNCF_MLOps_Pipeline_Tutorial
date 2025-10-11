# Cost Attribution

Track, analyze, and optimize ML infrastructure costs using OpenCost.

## Overview

OpenCost provides real-time cost allocation for Kubernetes workloads, enabling teams to understand spending, implement chargeback/showback, and optimize infrastructure costs.

### Key Features

- **Real-time cost monitoring**: Per-pod, per-namespace, per-team costs
- **GPU cost tracking**: Specialized GPU cost allocation
- **Cloud integration**: AWS, GCP, Azure pricing APIs
- **Chargeback/Showback**: Cost allocation for internal billing
- **Cost optimization**: Identify waste and optimization opportunities
- **Budget alerts**: Notify teams when spending exceeds thresholds

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Cost Attribution Flow                     │
└─────────────────────────────────────────────────────────────┘

Resource Usage         OpenCost Engine           Cost Reports
┌──────────────┐      ┌──────────────────┐      ┌──────────────┐
│ Prometheus   │─────▶│  Cost Model      │      │  Grafana     │
│              │      │                  │      │              │
│ - CPU usage  │      │  Inputs:         │      │  Dashboards: │
│ - Memory     │      │  - Node costs    │─────▶│  - Per team  │
│ - GPU hours  │      │  - Storage costs │      │  - Per job   │
│ - Network    │      │  - Cloud pricing │      │  - Per model │
└──────────────┘      │                  │      └──────────────┘
                      │  Outputs:        │      ┌──────────────┐
┌──────────────┐      │  - Pod costs     │─────▶│  API         │
│ K8s API      │─────▶│  - NS costs      │      │              │
│              │      │  - Label costs   │      │  - JSON      │
│ - PVCs       │      │  - Idle costs    │      │  - CSV       │
│ - Services   │      └──────────────────┘      │  - Reports   │
│ - Labels     │                                └──────────────┘
└──────────────┘
```

## Quick Start

### Prerequisites

- Kubernetes 1.28+
- Prometheus (for metrics collection)
- kubectl with admin access
- Cloud provider (for accurate pricing)

### Installation

#### Install OpenCost with Helm

```bash
# Add OpenCost Helm repository
helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm repo update

# Install OpenCost
helm install opencost opencost/opencost \
  --namespace opencost \
  --create-namespace \
  --set opencost.exporter.defaultClusterId=ml-platform-prod \
  --set opencost.prometheus.external.url=http://prometheus-kube-prometheus-prometheus.monitoring:9090 \
  --set opencost.ui.enabled=true \
  --wait

# Wait for OpenCost pods
kubectl wait --for=condition=ready pod \
  -l app=opencost \
  -n opencost \
  --timeout=5m
```

#### Configure Cloud Pricing

For accurate costs, configure cloud provider credentials:

**AWS:**
```bash
kubectl create secret generic opencost-aws-credentials \
  --namespace opencost \
  --from-literal=aws-access-key-id=<YOUR_AWS_ACCESS_KEY_ID> \
  --from-literal=aws-secret-access-key=<YOUR_AWS_SECRET_ACCESS_KEY>

# Update OpenCost deployment
kubectl set env deployment/opencost -n opencost \
  AWS_ACCESS_KEY_ID=<YOUR_KEY> \
  AWS_SECRET_ACCESS_KEY=<YOUR_SECRET>
```

**GCP:**
```bash
kubectl create secret generic opencost-gcp-credentials \
  --namespace opencost \
  --from-file=key.json=<PATH_TO_GCP_SERVICE_ACCOUNT_JSON>

kubectl set env deployment/opencost -n opencost \
  GOOGLE_APPLICATION_CREDENTIALS=/var/secrets/key.json
```

### Access OpenCost UI

```bash
# Port-forward OpenCost UI
kubectl port-forward -n opencost svc/opencost 9090:9090

# Open browser: http://localhost:9090
```

## Cost Allocation Methods

### 1. Per-Namespace Costs

```bash
# Get cost per namespace (last 7 days)
curl http://localhost:9090/allocation/compute \
  -d window=7d \
  -d aggregate=namespace \
  | jq '.data[] | {namespace: .name, cost: .totalCost}'

# Example output:
# {
#   "namespace": "ml-team-a",
#   "cost": 2450.50
# }
# {
#   "namespace": "ml-team-b",
#   "cost": 1820.30
# }
```

### 2. Per-Team Costs (Label-based)

```yaml
# Label pods with team name
apiVersion: v1
kind: Pod
metadata:
  name: training-job
  labels:
    team: ml-team-a
    project: fraud-detection
    environment: prod
```

```bash
# Query costs by team label
curl http://localhost:9090/allocation/compute \
  -d window=7d \
  -d aggregate=label:team \
  | jq '.data[] | {team: .name, cost: .totalCost}'
```

### 3. Per-Job Costs

```bash
# Query costs by job
curl http://localhost:9090/allocation/compute \
  -d window=24h \
  -d aggregate=controller \
  -d filterControllerKinds=job \
  | jq '.data[] | {job: .name, cost: .totalCost}'
```

### 4. Per-Model Costs

```yaml
# Label InferenceServices with model name
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: fraud-detection
  labels:
    model: fraud-detection
    version: v1.0.0
```

```bash
# Query serving costs by model
curl http://localhost:9090/allocation/compute \
  -d window=30d \
  -d aggregate=label:model \
  -d filterNamespaces=ml-serving \
  | jq '.data[] | {model: .name, cost: .totalCost, requests: .properties.requests}'
```

## Cost Breakdown

### Cost Components

OpenCost tracks multiple cost dimensions:

```bash
# Detailed cost breakdown
curl http://localhost:9090/allocation/compute \
  -d window=7d \
  -d aggregate=namespace \
  | jq '.data[0]'

# Output includes:
# {
#   "cpuCost": 850.00,           # CPU usage cost
#   "gpuCost": 1200.00,          # GPU usage cost
#   "ramCost": 200.00,           # Memory usage cost
#   "pvCost": 150.00,            # Persistent volume cost
#   "networkCost": 50.50,        # Network transfer cost
#   "loadBalancerCost": 100.00,  # Load balancer cost
#   "totalCost": 2550.50,        # Total cost
#   "cpuCoreHours": 2040.5,      # CPU hours used
#   "ramByteHours": 13107200000, # Memory byte-hours
#   "gpuHours": 168.0            # GPU hours used
# }
```

### GPU Cost Tracking

Specialized GPU cost allocation:

```promql
# OpenCost GPU cost metrics
opencost_gpu_hourly_cost{node="gpu-node-1",gpu_type="nvidia-tesla-a100"}

# GPU cost per pod
sum(opencost_pod_gpu_allocation * opencost_gpu_hourly_cost) by (pod, namespace)

# GPU efficiency (utilization * allocation)
(avg_over_time(DCGM_FI_DEV_GPU_UTIL[1h]) / 100) *
  (opencost_pod_gpu_allocation / opencost_node_gpu_count)
```

## Grafana Dashboards

### Import OpenCost Dashboard

```bash
# Dashboard ID: 15714 (OpenCost Official)
# Or use custom ML-focused dashboard

# In Grafana:
# Dashboards → Import → Enter 15714 → Load
# Select Prometheus datasource → Import
```

### Custom ML Cost Dashboard Panels

```yaml
# Panel 1: Cost per Team (Bar chart)
Query:
  sum(opencost_allocation_total_cost) by (team)

# Panel 2: GPU vs CPU Cost (Pie chart)
Queries:
  GPU: sum(opencost_allocation_gpu_cost)
  CPU: sum(opencost_allocation_cpu_cost)

# Panel 3: Training vs Serving Cost (Time series)
Queries:
  Training: sum(opencost_allocation_total_cost{namespace=~".*training.*"})
  Serving: sum(opencost_allocation_total_cost{namespace=~".*serving.*"})

# Panel 4: Cost per Model (Table)
Query:
  sum(opencost_allocation_total_cost) by (model) > 100

# Panel 5: Top 10 Expensive Pods (Table)
Query:
  topk(10, sum(opencost_allocation_total_cost) by (pod, namespace))

# Panel 6: Idle Resource Cost (Gauge)
Query:
  sum(opencost_allocation_idle_cost)
```

## Chargeback & Showback

### Monthly Chargeback Report

```bash
# Generate monthly cost report per team
cat <<'EOF' > generate_chargeback.sh
#!/bin/bash

START_DATE="2025-01-01T00:00:00Z"
END_DATE="2025-01-31T23:59:59Z"

curl "http://localhost:9090/allocation/compute?window=${START_DATE},${END_DATE}&aggregate=label:team&format=csv" \
  > chargeback_january_2025.csv

echo "Chargeback report generated: chargeback_january_2025.csv"
cat chargeback_january_2025.csv
EOF

chmod +x generate_chargeback.sh
./generate_chargeback.sh
```

### Showback Dashboard

Create internal billing portal:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cost-dashboard
  namespace: opencost
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cost-dashboard
  template:
    metadata:
      labels:
        app: cost-dashboard
    spec:
      containers:
        - name: dashboard
          image: grafana/grafana:10.2.0
          ports:
            - containerPort: 3000
          env:
            - name: GF_AUTH_ANONYMOUS_ENABLED
              value: "true"
            - name: GF_AUTH_ANONYMOUS_ORG_ROLE
              value: "Viewer"
            - name: GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH
              value: "/var/lib/grafana/dashboards/cost-overview.json"
```

## Cost Optimization

### Identify Idle Resources

```bash
# Find pods with low utilization (< 20%)
curl http://localhost:9090/allocation/compute \
  -d window=7d \
  -d idle=true \
  | jq '.data[] | select(.cpuEfficiency < 0.2) | {pod: .name, efficiency: .cpuEfficiency, wastedCost: .idleCost}'

# Example output:
# {
#   "pod": "ml-team-a/training-job-123",
#   "efficiency": 0.15,
#   "wastedCost": 450.00
# }
```

### Right-Sizing Recommendations

```bash
# Get pod resource usage vs requests
kubectl top pods -n ml-team-a --containers

# Compare with resource requests
kubectl get pods -n ml-team-a -o json | \
  jq '.items[] | {name: .metadata.name, requests: .spec.containers[0].resources.requests}'

# Recommendation: If usage < 50% of requests, reduce requests
```

### GPU Utilization Analysis

```promql
# GPU utilization per pod (last 7 days)
avg_over_time(DCGM_FI_DEV_GPU_UTIL{pod=~".*"}[7d])

# Underutilized GPUs (< 30% average)
avg_over_time(DCGM_FI_DEV_GPU_UTIL[7d]) < 30

# Recommendation: Use fractional GPUs (HAMi) or batch multiple models
```

### Scale-to-Zero Savings

```bash
# Calculate savings from scale-to-zero
# Before: 24/7 running = $360/month
# After: 20% utilization = $72/month
# Savings: $288/month (80%)

# Enable scale-to-zero in KServe
kubectl patch inferenceservice <model-name> -n ml-serving \
  --type merge \
  -p '{"metadata":{"annotations":{"autoscaling.knative.dev/minScale":"0"}}}'
```

## Budget Alerts

### Configure Cost Alerts

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: opencost-alerts
  namespace: opencost
data:
  alerts.yaml: |
    groups:
      - name: cost-alerts
        interval: 1h
        rules:
          # Alert if namespace cost exceeds budget
          - alert: NamespaceCostExceedsBudget
            expr: |
              sum(increase(opencost_allocation_total_cost{namespace="ml-team-a"}[24h])) > 100
            for: 1h
            labels:
              severity: warning
              team: ml-team-a
            annotations:
              summary: "Team A daily cost exceeded $100"
              description: "Daily cost: ${{ $value | humanize }}"

          # Alert if GPU cost is high
          - alert: HighGPUCost
            expr: |
              sum(increase(opencost_allocation_gpu_cost[24h])) > 500
            for: 2h
            labels:
              severity: warning
            annotations:
              summary: "Daily GPU cost exceeded $500"
              description: "GPU cost: ${{ $value | humanize }}"

          # Alert on cost anomaly (2x average)
          - alert: CostAnomaly
            expr: |
              sum(increase(opencost_allocation_total_cost{namespace="ml-team-a"}[1h])) /
              avg_over_time(sum(increase(opencost_allocation_total_cost{namespace="ml-team-a"}[1h]))[24h:1h]) > 2
            for: 30m
            labels:
              severity: critical
              team: ml-team-a
            annotations:
              summary: "Cost spike detected for Team A"
              description: "Cost is {{ $value }}x higher than 24h average"
```

### Send Alerts to Slack

```yaml
# Configure Alertmanager
apiVersion: v1
kind: ConfigMap
metadata:
  name: alertmanager-config
  namespace: monitoring
data:
  alertmanager.yml: |
    route:
      receiver: 'slack-cost-alerts'
      routes:
        - match:
            alertname: NamespaceCostExceedsBudget
          receiver: slack-cost-alerts
          group_by: ['team']

    receivers:
      - name: 'slack-cost-alerts'
        slack_configs:
          - api_url: 'https://hooks.slack.com/services/XXX/YYY/ZZZ'
            channel: '#ml-platform-costs'
            title: 'Cost Alert: {{ .GroupLabels.team }}'
            text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

## Cost Benchmarks

### ML Workload Costs (Monthly)

| Workload Type | Configuration | Monthly Cost | Cost/Unit |
|---------------|---------------|--------------|-----------|
| Training (small) | 4 vCPU, 16GB RAM | $120 | $0.25/job |
| Training (large) | 16 vCPU, 128GB, 2 GPU | $2,400 | $5.00/job |
| Inference (CPU) | 2 vCPU, 4GB RAM, scale-to-zero | $24 | $0.024/1K req |
| Inference (GPU) | 4 vCPU, 16GB, 0.25 GPU | $180 | $0.18/1K req |
| Storage (models) | 500GB SSD | $50 | $0.10/GB/mo |

### Cost Optimization Results

| Optimization | Before | After | Savings |
|--------------|--------|-------|---------|
| Scale-to-zero inference | $360/mo | $72/mo | 80% |
| Fractional GPU (HAMi) | $2,400/mo | $600/mo | 75% |
| Right-sizing pods | $1,200/mo | $800/mo | 33% |
| Spot instances for training | $2,400/mo | $720/mo | 70% |
| **Total** | **$6,360/mo** | **$2,192/mo** | **66%** |

## API Usage

### OpenCost REST API

```bash
# Get allocation data
curl http://localhost:9090/allocation/compute \
  -d window=7d \
  -d aggregate=namespace \
  -G

# Get asset costs (nodes, disks, LBs)
curl http://localhost:9090/allocation/assets \
  -d window=7d \
  -G

# Get savings recommendations
curl http://localhost:9090/savings \
  -G

# Export CSV report
curl http://localhost:9090/allocation/compute \
  -d window=30d \
  -d aggregate=namespace \
  -d format=csv \
  -G > monthly_costs.csv
```

### Programmatic Access (Python)

```python
import requests
import pandas as pd

# Query OpenCost API
def get_namespace_costs(days=7):
    url = "http://localhost:9090/allocation/compute"
    params = {
        "window": f"{days}d",
        "aggregate": "namespace"
    }
    response = requests.get(url, params=params)
    data = response.json()

    # Convert to DataFrame
    costs = []
    for item in data["data"]:
        costs.append({
            "namespace": item["name"],
            "cpu_cost": item["cpuCost"],
            "gpu_cost": item["gpuCost"],
            "ram_cost": item["ramCost"],
            "total_cost": item["totalCost"]
        })

    df = pd.DataFrame(costs)
    return df.sort_values("total_cost", ascending=False)

# Generate report
df = get_namespace_costs(30)
print(df)
df.to_csv("cost_report_30d.csv", index=False)
```

## Troubleshooting

### OpenCost Not Collecting Data

```bash
# Check OpenCost logs
kubectl logs -n opencost deployment/opencost --tail=100

# Verify Prometheus connection
kubectl exec -it -n opencost deployment/opencost -- \
  curl http://prometheus-kube-prometheus-prometheus.monitoring:9090/api/v1/query?query=up

# Common issues:
# - Prometheus URL incorrect
# - Prometheus not scraping node-exporter
# - Cloud pricing API not configured
```

### Costs Show as Zero

```bash
# Check if node costs are configured
kubectl get cm -n opencost opencost-pricing

# If missing, create pricing config
kubectl create configmap opencost-pricing \
  --namespace opencost \
  --from-literal=CPU=0.031611 \
  --from-literal=RAM=0.004237 \
  --from-literal=GPU=1.000000

# Restart OpenCost
kubectl rollout restart deployment/opencost -n opencost
```

### Inaccurate GPU Costs

```bash
# Verify DCGM metrics available
kubectl port-forward -n gpu-operator svc/dcgm-exporter 9400:9400
curl http://localhost:9400/metrics | grep DCGM_FI_DEV_GPU_UTIL

# Check GPU pricing
kubectl get cm -n opencost opencost-pricing -o yaml | grep GPU

# Update GPU pricing (example: A100 = $3.06/hr)
kubectl patch cm opencost-pricing -n opencost \
  --type merge \
  -p '{"data":{"GPU":"3.06"}}'
```

## Best Practices

### 1. Consistent Labeling

```yaml
# Standard labels for cost tracking
apiVersion: v1
kind: Pod
metadata:
  labels:
    team: ml-team-a           # Required: For chargeback
    project: fraud-detection  # Required: Project attribution
    environment: prod         # Required: Environment type
    cost-center: ml-research  # Optional: Finance dept code
    model: fraud-detection-v2 # Optional: Model name
```

### 2. Budget Allocation

```yaml
# Set namespace resource quotas aligned with budgets
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ml-team-a-quota
  namespace: ml-team-a
  annotations:
    monthly-budget: "2000"  # $2000/month budget
spec:
  hard:
    requests.cpu: "100"      # Limit to ~$75/day CPU
    requests.memory: "500Gi"
    requests.nvidia.com/gpu: "4"  # 4 GPUs = ~$300/day
```

### 3. Cost Reviews

- **Weekly**: Review top spending teams/projects
- **Monthly**: Generate chargeback reports
- **Quarterly**: Analyze trends, set optimization targets

### 4. Optimization Cycle

1. **Measure**: Collect 2 weeks of cost data
2. **Analyze**: Identify inefficiencies (idle resources, overprovisioning)
3. **Optimize**: Implement changes (right-sizing, scale-to-zero, spot instances)
4. **Validate**: Measure cost reduction
5. **Repeat**: Continuous improvement

## Integration with ML Platform

### Cost-Aware Scheduling

```yaml
# Prefer cheaper nodes for non-critical workloads
apiVersion: v1
kind: Pod
metadata:
  name: training-job-dev
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          preference:
            matchExpressions:
              - key: node-pool
                operator: In
                values:
                  - spot-instances  # Cheaper spot instances
```

### Model Cost Tracking

```yaml
# Track cost per model version
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: fraud-detection
  labels:
    model: fraud-detection
    version: v2.1.0
    cost-tier: standard  # Standard, premium, economy
  annotations:
    cost-budget: "500"  # $500/month budget
```

## Component Documentation

- **OpenCost Installation**: [opencost/opencost-install.yaml](opencost/opencost-install.yaml)
- **Cost Dashboard**: [opencost/grafana-dashboard.json](opencost/grafana-dashboard.json)
- **Alert Rules**: [opencost/cost-alerts.yaml](opencost/cost-alerts.yaml)

## Tutorial

For a complete step-by-step tutorial, see:
[Cost Attribution Tutorial](../../docs/tutorials/06-cost-attribution.md)

## References

- [OpenCost Documentation](https://www.opencost.io/docs/)
- [OpenCost API Reference](https://www.opencost.io/docs/integrations/api)
- [Kubernetes Cost Optimization Guide](https://kubernetes.io/docs/concepts/cluster-administration/cost-optimization/)
- [Cloud Cost Management Best Practices](https://www.cncf.io/blog/2023/01/10/kubernetes-cost-optimization/)

---

[← Back: Observability](../05-observability/README.md) | [Components Overview](../README.md) | [Next: Security & Governance →](../07-security/README.md)
