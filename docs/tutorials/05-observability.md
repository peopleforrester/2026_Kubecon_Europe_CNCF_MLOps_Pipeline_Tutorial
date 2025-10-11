# Observability & Monitoring Tutorial

This tutorial demonstrates how to set up complete observability for your ML platform with Prometheus, Grafana, AlertManager, and Jaeger distributed tracing.

## Overview

Observability stack provides:

- **Prometheus**: Metrics collection and storage (15s scrape interval, 30 day retention)
- **Grafana**: Visualization dashboards (6 pre-built dashboards)
- **AlertManager**: Alert routing to Slack/PagerDuty
- **Jaeger**: Distributed tracing for request flows
- **Custom Metrics**: ML-specific metrics (accuracy, drift, cost)

## Architecture

### Observability Stack Overview

```mermaid
graph TB
    subgraph sources["Metric Sources"]
        KSERVE[KServe<br/>InferenceServices]
        VOLCANO[Volcano<br/>Training Jobs]
        GPU[NVIDIA DCGM<br/>GPU Metrics]
        HARBOR[Harbor<br/>Registry]
        CUSTOM[Custom ML<br/>Metrics]
    end

    subgraph monitoring["Monitoring Core"]
        PROM[Prometheus<br/>Metrics Storage<br/>30d retention]
        AM[AlertManager<br/>Alert Routing]
    end

    subgraph visualization["Visualization"]
        GRAFANA[Grafana]
        DASH1[ML Platform<br/>Overview]
        DASH2[Training<br/>Jobs]
        DASH3[Model<br/>Serving]
        DASH4[GPU<br/>Utilization]
        DASH5[Cost<br/>Attribution]
        DASH6[Performance<br/>& Drift]
    end

    subgraph alerting["Alert Destinations"]
        SLACK[Slack]
        PD[PagerDuty]
        EMAIL[Email]
    end

    KSERVE -->|scrape 15s| PROM
    VOLCANO -->|scrape 15s| PROM
    GPU -->|scrape 15s| PROM
    HARBOR -->|scrape 15s| PROM
    CUSTOM -->|scrape 15s| PROM

    PROM --> GRAFANA
    PROM --> AM

    GRAFANA --> DASH1
    GRAFANA --> DASH2
    GRAFANA --> DASH3
    GRAFANA --> DASH4
    GRAFANA --> DASH5
    GRAFANA --> DASH6

    AM --> SLACK
    AM --> PD
    AM --> EMAIL

    style monitoring fill:#e1f5ff
    style sources fill:#fff4e1
    style visualization fill:#e8f5e9
    style alerting fill:#f3e5f5
```

### Distributed Tracing Flow

```mermaid
sequenceDiagram
    participant Client
    participant App as Application<br/>(OpenTelemetry)
    participant OTEL as OTEL Collector
    participant Jaeger as Jaeger Backend
    participant UI as Jaeger UI

    Client->>App: POST /predict
    activate App

    App->>App: Start span: preprocess
    Note over App: Extract features<br/>50ms
    App->>App: End span: preprocess

    App->>App: Start span: inference
    Note over App: Model predict<br/>580ms
    App->>App: End span: inference

    App->>App: Start span: postprocess
    Note over App: Format response<br/>20ms
    App->>App: End span: postprocess

    App->>OTEL: Export trace
    deactivate App
    OTEL->>Jaeger: Store trace
    Jaeger-->>UI: Query traces

    Note over UI: Total duration: 650ms<br/>Bottleneck: inference

    App-->>Client: Response
```

### Alert Routing Logic

```mermaid
graph TB
    ALERT{New Alert}

    ALERT -->|Severity| SEV{Check<br/>Severity}

    SEV -->|Critical| ONCALL[Page<br/>On-Call]
    SEV -->|Warning| SLACK[Slack<br/>Channel]
    SEV -->|Info| LOG[Log Only]

    ONCALL --> CHECK{Ack within<br/>5 minutes?}
    CHECK -->|No| ESC[Escalate to<br/>Manager]
    CHECK -->|Yes| RESOLVE[Resolve<br/>Issue]

    ESC --> PD[PagerDuty<br/>Escalation]

    style ALERT fill:#ff9800
    style ONCALL fill:#f44336
    style SLACK fill:#4caf50
    style ESC fill:#f44336
    style RESOLVE fill:#2196f3
```

## Prerequisites

1. Kubernetes cluster (1.28+)
2. kubectl configured
3. Helm 3.x installed
4. 600Gi storage for metrics

## Part 1: Install Prometheus & Grafana

### Step 1.1: Add Helm repository

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### Step 1.2: Create namespace

```bash
kubectl create namespace monitoring
```

### Step 1.3: Install Prometheus Operator stack

```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=500Gi \
  --set grafana.adminPassword=admin123 \
  --wait
```

**This installs:**
- Prometheus Operator
- Prometheus (2 replicas for HA)
- Grafana
- AlertManager (3 replicas)
- Node Exporter
- kube-state-metrics

### Step 1.4: Verify installation

```bash
# Check pods
kubectl get pods -n monitoring

# Expected output:
# prometheus-prometheus-kube-prometheus-prometheus-0   Running
# prometheus-grafana-xxx                                Running
# alertmanager-prometheus-kube-prometheus-alertmanager-0 Running
```

### Step 1.5: Access Grafana

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

Open http://localhost:3000
- Username: `admin`
- Password: `admin123`

## Part 2: Install Service Monitors

### Step 2.1: KServe models monitoring

```bash
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kserve-models
  namespace: monitoring
spec:
  selector:
    matchLabels:
      serving.kserve.io/inferenceservice: ""
  namespaceSelector:
    matchNames:
      - ml-serving
  endpoints:
    - port: metrics
      interval: 15s
EOF
```

### Step 2.2: GPU metrics (DCGM)

```bash
# Install NVIDIA GPU Operator (if not already)
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set dcgmExporter.enabled=true

# Create ServiceMonitor for GPU metrics
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: dcgm-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: nvidia-dcgm-exporter
  namespaceSelector:
    matchNames:
      - gpu-operator
  endpoints:
    - port: metrics
      interval: 15s
EOF
```

### Step 2.3: Verify metrics collection

```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Open http://localhost:9090
# Query: up{job="kserve-models"}
# Should return metrics from KServe pods
```

## Part 3: Import Grafana Dashboards

### Step 3.1: Apply dashboard ConfigMaps

```bash
kubectl apply -f components/05-observability/grafana/ml-monitoring-dashboards.yaml
```

###Step 3.2: Access dashboards in Grafana

1. Open Grafana: http://localhost:3000
2. Navigate to Dashboards → Browse
3. Look for "ML Platform" folder
4. Available dashboards:
   - ML Platform Overview
   - ML Training Jobs
   - Model Serving
   - GPU Utilization
   - Cost Attribution
   - Model Performance & Drift

### Step 3.3: Verify dashboard data

Open "ML Platform Overview" dashboard:
- Should show: Active training jobs, model servers, GPU count
- If no data, check ServiceMonitors are collecting metrics

## Part 4: Configure Alerting

### Step 4.1: Apply alert rules

```bash
kubectl apply -f components/05-observability/alerting/prometheus-alert-rules.yaml
```

### Step 4.2: Configure Slack webhook

```bash
# Get your Slack webhook URL from https://api.slack.com/messaging/webhooks

# Update AlertManager config
kubectl edit secret -n monitoring alertmanager-prometheus-kube-prometheus-alertmanager

# Add Slack webhook under alertmanager.yaml:
# global:
#   slack_api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
```

### Step 4.3: Test alerting

```bash
# Create a failing deployment to trigger alert
kubectl run test-fail --image=invalid-image --namespace=ml-serving

# Check AlertManager
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093

# Open http://localhost:9093
# Should see "ModelServingNoHealthyReplicas" firing
```

## Part 5: Distributed Tracing with Jaeger

### Step 5.1: Install Jaeger Operator

```bash
# Install cert-manager (prerequisite)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Wait for cert-manager
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/component=webhook \
  -n cert-manager \
  --timeout=5m

# Install Jaeger Operator
kubectl create namespace observability
kubectl create -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.51.0/jaeger-operator.yaml -n observability
```

### Step 5.2: Create Jaeger instance

```bash
kubectl apply -f components/05-observability/jaeger/distributed-tracing.yaml
```

### Step 5.3: Access Jaeger UI

```bash
kubectl port-forward -n observability svc/jaeger-ml-platform-query 16686:16686
```

Open http://localhost:16686

### Step 5.4: Instrument model code

Create `model_server.py` with OpenTelemetry:

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

# Initialize tracing
trace.set_tracer_provider(TracerProvider())
tracer = trace.get_tracer(__name__)

otlp_exporter = OTLPSpanExporter(
    endpoint="otel-collector.observability:4317",
    insecure=True
)

@app.route('/predict', methods=['POST'])
def predict():
    with tracer.start_as_current_span("predict") as span:
        # Your inference code
        result = model.predict(data)
        span.set_attribute("ml.model_name", "resnet50")
        return result
```

### Step 5.5: View traces

1. Send requests to instrumented model
2. Open Jaeger UI
3. Select Service: "resnet50-inference"
4. Click "Find Traces"
5. View trace timeline showing latency breakdown

## Monitoring Workflows

### Monitor Training Job

**Scenario:** Track GPU utilization during training

```bash
# Open Grafana → ML Training Jobs dashboard
# Select job name from dropdown
# View panels:
#   - GPU Utilization per Job (should be 80-100%)
#   - GPU Memory per Job
#   - Training Duration
#   - Training Loss (if custom metric exported)
```

### Monitor Model Serving

**Scenario:** Check request rate and latency

```bash
# Open Grafana → Model Serving dashboard
# View panels:
#   - Request Rate by Model
#   - Latency P50/P95/P99
#   - Error Rate by Model
#   - Replica Count (autoscaling)
```

### Debug Slow Inference

**Scenario:** Request taking > 500ms

1. Check Grafana → Model Serving → Latency P99
2. Identify model with high latency
3. Open Jaeger UI
4. Search for traces with duration > 500ms
5. View trace timeline:
   ```
   Total: 650ms
   ├─ preprocess: 50ms
   ├─ inference: 580ms  ← Bottleneck!
   └─ postprocess: 20ms
   ```
6. Optimize inference step (use TensorRT, quantization, or GPU)

### Investigate Alert

**Scenario:** Received "ModelServingHighErrorRate" alert

1. Check Slack notification for details
2. Open Grafana → Model Serving dashboard
3. Check Error Rate panel (see which model)
4. Open Prometheus → Alerts
5. Query error logs:
   ```promql
   rate(revision_app_request_count{
     service_name="bert-base",
     response_code_class="5xx"
   }[5m])
   ```
6. Check recent deployments (canary rollout issue?)
7. Rollback if needed

## Troubleshooting

### No metrics in Grafana

**Check ServiceMonitors:**
```bash
kubectl get servicemonitors -n monitoring
```

**Check Prometheus targets:**
```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Open http://localhost:9090/targets
# All targets should be "UP"
```

**If target is DOWN:**
- Check pod has metrics endpoint
- Verify port and path are correct
- Check network policies allow scraping

### Alerts not firing

**Check alert rules:**
```bash
# Port-forward Prometheus
# Open http://localhost:9090/alerts
# Should see all configured alerts
```

**Check AlertManager:**
```bash
kubectl logs -n monitoring alertmanager-prometheus-kube-prometheus-alertmanager-0
```

**Common issues:**
- Slack webhook URL incorrect
- Silenced alerts
- Alert not meeting threshold

### Jaeger not receiving traces

**Check OpenTelemetry Collector:**
```bash
kubectl logs -n observability deployment/otel-collector
```

**Verify endpoint:**
```bash
# From application pod
curl http://otel-collector.observability:4318/v1/traces -X POST
```

**Check instrumentation:**
- Verify OpenTelemetry SDK installed
- Check OTEL_EXPORTER_OTLP_ENDPOINT env var
- Enable debug logging in SDK

## Best Practices

### 1. Metrics

**What to monitor:**
- Infrastructure: CPU, memory, disk, network, GPU
- Training: Loss, accuracy, GPU utilization, duration
- Serving: Request rate, latency, error rate, replicas
- Business: Model accuracy, drift, cost per model

**Retention:**
- High resolution (15s): 7 days
- Medium (1m): 30 days
- Low (5m): 1 year (via downsampling)

### 2. Dashboards

**Organization:**
- 1 overview dashboard (executives)
- 1 per component (training, serving, GPU)
- 1 for cost attribution
- Team-specific dashboards

**Design:**
- Use appropriate viz (graph, stat, gauge)
- Set meaningful thresholds
- Include units (ms, %, $)
- Add descriptions

### 3. Alerting

**Severity levels:**
- Critical: Production down, page on-call
- Warning: Degraded, action within hours
- Info: FYI only, no action needed

**Alert fatigue prevention:**
- Use `for:` duration (avoid flapping)
- Group similar alerts
- Aim for < 10 alerts/day
- Review noisy alerts monthly

### 4. Tracing

**Sampling:**
- Production: 1-10% (reduce overhead)
- Development: 100% (debug all)
- Always sample errors and slow requests

**Instrumentation:**
- HTTP/gRPC boundaries
- Database queries
- External API calls
- Important business logic

## Performance Impact

### Metrics Collection

| Component | CPU | Memory | Network |
|-----------|-----|--------|---------|
| Prometheus | 2 cores | 8Gi | 50 KB/s |
| Grafana | 0.5 core | 1Gi | 10 KB/s |
| DCGM Exporter | 0.1 core | 128Mi | 5 KB/s |

**Application overhead:**
- Metrics: < 1% CPU (scrape every 15s)

### Distributed Tracing

| Component | CPU | Memory | Network |
|-----------|-----|--------|---------|
| OTEL Collector | 1 core | 2Gi | 1 MB/s |
| Jaeger | 2 cores | 4Gi | 500 KB/s |

**Application overhead:**
- Tracing: 2-5% CPU (with 10% sampling)
- Latency: < 1ms per trace

## Common Pitfalls

### 1. Not Setting Prometheus Retention

**Mistake:** Using default 15 day retention for production.

**Impact:** Historical data lost, can't investigate week-old incidents.

**Solution:**
```bash
# Set 30-90 day retention
helm install prometheus prometheus-community/kube-prometheus-stack \
  --set prometheus.prometheusSpec.retention=90d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=1Ti
```

**Cost:** ~$100/month for 1Ti SSD storage (3-month retention).

### 2. Too Many Alerts (Alert Fatigue)

**Mistake:**
```yaml
# Alert on every error
- alert: AnyError
  expr: rate(http_requests_total{status="500"}[5m]) > 0  # ❌ Too sensitive!
```

**Impact:** Team ignores alerts, miss critical issues.

**Solution:**
```yaml
# Alert on sustained error rate
- alert: HighErrorRate
  expr: |
    rate(http_requests_total{status=~"5.."}[5m])
    / rate(http_requests_total[5m]) > 0.01  # 1% error rate
  for: 10m  # Must persist for 10 minutes
  labels:
    severity: warning
```

**Rule:** < 10 alerts/day, use `for:` duration to avoid flapping.

### 3. Missing ServiceMonitor Labels

**Mistake:**
```yaml
# ServiceMonitor can't find pods
spec:
  selector:
    matchLabels:
      app: my-model  # ❌ Pod has different label!
```

**Impact:** No metrics collected from pods.

**Solution:**
```bash
# Check pod labels
kubectl get pods -n ml-serving --show-labels

# Match labels exactly
spec:
  selector:
    matchLabels:
      serving.kserve.io/inferenceservice: pytorch-resnet  # ✓ Correct label
```

### 4. Not Instrumenting Custom Metrics

**Mistake:** Only using default Kubernetes metrics.

**Impact:** Can't track ML-specific metrics (accuracy, drift, predictions/sec).

**Solution:**
```python
from prometheus_client import Counter, Histogram, Gauge
import time

# Define metrics
prediction_counter = Counter('ml_predictions_total', 'Total predictions', ['model', 'version'])
prediction_latency = Histogram('ml_prediction_duration_seconds', 'Prediction latency')
model_accuracy = Gauge('ml_model_accuracy', 'Model accuracy', ['model'])

@app.route('/predict')
def predict():
    start = time.time()

    # Your inference code
    result = model.predict(data)

    # Record metrics
    prediction_counter.labels(model='resnet50', version='v1.0.0').inc()
    prediction_latency.observe(time.time() - start)
    model_accuracy.labels(model='resnet50').set(0.95)

    return result

# Expose metrics endpoint
@app.route('/metrics')
def metrics():
    return prometheus_client.generate_latest()
```

### 5. Wrong Scrape Interval

**Mistake:**
```yaml
endpoints:
  - port: metrics
    interval: 1s  # ❌ Too frequent!
```

**Impact:** High Prometheus CPU/memory usage, storage fills up quickly.

**Solution:**
```yaml
# Production: 15-30 seconds
endpoints:
  - port: metrics
    interval: 15s  # ✓ Good balance

# High-frequency metrics: 5 seconds (rare)
# Low-frequency metrics: 60 seconds (cost tracking)
```

**Guideline:**
- Infrastructure: 15s
- Application: 15-30s
- Cost/billing: 60s

### 6. Not Configuring AlertManager Routes

**Mistake:** All alerts go to same Slack channel.

**Impact:** Noisy channel, critical alerts buried.

**Solution:**
```yaml
route:
  receiver: default
  group_by: [alertname, cluster]
  routes:
    # Critical to PagerDuty
    - match:
        severity: critical
      receiver: pagerduty
      group_wait: 10s
      group_interval: 5m

    # Warnings to Slack
    - match:
        severity: warning
      receiver: slack-warnings
      group_interval: 10m

    # Training job alerts to ML team
    - match_re:
        alertname: Training.*
      receiver: slack-ml-team
```

### 7. Tracing Everything (100% Sampling)

**Mistake:**
```python
# Sample 100% of requests
sampler = TraceIdRatioBased(1.0)  # ❌ High overhead!
```

**Impact:** 5-10% CPU overhead, storage costs skyrocket.

**Solution:**
```python
# Production: 1-10% sampling
sampler = TraceIdRatioBased(0.1)  # 10% sampling

# Always trace errors and slow requests
def should_sample(context):
    if context.response_time_ms > 500:  # Slow request
        return True
    if context.status_code >= 500:  # Error
        return True
    return random.random() < 0.1  # 10% random
```

### 8. No Grafana Dashboard Organization

**Mistake:** All 20 dashboards in root folder, no structure.

**Impact:** Can't find dashboards, duplicates created.

**Solution:**
```bash
# Create folder structure
curl -X POST http://admin:admin@localhost:3000/api/folders \
  -H "Content-Type: application/json" \
  -d '{
    "title": "ML Platform",
    "uid": "ml-platform"
  }'

# Organize dashboards:
# ML Platform/
#   ├── Overview
#   ├── Training/
#   │   ├── GPU Utilization
#   │   └── Job Status
#   └── Serving/
#       ├── Request Rate
#       └── Latency
```

### 9. Ignoring Cardinality Explosion

**Mistake:**
```python
# High-cardinality label
prediction_counter.labels(
    model='resnet50',
    user_id='user-12345',  # ❌ Unique per user!
    request_id='req-abc'   # ❌ Unique per request!
).inc()
```

**Impact:** Prometheus OOM, queries slow down.

**Solution:**
```python
# Use low-cardinality labels only
prediction_counter.labels(
    model='resnet50',      # ✓ Low cardinality (~10 models)
    version='v1.0.0',      # ✓ Low cardinality (~5 versions)
    endpoint='/predict'    # ✓ Low cardinality (~20 endpoints)
).inc()

# For high-cardinality data, use logs/traces instead
logger.info(f"Prediction for user {user_id}, request {request_id}")
```

**Rule:** Keep label cardinality < 100 per metric.

### 10. Not Testing Alerts

**Mistake:** Deploy alert rules without testing.

**Impact:** Alerts never fire or fire incorrectly.

**Solution:**
```bash
# Test alert rule with promtool
promtool check rules prometheus-rules.yaml

# Simulate alert condition
# Option 1: Create failing pod
kubectl run test-fail --image=invalid-image

# Option 2: Use amtool to manually fire alert
amtool alert add alertname=TestAlert severity=critical

# Verify in AlertManager UI
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
# Check http://localhost:9093

# Verify Slack notification received
```

---

## Next Steps

- [Cost Attribution with OpenCost](06-cost-attribution.md)
- [Security & Governance](07-security.md)
- [CI/CD Automation](08-cicd.md)

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [OpenTelemetry](https://opentelemetry.io/docs/)
