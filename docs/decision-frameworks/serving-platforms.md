# Serving Platforms: KServe vs KAITO

## Executive Summary

**TL;DR:**
- **KAITO:** Simplified LLM deployment (Llama, Phi, Mistral) - one YAML, OpenAI-compatible API, auto GPU provisioning
- **KServe:** Production-grade model serving for all frameworks (PyTorch, TensorFlow, sklearn, LLMs) - advanced features, more configuration

**Use both:** KAITO for quick LLM prototypes, KServe for production multi-model serving.

---

## Quick Comparison

| Feature | KAITO | KServe |
|---------|-------|--------|
| **CNCF Status** | Sandbox (Oct 2024) | Incubating (Promoted Sept 2025) |
| **Primary Use Case** | LLM inference | General model serving |
| **Supported Models** | Pre-packaged LLMs only | Any model (custom containers) |
| **Complexity** | Low (1 YAML) | Medium (InferenceService + config) |
| **GPU Provisioning** | ✓ Automatic | Manual (via Karpenter) |
| **Multi-Model Serving** | ✗ One model per workspace | ✓ Multiple models per GPU |
| **Autoscaling** | Basic (HPA) | Advanced (KEDA integration) |
| **Canary Deployments** | ✗ No | ✓ Yes (via Gateway API) |
| **Custom Runtimes** | ✗ Pre-defined only | ✓ Bring your own container |
| **OpenAI API Compatibility** | ✓ Built-in | ✓ Via vLLM runtime |
| **Production Maturity** | Early (6 months in CNCF) | Production (3+ years) |
| **Learning Curve** | Easy (30 minutes) | Moderate (2-4 hours) |

---

## KAITO: Simplified LLM Deployment

### What is KAITO?

**Kubernetes AI Toolchain Operator** - Simplifies LLM deployment with pre-configured workspaces for popular models.

### When to Use KAITO

✓ **Quick LLM Prototyping**
- Need Llama-2, Phi, or Mistral running in <5 minutes
- Exploring different LLM models
- Proof-of-concept demos

✓ **Simple LLM Inference**
- Single LLM per endpoint
- Standard OpenAI-compatible API
- No custom preprocessing needed

✓ **Auto GPU Provisioning**
- Want KAITO to handle GPU node creation
- Don't want to manage Karpenter manually
- Rapid dev/test iterations

### When NOT to Use KAITO

✗ **Custom Models**
- Fine-tuned models not in KAITO registry
- Custom model architectures
- Non-LLM models (sklearn, XGBoost, etc.)

✗ **Multi-Model Serving**
- Need to serve 10 models on 1 GPU
- Model AB testing
- Canary deployments

✗ **Advanced Features**
- Custom preprocessing pipelines
- Model ensembles
- Explainability integrations

### KAITO Example: Deploy Llama-2 in 1 YAML

```yaml
apiVersion: kaito.sh/v1alpha1
kind: Workspace
metadata:
  name: llama2-workspace
spec:
  # Model selection
  resource:
    instanceType: "Standard_NC6s_v3"  # Azure (or AWS p3.2xlarge)
    labelSelector:
      matchLabels:
        apps: llama2

  # Model configuration
  inference:
    preset:
      name: "llama-2-7b"  # Pre-packaged model
      # Also available: llama-2-13b, llama-2-70b

  # Tuning (optional)
  tuning:
    method: "qlora"  # Quantized LoRA fine-tuning
    input: "s3://my-bucket/training-data"
```

**Deploy:**
```bash
kubectl apply -f kaito-llama2.yaml

# KAITO automatically:
# 1. Provisions GPU node (if needed)
# 2. Downloads Llama-2 weights
# 3. Starts inference server
# 4. Exposes OpenAI-compatible API
```

**Use:**
```bash
# Get service endpoint
kubectl get svc -l app=llama2-workspace

# Call OpenAI-compatible API
curl http://<endpoint>/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-2-7b",
    "prompt": "Explain Kubernetes in simple terms:",
    "max_tokens": 100
  }'
```

**Total Setup Time:** 5 minutes (vs 30+ minutes with manual KServe setup)

---

## KServe: Production Model Serving

### What is KServe?

**Cloud-native model serving platform** on Kubernetes with advanced features for production deployments.

### When to Use KServe

✓ **Production Model Serving**
- SLA requirements (99.9% uptime)
- Canary deployments (10% → 50% → 100%)
- Multi-model serving (cost optimization)

✓ **Any ML Framework**
- PyTorch, TensorFlow, scikit-learn, XGBoost
- Custom models with custom preprocessing
- LLMs with advanced configurations

✓ **Advanced Features**
- Model explainability (Shapley values)
- Outlier detection
- Model monitoring integration

✓ **Multi-Tenant Serving**
- Serve models for multiple teams
- Resource isolation per model
- Cost attribution per model

### KServe Example: Deploy PyTorch Model

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: pytorch-model
spec:
  predictor:
    pytorch:
      storageUri: "s3://my-bucket/models/resnet50"
      resources:
        requests:
          cpu: "1"
          memory: "4Gi"
          nvidia.com/gpu: "1"
        limits:
          cpu: "1"
          memory: "4Gi"
          nvidia.com/gpu: "1"
      env:
        - name: STORAGE_URI
          value: "s3://my-bucket/models/resnet50"
```

**Deploy:**
```bash
kubectl apply -f kserve-pytorch.yaml

# KServe creates:
# - Predictor pod (model inference)
# - Transformer pod (preprocessing, optional)
# - Explainer pod (explainability, optional)
# - Istio VirtualService (routing)
```

### KServe Example: LLM with vLLM Runtime

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: llama2-vllm
spec:
  predictor:
    model:
      modelFormat:
        name: vllm
      runtime: kserve-vllm
      storageUri: "s3://my-bucket/models/llama-2-7b-hf"
      resources:
        limits:
          nvidia.com/gpu: "1"
      args:
        - --model=/mnt/models
        - --tensor-parallel-size=1
        - --gpu-memory-utilization=0.9
        - --max-model-len=4096
```

**Advantages over KAITO:**
- Custom vLLM arguments (memory utilization, max length)
- Canary deployments
- Model monitoring integration
- Multi-model serving (10 LLMs on 1 GPU)

---

## Feature-by-Feature Comparison

### 1. Model Support

| Framework | KAITO | KServe |
|-----------|-------|--------|
| **LLMs** | ✓ Llama, Phi, Mistral (pre-packaged) | ✓ Any LLM (custom container) |
| **PyTorch** | ✗ LLMs only | ✓ Yes |
| **TensorFlow** | ✗ No | ✓ Yes |
| **sklearn** | ✗ No | ✓ Yes |
| **XGBoost** | ✗ No | ✓ Yes |
| **Custom** | ✗ No | ✓ Yes (custom runtime) |

**Winner:** KServe (supports all frameworks)

### 2. Deployment Simplicity

**KAITO (1 YAML, 10 lines):**
```yaml
apiVersion: kaito.sh/v1alpha1
kind: Workspace
metadata:
  name: phi-workspace
spec:
  inference:
    preset:
      name: "phi-2"  # Done!
```

**KServe (1 YAML, 20+ lines):**
```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: phi-model
spec:
  predictor:
    model:
      modelFormat:
        name: vllm
      runtime: kserve-vllm
      storageUri: "s3://bucket/phi-2"
      resources:
        limits:
          nvidia.com/gpu: "1"
      args:
        - --model=/mnt/models
```

**Winner:** KAITO (simpler for LLMs)

### 3. Multi-Model Serving

**KAITO:**
- ✗ One model per Workspace
- ✗ Cannot share GPU across models

**KServe with ModelMesh:**
```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: model-1
  annotations:
    serving.kserve.io/deploymentMode: ModelMesh  # Enable multi-model
---
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: model-2
  annotations:
    serving.kserve.io/deploymentMode: ModelMesh  # Share GPU with model-1
```

**Result:** 10 models on 1 GPU, each served independently.

**Winner:** KServe (essential for cost optimization)

### 4. Canary Deployments

**KAITO:**
- ✗ No built-in canary support
- Must use separate Workspaces + manual traffic splitting

**KServe:**
```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: model
spec:
  predictor:
    canaryTrafficPercent: 10  # 10% traffic to new version
    pytorch:
      storageUri: "s3://bucket/model-v2"  # New version
```

**Gradually increase:**
```bash
kubectl patch isvc model --type merge -p '{"spec":{"predictor":{"canaryTrafficPercent":50}}}'  # 50%
kubectl patch isvc model --type merge -p '{"spec":{"predictor":{"canaryTrafficPercent":100}}}' # 100%
```

**Winner:** KServe (production requirement)

### 5. Autoscaling

**KAITO:**
- Basic HPA (Horizontal Pod Autoscaler)
- Scales on CPU/memory only

**KServe + KEDA:**
```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: kserve-scaler
spec:
  scaleTargetRef:
    name: pytorch-model-predictor
  minReplicaCount: 0  # Scale to zero
  maxReplicaCount: 10
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://prometheus:9090
        metricName: http_requests_per_second
        threshold: '100'
        query: sum(rate(http_requests_total{service="pytorch-model"}[1m]))
```

**Winner:** KServe + KEDA (scale-to-zero, custom metrics)

### 6. Cost Per Request

**Test:** Llama-2-7B inference, 1M requests/month

**KAITO:**
- 1 Workspace = 1 GPU dedicated
- g4dn.xlarge (T4): $0.526/hour × 730 hours = **$384/month**
- Cost per 1M requests: **$384**

**KServe with ModelMesh:**
- 10 LLMs on 1 GPU (multi-model serving)
- g4dn.xlarge: $0.526/hour × 730 hours = $384/month
- Cost per 1M requests (amortized): **$38.40** (10x cheaper)

**Winner:** KServe (90% cost reduction via multi-model serving)

---

## Migration Path: KAITO → KServe

### Why Migrate?

1. **Need canary deployments** (production requirement)
2. **Multi-model serving** (cost optimization)
3. **Custom model** (not in KAITO registry)
4. **Advanced monitoring** (Prometheus/Grafana integration)

### Migration Steps

**Step 1: Export Model from KAITO**

```bash
# KAITO stores model in pod filesystem
kubectl exec -n kaito-workspace <pod-name> -- tar czf /tmp/model.tar.gz /workspace/models/llama-2-7b

# Copy to S3/storage
kubectl cp kaito-workspace/<pod-name>:/tmp/model.tar.gz ./model.tar.gz
aws s3 cp model.tar.gz s3://my-bucket/models/llama-2-7b.tar.gz
```

**Step 2: Create KServe InferenceService**

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: llama2-kserve
spec:
  predictor:
    model:
      modelFormat:
        name: vllm
      runtime: kserve-vllm
      storageUri: "s3://my-bucket/models/llama-2-7b"
      resources:
        limits:
          nvidia.com/gpu: "1"
```

**Step 3: Test Parity**

```bash
# KAITO endpoint
curl http://kaito-workspace-svc/v1/completions -d '{"prompt":"test"}'

# KServe endpoint
curl http://llama2-kserve.default.svc.cluster.local/v1/completions -d '{"prompt":"test"}'

# Compare outputs
```

**Step 4: Traffic Cutover**

```yaml
# Use Gateway API to shift traffic
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: llm-route
spec:
  parentRefs:
    - name: gateway
  rules:
    - backendRefs:
        - name: kaito-workspace-svc
          weight: 50  # 50% to KAITO
        - name: llama2-kserve
          weight: 50  # 50% to KServe
```

Gradually increase KServe weight: 50% → 75% → 100%

**Step 5: Decommission KAITO**

```bash
kubectl delete workspace llama2-workspace
```

---

## Decision Matrix

| Your Scenario | Recommendation |
|---------------|---------------|
| **Quick LLM prototype (Llama, Phi, Mistral)** | ✓ KAITO |
| **Production LLM serving (1 model)** | KServe (canary support) |
| **Serve 10+ LLMs cost-effectively** | ✓ KServe (multi-model) |
| **Custom fine-tuned LLM** | ✓ KServe (KAITO limited to presets) |
| **Non-LLM models (sklearn, PyTorch)** | ✓ KServe (KAITO LLM-only) |
| **Need canary deployments** | ✓ KServe (KAITO lacks) |
| **Auto GPU provisioning required** | KAITO (built-in) or KServe + Karpenter |
| **Scale-to-zero for cost savings** | ✓ KServe + KEDA |
| **Multi-tenant serving platform** | ✓ KServe (namespace isolation) |

---

## Best Practice: Use Both

### Pattern: KAITO for Prototyping, KServe for Production

**Week 1 (Prototyping):**
```bash
# Deploy Llama-2 with KAITO for quick testing
kubectl apply -f kaito-llama2.yaml
# Test in 5 minutes
```

**Week 2-3 (Development):**
```bash
# Fine-tune model
# Evaluate performance
# Build application
```

**Week 4 (Production):**
```bash
# Migrate to KServe for production features
kubectl apply -f kserve-llama2-production.yaml
# Enable canary deployments
# Add monitoring
# Multi-model serving optimization
```

**Result:**
- Fast time-to-prototype (KAITO)
- Production-grade serving (KServe)
- Cost optimization (KServe multi-model)

---

## Cost Comparison Summary

**Scenario:** 5 LLMs deployed for 1 month

### KAITO (5 Workspaces)
- 5 Workspaces × 1 GPU each = 5 GPUs
- g4dn.xlarge: $0.526/hour
- Cost: 5 × $0.526 × 730 = **$1,920/month**

### KServe (Multi-Model)
- 5 LLMs on 1 GPU (ModelMesh)
- g4dn.xlarge: $0.526/hour
- Cost: 1 × $0.526 × 730 = **$384/month**

**Savings:** $1,536/month (80%)

---

## Next Steps

- **KAITO Quick Start:** [components/02-training/kaito/](../../components/02-training/kaito/)
- **KServe Installation:** [components/04-model-serving/kserve/](../../components/04-model-serving/kserve/)
- **LLM Serving Examples:** [components/04-model-serving/examples/](../../components/04-model-serving/examples/)
- **Cost Optimization:** [cost-analysis/optimization/optimization-checklist.md](../../cost-analysis/optimization/optimization-checklist.md)
