# Model Serving

Serverless inference with autoscaling, canary deployments, and GPU support using KServe.

## Overview

KServe provides production-ready model serving with unified APIs for multiple ML frameworks, automatic scaling, and advanced deployment strategies.

### Components

1. **KServe** (CNCF Incubating)
   - Unified serving API for PyTorch, TensorFlow, ONNX, Hugging Face
   - Multi-framework support with custom runtimes
   - Inference protocol v2 (compatible with Triton, TorchServe)
   - Built-in explainability and outlier detection

2. **Knative Serving**
   - Serverless runtime for Kubernetes
   - Scale-to-zero (80% cost savings)
   - Request-driven autoscaling
   - Revision-based rollouts

3. **Istio**
   - Service mesh for traffic management
   - Canary deployments with traffic splitting
   - Mutual TLS between services
   - Observability (traces, metrics, logs)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     KServe Architecture                      │
└─────────────────────────────────────────────────────────────┘

Client Request            KServe Stack              Model Storage
┌──────────┐             ┌──────────────┐          ┌──────────────┐
│  User /  │──predict───▶│   Istio      │          │ Harbor / S3  │
│   App    │             │  (routing)   │          │              │
└──────────┘             └──────┬───────┘          │  Model       │
                                │                  │  Artifacts   │
                         ┌──────▼──────┐           │              │
                         │  Knative    │◀──pull───│  - PyTorch   │
                         │  Serving    │           │  - TensorFlow│
                         │ (serverless)│           │  - ONNX      │
                         └──────┬──────┘           └──────────────┘
                                │
                  ┌─────────────┴─────────────┐
                  │                           │
           ┌──────▼──────┐           ┌───────▼──────┐
           │ InferenceService        │ InferenceService
           │  resnet50    │           │  bert-base   │
           │              │           │              │
           │ - Autoscale  │           │ - Autoscale  │
           │ - GPU: 1     │           │ - Scale-to-0 │
           │ - Min: 2     │           │ - Min: 0     │
           └──────────────┘           └──────────────┘
```

## Quick Start

### Prerequisites

- Kubernetes 1.28+
- kubectl with admin access
- 500Gi storage for models
- NVIDIA GPU nodes (optional, for GPU models)

### Installation

#### 1. Install Istio

```bash
# Download Istio
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.2 sh -
cd istio-1.20.2

# Install Istio
export PATH=$PWD/bin:$PATH
istioctl install --set profile=default -y

# Enable sidecar injection
kubectl label namespace default istio-injection=enabled

# Verify
kubectl get pods -n istio-system
```

#### 2. Install Knative Serving

```bash
KNATIVE_VERSION="1.12.0"

# Install CRDs
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v${KNATIVE_VERSION}/serving-crds.yaml

# Install core components
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v${KNATIVE_VERSION}/serving-core.yaml

# Install Istio networking
kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v${KNATIVE_VERSION}/net-istio.yaml

# Verify
kubectl get pods -n knative-serving
```

#### 3. Install Cert-Manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Wait for ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/component=webhook \
  -n cert-manager \
  --timeout=5m
```

#### 4. Install KServe

```bash
KSERVE_VERSION="v0.12.0"

# Install KServe
kubectl apply -f https://github.com/kserve/kserve/releases/download/${KSERVE_VERSION}/kserve.yaml

# Install serving runtimes
kubectl apply -f https://github.com/kserve/kserve/releases/download/${KSERVE_VERSION}/kserve-runtimes.yaml

# Wait for ready
kubectl wait --for=condition=ready pod \
  -l control-plane=kserve-controller-manager \
  -n kserve \
  --timeout=5m
```

### Deploy Your First Model

#### 1. Create Namespace

```bash
kubectl create namespace ml-serving
```

#### 2. Configure Storage Credentials

For Harbor:
```bash
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=harbor.ml-platform.example.com \
  --docker-username=admin \
  --docker-password=<password> \
  --namespace=ml-serving
```

For S3:
```bash
kubectl create secret generic s3-credentials \
  --from-literal=AWS_ACCESS_KEY_ID=<key> \
  --from-literal=AWS_SECRET_ACCESS_KEY=<secret> \
  --namespace=ml-serving
```

#### 3. Create ServiceAccount

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kserve-sa
  namespace: ml-serving
secrets:
  - name: harbor-registry-secret
  - name: s3-credentials
EOF
```

#### 4. Deploy PyTorch Model

```bash
cat <<EOF | kubectl apply -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: pytorch-resnet
  namespace: ml-serving
spec:
  predictor:
    serviceAccountName: kserve-sa
    pytorch:
      storageUri: s3://ml-models/pytorch/resnet50
      resources:
        requests:
          cpu: "1"
          memory: "2Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
EOF
```

#### 5. Wait for Model Ready

```bash
kubectl wait --for=condition=ready \
  inferenceservice pytorch-resnet \
  -n ml-serving \
  --timeout=5m

# Check status
kubectl get inferenceservice pytorch-resnet -n ml-serving
```

#### 6. Test Inference

```bash
# Get InferenceService URL
export SERVICE_URL=$(kubectl get inferenceservice pytorch-resnet \
  -n ml-serving \
  -o jsonpath='{.status.url}')

# Send prediction request
curl -H "Content-Type: application/json" \
  $SERVICE_URL/v1/models/pytorch-resnet:predict \
  -d '{
    "instances": [
      [1.0, 2.0, 3.0, 4.0]
    ]
  }'
```

## Features

### 1. GPU Model Serving

Deploy models with full or fractional GPU allocation:

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: llama2-7b
  namespace: ml-serving
  annotations:
    autoscaling.knative.dev/minScale: "1"
    autoscaling.knative.dev/maxScale: "5"
    autoscaling.knative.dev/target: "10"  # Low concurrency for LLM
spec:
  predictor:
    serviceAccountName: kserve-sa
    pytorch:
      storageUri: oci://harbor.ml-platform.example.com/ml-models/llama2-7b:1.0.0
      resources:
        requests:
          cpu: "4"
          memory: "16Gi"
        limits:
          cpu: "8"
          memory: "32Gi"
          nvidia.com/gpu: "1"
      nodeSelector:
        accelerator: nvidia-tesla-t4
```

### 2. Autoscaling Strategies

#### Scale-to-Zero (Cost Optimization)

```yaml
metadata:
  annotations:
    autoscaling.knative.dev/minScale: "0"   # Scale to zero
    autoscaling.knative.dev/maxScale: "10"
    autoscaling.knative.dev/scale-down-delay: "60s"
```

**Cost savings:**
- Without scale-to-zero: $360/month (24/7)
- With scale-to-zero (20% utilization): $72/month
- **Savings: 80%**

#### Always-Warm (Low Latency)

```yaml
metadata:
  annotations:
    autoscaling.knative.dev/minScale: "3"   # Always 3 replicas
    autoscaling.knative.dev/maxScale: "20"
    autoscaling.knative.dev/target: "100"   # Target 100 concurrent requests
```

### 3. Canary Deployment

Deploy new model version with gradual traffic shifting:

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: fraud-detection
  namespace: ml-serving
spec:
  # Default predictor (90% traffic)
  predictor:
    pytorch:
      storageUri: s3://ml-models/fraud-detection:v1.0.0
      resources:
        requests:
          cpu: "2"
          memory: "4Gi"
        limits:
          cpu: "4"
          memory: "8Gi"

  # Canary predictor (10% traffic)
  canary:
    pytorch:
      storageUri: s3://ml-models/fraud-detection:v2.0.0
      resources:
        requests:
          cpu: "2"
          memory: "4Gi"
        limits:
          cpu: "4"
          memory: "8Gi"
    canaryTrafficPercent: 10
```

#### Gradual Promotion

```bash
# Start with 10%
kubectl patch inferenceservice fraud-detection -n ml-serving \
  --type merge \
  -p '{"spec":{"canary":{"canaryTrafficPercent":10}}}'

# Monitor metrics, then increase
kubectl patch inferenceservice fraud-detection -n ml-serving \
  --type merge \
  -p '{"spec":{"canary":{"canaryTrafficPercent":25}}}'

# Full promotion
kubectl patch inferenceservice fraud-detection -n ml-serving \
  --type merge \
  -p '{"spec":{"canary":{"canaryTrafficPercent":100}}}'

# Rollback if needed
kubectl patch inferenceservice fraud-detection -n ml-serving \
  --type merge \
  -p '{"spec":{"canary":null}}'
```

### 4. Multi-Model Serving

Serve multiple models from one pod (model batching):

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: multi-model-server
  namespace: ml-serving
spec:
  predictor:
    model:
      modelFormat:
        name: triton
      runtime: kserve-tritonserver
      storageUri: s3://ml-models/triton-models/
      resources:
        requests:
          cpu: "4"
          memory: "8Gi"
          nvidia.com/gpu: "1"
        limits:
          cpu: "8"
          memory: "16Gi"
          nvidia.com/gpu: "1"
```

Model repository structure:
```
s3://ml-models/triton-models/
├── model-a/
│   ├── config.pbtxt
│   └── 1/model.pt
├── model-b/
│   ├── config.pbtxt
│   └── 1/model.onnx
└── model-c/
    ├── config.pbtxt
    └── 1/model.plan
```

### 5. Transformer (Pre/Post Processing)

Add custom pre/post-processing:

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: sklearn-iris
  namespace: ml-serving
spec:
  predictor:
    sklearn:
      storageUri: s3://ml-models/sklearn/iris
  transformer:
    containers:
      - name: transformer
        image: my-transformer:latest
        command:
          - "python"
          - "-m"
          - "transformer"
        env:
          - name: STORAGE_URI
            value: s3://ml-models/sklearn/iris
```

## Supported Frameworks

| Framework | Runtime | Example |
|-----------|---------|---------|
| PyTorch | TorchServe | `pytorch: storageUri: s3://...` |
| TensorFlow | TensorFlow Serving | `tensorflow: storageUri: s3://...` |
| Scikit-learn | SKLearn Server | `sklearn: storageUri: s3://...` |
| XGBoost | XGBoost Server | `xgboost: storageUri: s3://...` |
| ONNX | ONNX Runtime | `onnx: storageUri: s3://...` |
| Hugging Face | Hugging Face Server | `huggingface: storageUri: s3://...` |
| Custom | Custom Container | `containers: - image: my-server` |

## Monitoring

### Request Metrics

```bash
# Request rate
kubectl exec -it -n knative-serving <prometheus-pod> -- promtool query instant \
  'rate(revision_app_request_count{namespace="ml-serving"}[5m])'

# Latency P99
kubectl exec -it -n knative-serving <prometheus-pod> -- promtool query instant \
  'histogram_quantile(0.99, rate(revision_app_request_latencies_bucket{namespace="ml-serving"}[5m]))'

# Error rate
kubectl exec -it -n knative-serving <prometheus-pod> -- promtool query instant \
  'rate(revision_app_request_count{namespace="ml-serving",response_code_class="5xx"}[5m])'
```

### Grafana Dashboards

Pre-built dashboards available:

1. **KServe Overview**
   - InferenceService status
   - Request rate, latency, errors
   - Autoscaling metrics
   - Resource utilization

2. **Model Performance**
   - Per-model latency
   - Per-model throughput
   - Error rates by model
   - Canary comparison

3. **Cost Analysis**
   - Request cost ($/1000 requests)
   - Idle time (scale-to-zero)
   - GPU utilization
   - Potential savings

## Performance Tuning

### Latency Optimization

```yaml
# 1. Keep replicas warm
metadata:
  annotations:
    autoscaling.knative.dev/minScale: "2"

# 2. Use PVC instead of S3 for faster model loading
spec:
  predictor:
    pytorch:
      storageUri: pvc://ml-models-pvc/resnet50

# 3. Enable model caching
spec:
  predictor:
    pytorch:
      storageUri: s3://ml-models/resnet50
      modelCache:
        enabled: true
```

### Throughput Optimization

```yaml
# 1. Increase max replicas
metadata:
  annotations:
    autoscaling.knative.dev/maxScale: "50"

# 2. Tune concurrency target
metadata:
  annotations:
    autoscaling.knative.dev/target: "100"

# 3. Enable request batching (if supported by runtime)
spec:
  predictor:
    pytorch:
      args:
        - --batch_size=32
        - --max_batch_delay=100  # ms
```

### GPU Utilization

```yaml
# 1. Use full GPU for large models
resources:
  limits:
    nvidia.com/gpu: "1"

# 2. Use fractional GPU for small models (with HAMi)
resources:
  limits:
    nvidia.com/gpumem: "4096"  # 4GB GPU memory
    nvidia.com/gpucores: "50"  # 50% GPU cores

# 3. Multi-model serving on single GPU
# Use Triton with multiple models
```

## Troubleshooting

### Model Not Ready

```bash
# Check InferenceService status
kubectl describe inferenceservice <name> -n ml-serving

# Check pod events
kubectl get events -n ml-serving --sort-by='.lastTimestamp'

# Check pod logs
kubectl logs -n ml-serving -l serving.kserve.io/inferenceservice=<name>

# Common causes:
# - Storage URI incorrect → Fix storageUri
# - Credentials missing → Check ServiceAccount secrets
# - Insufficient resources → Increase resource limits
# - Image pull errors → Check registry credentials
```

### High Latency

```bash
# Check replica count
kubectl get pods -n ml-serving -l serving.kserve.io/inferenceservice=<name>

# If only 1 replica under load:
# 1. Increase maxScale
metadata:
  annotations:
    autoscaling.knative.dev/maxScale: "20"

# 2. Reduce target concurrency
metadata:
  annotations:
    autoscaling.knative.dev/target: "50"

# 3. Keep replicas warm
metadata:
  annotations:
    autoscaling.knative.dev/minScale: "3"
```

### Out of Memory (OOM)

```bash
# Solution 1: Increase memory limits
kubectl patch inferenceservice <name> -n ml-serving \
  --type merge \
  -p '{"spec":{"predictor":{"pytorch":{"resources":{"limits":{"memory":"16Gi"}}}}}}'

# Solution 2: Use model quantization
# Convert model to INT8/FP16 (reduces memory 2-4x)

# Solution 3: Use larger GPU
# A100 (80GB) instead of T4 (16GB)
```

### Cold Start Too Slow

```bash
# Solution 1: Set minScale > 0
metadata:
  annotations:
    autoscaling.knative.dev/minScale: "1"

# Solution 2: Use PVC instead of S3
spec:
  predictor:
    pytorch:
      storageUri: pvc://ml-models-pvc/model

# Solution 3: Pre-load models in custom image
# Build container with model baked in
```

## Best Practices

### 1. Resource Allocation

**CPU-only models:**
```yaml
resources:
  requests:
    cpu: "1-2"
    memory: "2-4Gi"
  limits:
    cpu: "2-4"
    memory: "4-8Gi"
```

**GPU models:**
```yaml
resources:
  requests:
    cpu: "4-8"      # Avoid CPU bottleneck
    memory: "16-32Gi"
  limits:
    cpu: "8-16"
    memory: "32-64Gi"
    nvidia.com/gpu: "1"
```

### 2. Autoscaling Strategy

**Development:**
- minScale: 0 (scale to zero)
- maxScale: 5
- Cost-optimized

**Production:**
- minScale: 2-3 (avoid cold starts)
- maxScale: 20-50
- Latency-optimized

### 3. Deployment Strategy

**Low-risk changes:**
- Canary: 10% → 25% → 50% → 100%
- Monitor for 5-10 minutes per step

**High-risk changes:**
- Shadow deployment first
- Then canary rollout
- Keep previous version for quick rollback

### 4. Storage

**Best options by use case:**
- **S3**: General purpose, large models, multi-region
- **Harbor OCI**: KitOps models, versioned, signed
- **PVC**: Fastest cold starts, shared models across pods
- **Baked-in**: Fastest startup, immutable deployments

## Performance Benchmarks

### Autoscaling Performance

| Metric | Value |
|--------|-------|
| Scale up (0 → 10 replicas) | 30 seconds |
| Scale down (10 → 1) | 60 seconds |
| Scale to zero | 60s after idle |
| Cold start (S3) | 5-10 seconds |
| Cold start (PVC) | 2-5 seconds |
| Cold start (baked-in) | 1-2 seconds |

### Request Latency

| Model Type | P50 Latency | P99 Latency |
|------------|-------------|-------------|
| MobileNet (CPU) | 45ms | 120ms |
| ResNet-50 (GPU) | 12ms | 35ms |
| BERT-base (GPU) | 25ms | 80ms |
| LLaMA-7B (GPU) | 1.2s | 2.5s |

## Component Documentation

- **KServe Installation**: [kserve/kserve-install.yaml](kserve/kserve-install.yaml)
- **Inference Examples**: [kserve/inference-examples.yaml](kserve/inference-examples.yaml)
- **Autoscaling Config**: [kserve/autoscaling-examples.yaml](kserve/autoscaling-examples.yaml)

## Tutorial

For a complete step-by-step tutorial, see:
[Model Serving with KServe Tutorial](../../docs/tutorials/04-model-serving.md)

## References

- [KServe Documentation](https://kserve.github.io/website/)
- [Knative Serving](https://knative.dev/docs/serving/)
- [Istio Traffic Management](https://istio.io/latest/docs/tasks/traffic-management/)
- [Inference Protocol v2](https://github.com/kserve/kserve/tree/master/docs/predict-api/v2)

---

[← Back: Model Registry](../03-model-registry/README.md) | [Components Overview](../README.md) | [Next: Observability →](../05-observability/README.md)
