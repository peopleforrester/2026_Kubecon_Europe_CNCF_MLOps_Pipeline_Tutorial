# 5-Minute Quickstart Guide

Get the CNCF MLOps pipeline running in under 30 minutes.

---

## Prerequisites

Before starting, ensure you have:

- ✓ Kubernetes cluster (1.28+) with 2+ GPU nodes
- ✓ `kubectl` configured and connected
- ✓ `helm` installed (v3.12+)
- ✓ GPU nodes labeled with `nvidia.com/gpu.present=true`

**Validate prerequisites:**
```bash
./tests/validation/validate-prerequisites.sh
```

---

## Quick Start: 3 Commands

### 1. Install Core Infrastructure (5 minutes)

```bash
# Install GPU Operator (NVIDIA drivers, device plugin, DCGM)
helm repo add nvidia https://nvidia.github.io/gpu-operator
helm install gpu-operator nvidia/gpu-operator \
  -n gpu-operator --create-namespace \
  -f infrastructure/gpu-operator/nvidia-gpu-operator.yaml

# Wait for GPU Operator to be ready
kubectl wait --for=condition=ready pod -l app=nvidia-device-plugin-daemonset -n gpu-operator --timeout=300s
```

**Verify:**
```bash
./infrastructure/gpu-operator/gpu-validation.sh
```

---

### 2. Install Observability Stack (3 minutes)

```bash
# Install Prometheus + OpenCost for GPU cost tracking
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace

# Install OpenCost for GPU cost attribution
helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm install opencost opencost/opencost \
  -n opencost --create-namespace \
  --set prometheus.internal.serviceName=prometheus-kube-prometheus-prometheus.monitoring
```

**Access OpenCost dashboard:**
```bash
kubectl port-forward -n opencost svc/opencost 9090:9090
# Visit: http://localhost:9090
```

---

### 3. Deploy Example Training Job (2 minutes)

```bash
# Install Volcano scheduler
kubectl apply -f https://raw.githubusercontent.com/volcano-sh/volcano/v1.11.0/installer/volcano-development.yaml

# Install Kubeflow Training Operator
kubectl apply -k "github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.8.0"

# Deploy example PyTorch training job
kubectl apply -f examples/end-to-end/mnist-example/pytorch-training.yaml

# Watch training progress
kubectl get pods -l app=pytorch-training -w
```

**Check logs:**
```bash
kubectl logs -l app=pytorch-training -f
```

---

## What You Just Deployed

### Infrastructure Layer
- **GPU Operator:** NVIDIA drivers, device plugin, DCGM exporter for GPU metrics
- **Prometheus:** Metrics collection (GPU utilization, memory, temperature)
- **OpenCost:** GPU cost attribution by pod/namespace/team

### Training Layer
- **Volcano:** GPU scheduler with gang scheduling (prevents deadlocks)
- **Kubeflow Training Operator:** Distributed training orchestration
- **Example Job:** MNIST digit classification on PyTorch

---

## Next Steps

### Deploy Model Serving

```bash
# Install KServe
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.13.0/kserve.yaml
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.13.0/kserve-runtimes.yaml

# Deploy trained model
kubectl apply -f examples/end-to-end/mnist-example/model-serving.yaml

# Test inference
kubectl port-forward svc/mnist-predictor 8080:80
curl http://localhost:8080/v1/models/mnist:predict -d @test-image.json
```

### Monitor GPU Costs

```bash
# Port-forward OpenCost
kubectl port-forward -n opencost svc/opencost 9090:9090

# Query GPU costs
curl http://localhost:9090/allocation \
  -d window=7d \
  -d aggregate=namespace \
  -d accumulate=true \
  -G
```

### Deploy HAMi for GPU Sharing

```bash
# Install HAMi device plugin
kubectl apply -f components/02-training/hami/hami-device-plugin.yaml

# Deploy inference with fractional GPU
kubectl apply -f examples/end-to-end/mnist-example/inference-fractional-gpu.yaml
```

---

## Troubleshooting

### GPU Operator Issues

**Problem:** GPU Operator pods not running
```bash
# Check logs
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset

# See troubleshooting guide
cat infrastructure/gpu-operator/troubleshooting.md
```

### Training Job Stuck Pending

**Problem:** Training pods pending with "Insufficient nvidia.com/gpu"
```bash
# Check GPU availability
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, gpus: .status.allocatable."nvidia.com/gpu"}'

# Check Volcano queue status
kubectl get queues

# See common issues
cat docs/troubleshooting/common-errors.md
```

### OpenCost Not Showing GPU Costs

**Problem:** OpenCost dashboard empty
```bash
# Verify DCGM exporter is running
kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter

# Check Prometheus scraping DCGM metrics
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit: http://localhost:9090/targets (verify dcgm-exporter target UP)
```

---

## Full Pipeline Deployment

For complete 6-stage MLOps pipeline:

```bash
# Install all components
./scripts/setup/install-all.sh

# Deploy end-to-end example
kubectl apply -k examples/end-to-end/complete-pipeline/
```

See: [Architecture Overview](../architecture/overview.md)

---

## Clean Up

```bash
# Remove example workloads
kubectl delete -f examples/end-to-end/mnist-example/

# Remove observability stack
helm uninstall prometheus -n monitoring
helm uninstall opencost -n opencost

# Remove GPU Operator
helm uninstall gpu-operator -n gpu-operator

# Remove Volcano
kubectl delete -f https://raw.githubusercontent.com/volcano-sh/volcano/v1.11.0/installer/volcano-development.yaml
```

---

## Resources

- **Architecture Guide:** [docs/architecture/overview.md](../architecture/overview.md)
- **Decision Frameworks:** [docs/decision-frameworks/](../decision-frameworks/)
- **Cost Optimization:** [cost-analysis/optimization/optimization-checklist.md](../../cost-analysis/optimization/optimization-checklist.md)
- **GPU Troubleshooting:** [infrastructure/gpu-operator/troubleshooting.md](../../infrastructure/gpu-operator/troubleshooting.md)

**Questions?** Open an issue or join #mlops-cncf-tutorial on CNCF Slack.
