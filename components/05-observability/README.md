# Observability & Monitoring

Comprehensive metrics, monitoring, and alerting for ML workloads using Prometheus and Grafana.

## Overview

The observability stack provides complete visibility into ML training, serving, GPU utilization, and infrastructure health with pre-built dashboards and alerting rules.

### Components

1. **Prometheus** (CNCF Graduated)
   - Time-series metrics database
   - Service discovery for Kubernetes
   - PromQL query language
   - Alerting engine

2. **Grafana** (CNCF Graduated)
   - Visualization and dashboards
   - Multi-datasource support
   - Alert routing and notifications
   - Templating and variables

3. **Pre-built Dashboards**
   - GPU Metrics Dashboard
   - Training Jobs Dashboard
   - Model Serving Dashboard
   - Cost Attribution Dashboard
   - Security Audit Dashboard
   - Infrastructure Overview

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Observability Architecture                  │
└─────────────────────────────────────────────────────────────┘

Metrics Sources          Prometheus              Grafana
┌──────────────┐        ┌──────────────┐        ┌──────────────┐
│ KServe       │───────▶│              │        │  Dashboards  │
│ Metrics      │        │  Scrape &    │───────▶│              │
└──────────────┘        │  Store       │        │  - GPU       │
┌──────────────┐        │              │        │  - Training  │
│ GPU DCGM     │───────▶│  Query:      │        │  - Serving   │
│ Exporter     │        │  PromQL      │        │  - Cost      │
└──────────────┘        │              │        └──────────────┘
┌──────────────┐        │  Alert:      │        ┌──────────────┐
│ Volcano      │───────▶│  Rules       │───────▶│ Alertmanager │
│ Metrics      │        │  Conditions  │        │              │
└──────────────┘        └──────────────┘        │  - Email     │
┌──────────────┐               │                │  - Slack     │
│ Node         │───────────────┘                │  - PagerDuty │
│ Exporter     │                                └──────────────┘
└──────────────┘
```

## Quick Start

### Prerequisites

- Kubernetes 1.28+
- kubectl with admin access
- Helm 3.x

### Installation

#### Install Prometheus Stack (includes Grafana)

```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=100Gi \
  --set grafana.adminPassword="<strong-password>" \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.size=10Gi

# Wait for pods to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=prometheus \
  -n monitoring \
  --timeout=5m
```

### Access Grafana

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Open browser: http://localhost:3000
# Username: admin
# Password: <password-from-install>
```

### Import Pre-built Dashboards

```bash
# Import from Grafana.com
# Go to Dashboards → Import → Enter dashboard ID:

# GPU Metrics: 12239 (NVIDIA DCGM Exporter)
# Kubernetes Cluster: 7249
# Node Exporter: 1860
# KServe Metrics: Custom (see dashboards/ directory)
```

## Key Metrics

### GPU Metrics

From NVIDIA DCGM Exporter:

```promql
# GPU Utilization (%)
DCGM_FI_DEV_GPU_UTIL{gpu="0"}

# GPU Memory Usage (MB)
DCGM_FI_DEV_FB_USED{gpu="0"}

# GPU Temperature (°C)
DCGM_FI_DEV_GPU_TEMP{gpu="0"}

# GPU Power Usage (W)
DCGM_FI_DEV_POWER_USAGE{gpu="0"}

# GPU Memory Utilization (%)
(DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL) * 100
```

### Training Job Metrics

From Volcano:

```promql
# Running jobs per queue
volcano_queue_job_running{queue="ml-team-a"}

# Job duration
histogram_quantile(0.99, rate(volcano_job_duration_seconds_bucket[5m]))

# Job retry count
sum(volcano_job_retry_count) by (job_name)

# GPU allocation per queue
volcano_queue_allocated_resources{resource="nvidia.com/gpu"}
```

### Model Serving Metrics

From KServe/Knative:

```promql
# Request rate (requests/sec)
rate(revision_app_request_count{namespace="ml-serving"}[5m])

# Request latency P99 (ms)
histogram_quantile(0.99,
  rate(revision_app_request_latencies_bucket{namespace="ml-serving"}[5m])
)

# Error rate (%)
(sum(rate(revision_app_request_count{namespace="ml-serving",response_code_class="5xx"}[5m])) /
 sum(rate(revision_app_request_count{namespace="ml-serving"}[5m]))) * 100

# Active pods
sum(kube_pod_status_phase{namespace="ml-serving",phase="Running"})
  by (label_serving_kserve_io_inferenceservice)
```

### Cost Metrics

From OpenCost:

```promql
# Cost per namespace ($/hour)
sum(node_total_hourly_cost) by (namespace)

# GPU cost per team ($/hour)
sum(gpu_hourly_cost * on(node) group_left(team)
  kube_pod_labels{label_team=~".*"}) by (team)

# Training job cost
sum(pod_total_cost{job=~".*training.*"})
```

## Grafana Dashboards

### 1. GPU Metrics Dashboard

Panels:
- GPU Utilization (% per GPU)
- GPU Memory Usage (MB per GPU)
- GPU Temperature (°C per GPU)
- GPU Power Usage (W per GPU)
- GPU Compute Utilization per Pod
- GPU Memory Allocation per Team
- GPU Idle Time

Query example:
```promql
# Average GPU utilization across cluster
avg(DCGM_FI_DEV_GPU_UTIL)
```

### 2. Training Jobs Dashboard

Panels:
- Active Training Jobs
- Job Queue Status
- Jobs per Team
- Training Duration P50/P95/P99
- Resource Utilization per Job
- Job Success/Failure Rate
- GPU Hours per Job

Query example:
```promql
# Job completion time
histogram_quantile(0.95,
  sum(rate(volcano_job_duration_seconds_bucket[1h])) by (le, queue)
)
```

### 3. Model Serving Dashboard

Panels:
- Requests per Second (per model)
- Latency P50/P95/P99 (per model)
- Error Rate (per model)
- Active Replicas (per model)
- Cold Starts per Hour
- Scale-to-Zero Savings
- Inference Cost per 1000 requests

Query example:
```promql
# P99 latency per InferenceService
histogram_quantile(0.99,
  sum(rate(revision_app_request_latencies_bucket[5m]))
    by (le, configuration_name)
)
```

### 4. Cost Attribution Dashboard

Panels:
- Total Cluster Cost ($/month)
- Cost per Team ($/month)
- Cost per Job ($/job)
- GPU Cost vs CPU Cost
- Training Cost vs Serving Cost
- Cost Trends (7d, 30d)
- Top 10 Expensive Jobs

Query example:
```promql
# Monthly cost per team
sum(increase(pod_total_cost[30d])) by (team)
```

### 5. Security Audit Dashboard

Panels:
- Gatekeeper Policy Violations
- Vault Secret Access Events
- Failed Authentication Attempts
- Privileged Container Count
- Network Policy Denials
- RBAC Permission Denied

Query example:
```promql
# Gatekeeper violations
sum(gatekeeper_violations{enforcement_action="deny"}) by (constraint_kind)
```

### 6. Infrastructure Overview

Panels:
- Node Count
- Total CPU/Memory/GPU Capacity
- Resource Utilization (%)
- Pod Count per Namespace
- Disk I/O
- Network Traffic
- Node Health Status

## Alerting Rules

### Critical Alerts

```yaml
groups:
  - name: ml-platform-critical
    interval: 30s
    rules:
      # GPU temperature too high
      - alert: GPUOverheating
        expr: DCGM_FI_DEV_GPU_TEMP > 85
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "GPU {{ $labels.gpu }} overheating"
          description: "GPU temperature is {{ $value }}°C (threshold: 85°C)"

      # Model serving high error rate
      - alert: ModelHighErrorRate
        expr: |
          (sum(rate(revision_app_request_count{response_code_class="5xx"}[5m])) by (configuration_name) /
           sum(rate(revision_app_request_count[5m])) by (configuration_name)) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate for {{ $labels.configuration_name }}"
          description: "Error rate is {{ $value | humanizePercentage }}"

      # Training job stuck
      - alert: TrainingJobStuck
        expr: |
          (time() - volcano_job_start_time) > 3600 and
          volcano_job_phase{phase="Pending"} == 1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Training job {{ $labels.job_name }} stuck in Pending"
          description: "Job pending for over 1 hour"

      # Out of GPU resources
      - alert: GPUResourcesExhausted
        expr: |
          sum(kube_node_status_capacity{resource="nvidia_com_gpu"}) -
          sum(kube_pod_container_resource_requests{resource="nvidia_com_gpu"}) < 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Cluster running low on GPU resources"
          description: "Only {{ $value }} GPUs available"
```

### Warning Alerts

```yaml
  - name: ml-platform-warnings
    interval: 1m
    rules:
      # High model latency
      - alert: ModelHighLatency
        expr: |
          histogram_quantile(0.99,
            sum(rate(revision_app_request_latencies_bucket[5m])) by (le, configuration_name)
          ) > 1000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High P99 latency for {{ $labels.configuration_name }}"
          description: "P99 latency is {{ $value }}ms (threshold: 1000ms)"

      # GPU memory leak
      - alert: GPUMemoryLeak
        expr: |
          (DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL) > 0.95
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "GPU {{ $labels.gpu }} memory near capacity"
          description: "GPU memory usage at {{ $value | humanizePercentage }}"

      # High cost anomaly
      - alert: CostAnomaly
        expr: |
          (increase(namespace_cost[1h]) / avg_over_time(namespace_cost[24h])) > 2
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Cost spike detected in {{ $labels.namespace }}"
          description: "Cost increased by {{ $value }}x compared to 24h average"
```

## Alert Routing

### Configure Alertmanager

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: alertmanager-config
  namespace: monitoring
data:
  alertmanager.yml: |
    global:
      resolve_timeout: 5m

    route:
      receiver: 'slack-critical'
      group_by: ['alertname', 'cluster']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      routes:
        # Critical alerts → Slack + PagerDuty
        - match:
            severity: critical
          receiver: slack-critical
          continue: true
        - match:
            severity: critical
          receiver: pagerduty

        # Warnings → Slack only
        - match:
            severity: warning
          receiver: slack-warnings

    receivers:
      - name: 'slack-critical'
        slack_configs:
          - api_url: 'https://hooks.slack.com/services/XXX/YYY/ZZZ'
            channel: '#ml-platform-critical'
            title: 'Critical Alert: {{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

      - name: 'slack-warnings'
        slack_configs:
          - api_url: 'https://hooks.slack.com/services/XXX/YYY/ZZZ'
            channel: '#ml-platform-alerts'

      - name: 'pagerduty'
        pagerduty_configs:
          - service_key: '<your-pagerduty-key>'
```

## Custom Metrics

### Instrument Python Training Code

```python
from prometheus_client import Counter, Histogram, Gauge, push_to_gateway

# Define metrics
training_loss = Gauge('training_loss', 'Training loss per epoch')
training_accuracy = Gauge('training_accuracy', 'Training accuracy per epoch')
epoch_duration = Histogram('epoch_duration_seconds', 'Time per epoch')
samples_processed = Counter('samples_processed_total', 'Total samples processed')

# In training loop
for epoch in range(num_epochs):
    start_time = time.time()

    # Training step
    loss, accuracy = train_epoch()

    # Update metrics
    training_loss.set(loss)
    training_accuracy.set(accuracy)
    epoch_duration.observe(time.time() - start_time)
    samples_processed.inc(len(train_loader))

    # Push to Prometheus Pushgateway
    push_to_gateway('prometheus-pushgateway:9091', job='training-job', registry=registry)
```

### Deploy Pushgateway

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus-pushgateway
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pushgateway
  template:
    metadata:
      labels:
        app: pushgateway
    spec:
      containers:
        - name: pushgateway
          image: prom/pushgateway:v1.6.2
          ports:
            - containerPort: 9091
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus-pushgateway
  namespace: monitoring
spec:
  selector:
    app: pushgateway
  ports:
    - port: 9091
      targetPort: 9091
```

## Troubleshooting

### Prometheus Not Scraping Targets

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090/targets

# Common issues:
# 1. ServiceMonitor not created
kubectl get servicemonitor -n monitoring

# 2. Label selector mismatch
kubectl get servicemonitor <name> -n monitoring -o yaml

# 3. Pod not exposing metrics
kubectl exec -it <pod> -n <namespace> -- curl localhost:8080/metrics
```

### Grafana Dashboard Not Loading Data

```bash
# Check Prometheus datasource
# Grafana → Configuration → Data Sources → Prometheus
# Test connection

# Check query in Explore
# Grafana → Explore → Select Prometheus → Enter query

# Common issues:
# - Wrong datasource URL
# - Prometheus not scraping metrics
# - PromQL query syntax error
```

### High Memory Usage in Prometheus

```bash
# Check Prometheus memory usage
kubectl top pod -n monitoring -l app.kubernetes.io/name=prometheus

# Solutions:
# 1. Reduce retention period
--set prometheus.prometheusSpec.retention=15d

# 2. Increase memory limits
--set prometheus.prometheusSpec.resources.limits.memory=16Gi

# 3. Reduce scrape interval
--set prometheus.prometheusSpec.scrapeInterval=60s
```

## Best Practices

### 1. Metric Naming

Follow Prometheus naming conventions:
- `<namespace>_<metric_name>_<unit>`
- Examples:
  - `training_loss_total`
  - `inference_latency_seconds`
  - `gpu_memory_bytes`

### 2. Label Cardinality

Avoid high-cardinality labels:
```promql
# ❌ Bad: User ID as label (millions of users)
requests_total{user_id="12345"}

# ✅ Good: Team as label (tens of teams)
requests_total{team="ml-team-a"}
```

### 3. Dashboard Organization

- **Executive Dashboard**: High-level metrics (cost, uptime, jobs)
- **Team Dashboards**: Per-team metrics (GPU usage, cost)
- **Operational Dashboards**: Detailed metrics (latency, errors)
- **Debug Dashboards**: Low-level metrics (pod status, network)

### 4. Alert Fatigue Prevention

- Set appropriate thresholds
- Use `for:` duration to avoid flapping
- Group related alerts
- Route by severity

### 5. Data Retention

- **Hot storage**: 30 days in Prometheus
- **Warm storage**: 90 days in Thanos/Cortex
- **Cold storage**: 1+ year in S3 (Parquet)

## Integration with MLOps Stack

### Monitor Model Training

```python
# In PyTorch training script
from prometheus_client import Summary

training_time = Summary('training_step_seconds', 'Time per training step')

@training_time.time()
def train_step(batch):
    # Training logic
    pass
```

### Monitor Model Serving

KServe automatically exposes metrics:
- `revision_app_request_count`
- `revision_app_request_latencies`
- `queue_average_concurrent_requests`

### Monitor GPU Usage

NVIDIA DCGM Exporter automatically provides:
- GPU utilization
- GPU memory
- GPU temperature
- GPU power

## Component Documentation

- **Prometheus Installation**: [prometheus/prometheus-grafana-install.yaml](prometheus/prometheus-grafana-install.yaml)
- **Dashboard Configs**: [prometheus/grafana-dashboards/](prometheus/grafana-dashboards/)
- **Alert Rules**: [prometheus/alert-rules.yaml](prometheus/alert-rules.yaml)

## Tutorial

For a complete step-by-step tutorial, see:
[Observability and Monitoring Tutorial](../../docs/tutorials/05-observability.md)

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [PromQL Basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [NVIDIA DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter)

---

[← Back: Model Serving](../04-model-serving/README.md) | [Components Overview](../README.md) | [Next: Cost Attribution →](../06-cost-attribution/README.md)
