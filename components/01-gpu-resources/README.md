# GPU Resources

GPU management, sharing, and scheduling for ML workloads using NVIDIA GPU Operator and HAMi.

## Overview

Efficient GPU utilization is critical for ML platforms. This component provides GPU device management, fractional GPU allocation, and multi-tenant GPU sharing to maximize resource utilization and reduce costs.

### Components

1. **NVIDIA GPU Operator**
   - Automated GPU driver installation
   - CUDA toolkit deployment
   - Device plugin for GPU discovery
   - DCGM metrics exporter
   - GPU Feature Discovery (GFD)

2. **HAMi (Heterogeneous AI Computing Virtualization Middleware)**
   - Fractional GPU allocation (vGPU)
   - GPU memory isolation
   - Multi-tenant GPU sharing
   - Fine-grained resource control
   - Oversubscription support

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     GPU Architecture                         │
└─────────────────────────────────────────────────────────────┘

ML Workloads              GPU Scheduling           Physical GPUs
┌──────────────┐         ┌──────────────────┐     ┌────────────┐
│ Training Job │         │   HAMi Plugin    │     │ Node 1     │
│ GPU: 0.5     │────────▶│                  │────▶│ GPU 0: A100│
│ GPUMem: 20GB │         │  Allocates:      │     │   80GB     │
└──────────────┘         │  - GPU cores     │     │            │
                         │  - GPU memory    │     │ GPU 1: A100│
┌──────────────┐         │  - Isolation     │     │   80GB     │
│ Serving Pod  │────────▶│                  │     └────────────┘
│ GPU: 0.25    │         └──────────────────┘     ┌────────────┐
│ GPUMem: 10GB │              ▲                   │ Node 2     │
└──────────────┘              │                   │ GPU 0: V100│
                              │                   │   32GB     │
                 ┌────────────┴──────────┐        └────────────┘
                 │ NVIDIA GPU Operator   │
                 │                       │
                 │ - GPU drivers         │
                 │ - CUDA toolkit        │
                 │ - Device plugin       │
                 │ - DCGM metrics        │
                 └───────────────────────┘
```

## Quick Start

### Prerequisites

- Kubernetes 1.28+
- NVIDIA GPU nodes (Tesla T4, V100, A100, H100, etc.)
- Node labels: `nvidia.com/gpu=true`
- kubectl with admin access

### Installation

#### 1. Install NVIDIA GPU Operator

```bash
# Add NVIDIA Helm repository
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# Install GPU Operator
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.enabled=true \
  --set toolkit.enabled=true \
  --set dcgmExporter.enabled=true \
  --set gfd.enabled=true \
  --wait

# Wait for all components
kubectl wait --for=condition=ready pod \
  -l app=nvidia-device-plugin-daemonset \
  -n gpu-operator \
  --timeout=10m

# Verify GPU discovery
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.capacity.nvidia\.com/gpu
```

#### 2. Install HAMi Device Plugin

```bash
# Install HAMi
kubectl apply -f https://raw.githubusercontent.com/Project-HAMi/HAMi/master/deployment/device-plugin-rbac.yaml
kubectl apply -f https://raw.githubusercontent.com/Project-HAMi/HAMi/master/deployment/device-plugin-daemonset.yaml

# Wait for HAMi pods
kubectl wait --for=condition=ready pod \
  -l app=hami-device-plugin \
  -n kube-system \
  --timeout=5m

# Verify HAMi resources
kubectl get nodes -o json | jq '.items[].status.capacity | keys | .[] | select(contains("hami"))'
```

### Verify Installation

```bash
# Check GPU Operator pods
kubectl get pods -n gpu-operator

# Expected output:
# gpu-feature-discovery-xxx    Running
# gpu-operator-xxx             Running
# nvidia-container-toolkit-xxx Running
# nvidia-dcgm-exporter-xxx     Running
# nvidia-device-plugin-xxx     Running
# nvidia-driver-daemonset-xxx  Running

# Check GPU capacity
kubectl describe node <gpu-node-name> | grep -A 10 "Capacity"

# Expected:
#   nvidia.com/gpu: 8
#   nvidia.com/gpumem: 640000    # HAMi: 8 GPUs * 80GB = 640GB
#   nvidia.com/gpucores: 800     # HAMi: 8 GPUs * 100 cores
```

## GPU Allocation Strategies

### 1. Full GPU Allocation (Traditional)

Allocate entire GPU to a single pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: training-full-gpu
spec:
  containers:
    - name: pytorch
      image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
      resources:
        limits:
          nvidia.com/gpu: 1  # Request 1 full GPU
```

**Use cases:**
- Large model training (LLMs, diffusion models)
- Maximum performance required
- GPU utilization > 80%

### 2. Fractional GPU Allocation (HAMi)

Share GPU across multiple pods:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: inference-fractional-gpu
spec:
  containers:
    - name: model-server
      image: my-model-server:latest
      resources:
        limits:
          nvidia.com/gpumem: 10000   # Request 10GB GPU memory
          nvidia.com/gpucores: 50     # Request 50% GPU cores
```

**Use cases:**
- Small model inference
- Batch processing
- Development/testing
- Cost optimization (50% cost reduction)

### 3. Multi-Instance GPU (MIG) - A100/H100

Partition single GPU into isolated instances:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: training-mig
spec:
  containers:
    - name: trainer
      image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
      resources:
        limits:
          nvidia.com/mig-1g.5gb: 1  # 1 MIG instance (1/7 of A100)
```

**MIG profiles (A100 80GB):**
- `mig-1g.5gb`: 1 instance, 5GB memory (7 per GPU)
- `mig-2g.10gb`: 1 instance, 10GB memory (3 per GPU)
- `mig-3g.20gb`: 1 instance, 20GB memory (2 per GPU)
- `mig-7g.40gb`: 1 instance, 40GB memory (1 per GPU)

**Use cases:**
- Guaranteed isolation
- Multi-tenant environments
- Compliance requirements

## GPU Sharing Examples

### Example 1: Mixed Workloads on Single GPU

```yaml
---
# Training job: Uses 50GB GPU memory, 70% cores
apiVersion: batch/v1
kind: Job
metadata:
  name: training-job
spec:
  template:
    spec:
      containers:
        - name: trainer
          image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
          command: ["python", "train.py"]
          resources:
            limits:
              nvidia.com/gpumem: 50000  # 50GB
              nvidia.com/gpucores: 70    # 70%
---
# Inference service: Uses 20GB GPU memory, 20% cores
apiVersion: v1
kind: Pod
metadata:
  name: inference-server
spec:
  containers:
    - name: server
      image: my-inference-server:latest
      resources:
        limits:
          nvidia.com/gpumem: 20000  # 20GB
          nvidia.com/gpucores: 20    # 20%
---
# Result: Both pods share same 80GB GPU
# Training: 50GB + 70% cores
# Inference: 20GB + 20% cores
# Remaining: 10GB + 10% cores available
```

### Example 2: Multi-Tenant GPU Allocation

```yaml
---
# Team A namespace with GPU quota
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-a-gpu-quota
  namespace: ml-team-a
spec:
  hard:
    requests.nvidia.com/gpumem: "80000"    # 80GB total
    requests.nvidia.com/gpucores: "200"     # 2 full GPUs worth of cores
---
# Team A pod
apiVersion: v1
kind: Pod
metadata:
  name: team-a-training
  namespace: ml-team-a
spec:
  containers:
    - name: trainer
      image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
      resources:
        requests:
          nvidia.com/gpumem: 40000   # Request 40GB
          nvidia.com/gpucores: 100    # Request 1 full GPU worth
        limits:
          nvidia.com/gpumem: 40000
          nvidia.com/gpucores: 100
```

### Example 3: Oversubscription for Inference

```yaml
---
# Allow GPU oversubscription (use with caution)
apiVersion: v1
kind: ConfigMap
metadata:
  name: hami-config
  namespace: kube-system
data:
  oversubscription: "true"  # Allow requesting more than physical capacity
---
# Deploy 10 inference pods on 2 GPUs
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-fleet
spec:
  replicas: 10  # 10 pods
  selector:
    matchLabels:
      app: inference
  template:
    metadata:
      labels:
        app: inference
    spec:
      containers:
        - name: server
          image: my-inference-server:latest
          resources:
            limits:
              nvidia.com/gpumem: 16000   # 16GB per pod
              nvidia.com/gpucores: 20     # 20% cores per pod
# Total requested: 10 pods * 16GB = 160GB (oversubscribed on 2x80GB GPUs)
# Works if pods don't use GPU simultaneously
```

## GPU Monitoring

### NVIDIA DCGM Metrics

DCGM Exporter provides Prometheus metrics:

```promql
# GPU utilization (%)
DCGM_FI_DEV_GPU_UTIL{gpu="0",UUID="GPU-xxx"}

# GPU memory usage (MB)
DCGM_FI_DEV_FB_USED{gpu="0"}

# GPU temperature (°C)
DCGM_FI_DEV_GPU_TEMP{gpu="0"}

# GPU power usage (W)
DCGM_FI_DEV_POWER_USAGE{gpu="0"}

# GPU memory utilization (%)
(DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL) * 100

# PCIe throughput (MB/s)
DCGM_FI_DEV_PCIE_TX_THROUGHPUT{gpu="0"}
DCGM_FI_DEV_PCIE_RX_THROUGHPUT{gpu="0"}
```

### HAMi Metrics

```promql
# GPU allocation per pod
hami_gpu_allocation{pod="training-job-xxx",node="gpu-node-1"}

# GPU memory allocated (MB)
hami_gpu_memory_allocated{pod="training-job-xxx"}

# GPU cores allocated (%)
hami_gpu_cores_allocated{pod="training-job-xxx"}
```

### Check GPU Utilization

```bash
# Real-time GPU monitoring
kubectl exec -it <gpu-pod> -- nvidia-smi

# Watch GPU utilization
kubectl exec -it <gpu-pod> -- watch -n 1 nvidia-smi

# DCGM metrics
kubectl exec -it -n gpu-operator <dcgm-pod> -- dcgmi dmon

# HAMi device info
kubectl exec -it -n kube-system <hami-pod> -- hami-device-plugin --device-info
```

## Performance Comparison

### Cost per Inference (1M requests)

| Configuration | GPUs Used | Cost | Cost/1M Requests |
|---------------|-----------|------|------------------|
| Full GPU (1 model) | 8 | $8,000/mo | $8.00 |
| HAMi 0.25 GPU (4 models) | 2 | $2,000/mo | $2.00 |
| MIG 1g.5gb (7 models) | 1.14 | $1,140/mo | $1.14 |
| **Savings** | **87%** | **$6,860** | **86%** |

### Training Performance

| Model | Full GPU | HAMi 0.5 GPU | MIG 3g.20gb |
|-------|----------|--------------|-------------|
| ResNet-50 | 1200 img/s | 600 img/s | 580 img/s |
| BERT-base | 850 seq/s | 425 seq/s | 410 seq/s |
| GPT-2 | 120 tok/s | 60 tok/s | 58 tok/s |

### Latency Impact

| Configuration | P50 Latency | P99 Latency |
|---------------|-------------|-------------|
| Full GPU | 12ms | 35ms |
| HAMi 0.5 GPU | 15ms | 45ms |
| HAMi 0.25 GPU | 25ms | 80ms |
| MIG 1g.5gb | 14ms | 40ms |

## Troubleshooting

### GPU Not Detected

```bash
# Check GPU Operator pods
kubectl get pods -n gpu-operator

# Check node labels
kubectl get nodes --show-labels | grep gpu

# Check GPU drivers
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset --tail=50

# Manually verify GPU on node
kubectl debug node/<node-name> -it --image=ubuntu
# Inside debug container:
lspci | grep -i nvidia
nvidia-smi
```

### HAMi Not Working

```bash
# Check HAMi daemonset
kubectl get ds -n kube-system hami-device-plugin

# Check HAMi logs
kubectl logs -n kube-system -l app=hami-device-plugin --tail=100

# Verify HAMi resources
kubectl describe node <gpu-node> | grep -E "nvidia.com/(gpumem|gpucores)"

# Common issues:
# - NVIDIA device plugin still running (conflict)
# - Node not labeled correctly
# - HAMi version incompatible with CUDA version
```

### Out of GPU Memory

```bash
# Check GPU memory allocation
kubectl describe node <gpu-node> | grep -A 20 "Allocated resources"

# Kill zombie GPU processes
kubectl exec -it <gpu-pod> -- nvidia-smi --gpu-reset -i 0

# Reduce memory request
# Option 1: Use smaller batch size
# Option 2: Use gradient checkpointing
# Option 3: Use mixed precision (FP16/BF16)
```

### Poor GPU Utilization

```bash
# Check if CPU-bound
kubectl top pod <pod-name>

# If CPU usage is high (>80%), increase CPU allocation:
resources:
  requests:
    cpu: "8"      # Increase from 4
    memory: "32Gi"

# Check if I/O-bound (data loading)
# Use faster storage or increase num_workers in DataLoader

# Enable profiling
# PyTorch: python -m torch.utils.bottleneck train.py
# TensorFlow: TF_CPP_MIN_LOG_LEVEL=0
```

## Best Practices

### 1. Right-Sizing GPU Allocation

```yaml
# ❌ Bad: Over-requesting
resources:
  limits:
    nvidia.com/gpu: 1  # Using only 30% of GPU

# ✅ Good: Use fractional GPU
resources:
  limits:
    nvidia.com/gpumem: 25000   # 25GB (30% of 80GB)
    nvidia.com/gpucores: 30     # 30% of cores
```

### 2. GPU Affinity and Topology

```yaml
# Pin pods to specific GPU type
spec:
  nodeSelector:
    accelerator: nvidia-tesla-a100  # Only schedule on A100 nodes

  # Or use affinity for mixed GPU types
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          preference:
            matchExpressions:
              - key: accelerator
                operator: In
                values:
                  - nvidia-tesla-a100
                  - nvidia-tesla-v100
```

### 3. GPU Node Pools

Separate node pools by GPU type:

```yaml
# Training pool (A100 - high performance)
nodeSelector:
  node-pool: training-a100

# Inference pool (T4 - cost effective)
nodeSelector:
  node-pool: inference-t4

# Development pool (Shared GPUs with HAMi)
nodeSelector:
  node-pool: dev-shared-gpu
```

### 4. Resource Quotas per Team

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ml-team-quota
  namespace: ml-team-a
spec:
  hard:
    # Limit total GPU resources
    requests.nvidia.com/gpu: "4"           # Max 4 full GPUs
    requests.nvidia.com/gpumem: "320000"   # Or 320GB GPU memory
    requests.nvidia.com/gpucores: "400"    # Or 4 GPUs worth of cores
    limits.nvidia.com/gpu: "4"
```

### 5. GPU Health Monitoring

```yaml
# Deploy GPU health check DaemonSet
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: gpu-health-check
spec:
  selector:
    matchLabels:
      app: gpu-health
  template:
    spec:
      nodeSelector:
        nvidia.com/gpu: "true"
      containers:
        - name: health-check
          image: nvidia/cuda:12.1.0-base-ubuntu22.04
          command:
            - sh
            - -c
            - |
              while true; do
                nvidia-smi --query-gpu=gpu_name,temperature.gpu,utilization.gpu,utilization.memory --format=csv,noheader
                sleep 60
              done
          resources:
            limits:
              nvidia.com/gpu: 1
```

## Integration with Training

### PyTorch with HAMi

```python
import torch

# PyTorch automatically detects GPU
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Using device: {device}")

# Check GPU memory allocation (respects HAMi limits)
print(f"GPU memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.2f} GB")

# Train model
model = MyModel().to(device)
```

### TensorFlow with GPU Memory Growth

```python
import tensorflow as tf

# Enable memory growth (important for HAMi)
gpus = tf.config.list_physical_devices('GPU')
for gpu in gpus:
    tf.config.experimental.set_memory_growth(gpu, True)

# TensorFlow respects HAMi memory limits
```

## Component Documentation

- **GPU Operator Installation**: [nvidia/gpu-operator-install.yaml](nvidia/gpu-operator-install.yaml)
- **HAMi Installation**: [hami/hami-install.yaml](hami/hami-install.yaml)
- **GPU Monitoring Setup**: [nvidia/dcgm-exporter-config.yaml](nvidia/dcgm-exporter-config.yaml)

## Tutorial

For a complete step-by-step tutorial, see:
[GPU Resource Management Tutorial](../../docs/tutorials/01-gpu-resources.md)

## References

- [NVIDIA GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [HAMi GitHub Repository](https://github.com/Project-HAMi/HAMi)
- [NVIDIA DCGM](https://developer.nvidia.com/dcgm)
- [Multi-Instance GPU (MIG)](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/)
- [CUDA Toolkit](https://developer.nvidia.com/cuda-toolkit)

---

[Components Overview](../README.md) | [Next: Training Infrastructure →](../02-training/README.md)
