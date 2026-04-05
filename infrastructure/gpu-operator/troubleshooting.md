# GPU Operator Troubleshooting Guide

## Common Issues and Solutions

This guide addresses the most common GPU Operator issues seen across 100K+ student deployments.

---

## Issue 1: Driver Installation Fails

### Symptoms
```
nvidia-driver-daemonset-xxxxx   0/1     CrashLoopBackOff
```

### Diagnosis
```bash
# Check driver pod logs
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset --tail=50

# Check node kernel version
kubectl get nodes -o wide
```

### Common Causes

#### Cause 1: Kernel Headers Missing

**Error Message:**
```
ERROR: Unable to find the kernel source tree
```

**Solution:**
```bash
# SSH to GPU node
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y linux-headers-$(uname -r)

# RHEL/CentOS
sudo yum install -y kernel-devel-$(uname -r) kernel-headers-$(uname -r)

# Restart driver pod
kubectl delete pod -n gpu-operator -l app=nvidia-driver-daemonset
```

#### Cause 2: Secure Boot Enabled

**Error Message:**
```
modprobe: ERROR: could not insert 'nvidia': Required key not available
```

**Solution:**

Option A: Disable Secure Boot (recommended for ML clusters)
```bash
# Enter BIOS/UEFI and disable Secure Boot
# Reboot node
```

Option B: Sign NVIDIA kernel module
```bash
# Generate signing key
openssl req -new -x509 -newkey rsa:2048 -keyout MOK.priv -outform DER -out MOK.der -days 36500 -subj "/CN=GPU Operator/"
# Import key into MOK (Machine Owner Key)
sudo mokutil --import MOK.der
# Reboot and enroll key
```

#### Cause 3: Pre-installed Driver Conflict

**Error Message:**
```
NVIDIA driver already loaded
```

**Solution:**
```yaml
# Set usePreinstalled: true in nvidia-gpu-operator.yaml
driver:
  enabled: true
  usePreinstalled: true  # Use existing driver
```

---

## Issue 2: Device Plugin Not Discovering GPUs

### Symptoms
```bash
kubectl get nodes -o json | jq '.items[].status.capacity."nvidia.com/gpu"'
# Returns: null
```

### Diagnosis
```bash
# Check device plugin logs
kubectl logs -n gpu-operator -l app=nvidia-device-plugin-daemonset

# Check if nvidia-smi works on driver pod
kubectl exec -n gpu-operator $(kubectl get pod -n gpu-operator -l app=nvidia-driver-daemonset -o jsonpath='{.items[0].metadata.name}') -- nvidia-smi
```

### Solutions

#### Solution 1: Verify Driver is Loaded
```bash
# Should show GPU list
kubectl exec -n gpu-operator <driver-pod> -- nvidia-smi

# If not, check driver logs
kubectl logs -n gpu-operator <driver-pod>
```

#### Solution 2: Check Container Runtime Socket
```bash
# Verify containerd socket path
ls -la /run/containerd/containerd.sock

# Update GPU Operator if path differs
helm upgrade gpu-operator nvidia/gpu-operator \
  --set toolkit.env[0].name=CONTAINERD_SOCKET \
  --set toolkit.env[0].value=/run/containerd/containerd.sock
```

#### Solution 3: Restart Device Plugin
```bash
kubectl delete pod -n gpu-operator -l app=nvidia-device-plugin-daemonset
```

---

## Issue 3: DCGM Exporter Not Exposing Metrics

### Symptoms
```bash
curl localhost:9400/metrics
# No response or "connection refused"
```

### Diagnosis
```bash
# Check DCGM exporter logs
kubectl logs -n gpu-operator -l app=nvidia-dcgm-exporter

# Port-forward to test
kubectl port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400
curl localhost:9400/metrics | grep DCGM
```

### Solutions

#### Solution 1: Verify Pod is Running
```bash
kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter

# If not running, check events
kubectl describe pod -n gpu-operator -l app=nvidia-dcgm-exporter
```

#### Solution 2: Check DCGM Hostengine
```bash
# DCGM exporter needs DCGM hostengine running
kubectl exec -n gpu-operator <dcgm-pod> -- dcgmi discovery -l

# Should list GPUs
```

#### Solution 3: Update Metrics ConfigMap
```bash
# Verify metrics config exists
kubectl get configmap -n gpu-operator dcgm-exporter-metrics

# Apply updated config from nvidia-gpu-operator.yaml
kubectl apply -f infrastructure/gpu-operator/nvidia-gpu-operator.yaml
kubectl delete pod -n gpu-operator -l app=nvidia-dcgm-exporter
```

---

## Issue 4: Pods Stuck in Pending with "Insufficient nvidia.com/gpu"

### Symptoms
```bash
kubectl get pods
NAME          READY   STATUS    RESTARTS   AGE
training-pod  0/1     Pending   0          5m

kubectl describe pod training-pod
# Events: 0/3 nodes are available: 3 Insufficient nvidia.com/gpu
```

### Diagnosis
```bash
# Check allocatable GPUs
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, gpus: .status.allocatable."nvidia.com/gpu"}'

# Check current GPU usage
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.containers[].resources.limits."nvidia.com/gpu" != null) | "\(.metadata.name) - \(.spec.containers[0].resources.limits."nvidia.com/gpu")"'
```

### Solutions

#### Solution 1: Verify Device Plugin Registered GPUs
```bash
# Should show available GPUs
kubectl describe node <gpu-node> | grep nvidia.com/gpu
# Capacity: nvidia.com/gpu: 2
# Allocatable: nvidia.com/gpu: 2
```

#### Solution 2: Check if GPUs are Already Allocated
```bash
# List all pods using GPUs
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.containers[].resources.limits."nvidia.com/gpu" != null) | "\(.metadata.namespace)/\(.metadata.name)"'

# Delete completed/failed pods to free GPUs
kubectl delete pod <pod-name>
```

#### Solution 3: Add Node Affinity for GPU Nodes
```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: nvidia.com/gpu.present
            operator: In
            values:
            - "true"
```

---

## Issue 5: Time-Slicing Causing Latency Issues

### Symptoms
- Inference latency 5-10x higher than expected
- `nvidia-smi` shows multiple processes on same GPU
- Production SLA violations

### Diagnosis
```bash
# Check time-slicing config
kubectl get configmap -n gpu-operator time-slicing-config -o yaml

# Look for replicas > 1
```

### Solution

**Time-slicing is NOT recommended for production inference.** Use HAMi instead.

```bash
# Disable time-slicing
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: gpu-operator
data:
  any: |-
    version: v1
    sharing:
      timeSlicing:
        replicas: 1  # Disable time-slicing
EOF

# Restart device plugin
kubectl delete pod -n gpu-operator -l app=nvidia-device-plugin-daemonset

# Migrate to HAMi for GPU sharing
kubectl apply -f infrastructure/hami/hami-device-plugin.yaml
```

See [GPU Sharing Decision Framework](../../docs/decision-frameworks/gpu-sharing.md) for details.

---

## Issue 6: MIG Mode Not Working

### Symptoms
```bash
nvidia-smi -mig 1
# ERROR: MIG mode is not supported
```

### Diagnosis
```bash
# Check GPU model
kubectl exec -n gpu-operator <driver-pod> -- nvidia-smi --query-gpu=name --format=csv,noheader
```

### Solution

**MIG only works on A100, H100, A30 GPUs.**

If you have V100, T4, or other GPUs:
```bash
# Use HAMi instead for GPU virtualization
kubectl apply -f components/02-training/hami/hami-device-plugin.yaml
```

If you have A100/H100:
```bash
# Enable MIG Manager
helm upgrade gpu-operator nvidia/gpu-operator \
  --set migManager.enabled=true \
  --set migManager.config.name=mig-parted-config

# Apply MIG config from nvidia-gpu-operator.yaml
kubectl apply -f infrastructure/gpu-operator/nvidia-gpu-operator.yaml

# Restart GPU Operator pods
kubectl delete pod -n gpu-operator --all
```

---

## Issue 7: GPU OOM Kills Other Pods (Time-Slicing)

### Symptoms
```
Pod gpu-inference-2 evicted: OutOfMemory
```

Multiple pods sharing GPU via time-slicing, one pod allocates too much GPU memory and kills others.

### Diagnosis
```bash
# Check GPU memory usage
kubectl exec -n gpu-operator <driver-pod> -- nvidia-smi --query-gpu=memory.used,memory.total --format=csv
```

### Solution

**Time-slicing has NO memory isolation.** This is a fundamental limitation.

**Fix: Use HAMi with memory limits:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: safe-inference-pod
spec:
  containers:
  - name: model
    resources:
      limits:
        nvidia.com/gpu: 1
        nvidia.com/gpumem: 10000  # HAMi enforces 10GB GPU memory limit
```

See [docs/decision-frameworks/gpu-sharing.md](../../docs/decision-frameworks/gpu-sharing.md).

---

## Diagnostic Commands Cheat Sheet

```bash
# GPU Operator overall health
kubectl get pods -n gpu-operator

# Driver version
kubectl exec -n gpu-operator <driver-pod> -- nvidia-smi --query-gpu=driver_version --format=csv,noheader

# GPU list
kubectl exec -n gpu-operator <driver-pod> -- nvidia-smi -L

# GPU utilization
kubectl exec -n gpu-operator <driver-pod> -- nvidia-smi

# DCGM metrics
kubectl port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400
curl localhost:9400/metrics | grep DCGM_FI_DEV_GPU_UTIL

# Allocatable GPUs per node
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, gpus: .status.allocatable."nvidia.com/gpu"}'

# Pods using GPUs
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.containers[].resources.limits."nvidia.com/gpu" != null) | "\(.metadata.namespace)/\(.metadata.name)"'

# GPU Operator logs
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset --tail=100
kubectl logs -n gpu-operator -l app=nvidia-device-plugin-daemonset --tail=100
kubectl logs -n gpu-operator -l app=nvidia-dcgm-exporter --tail=100
```

---

## Getting Help

If issues persist after trying these solutions:

1. **Check GPU Operator logs:**
   ```bash
   kubectl logs -n gpu-operator <pod-name> --tail=200
   ```

2. **Gather diagnostics:**
   ```bash
   kubectl cluster-info dump -n gpu-operator > gpu-operator-diagnostics.txt
   ```

3. **NVIDIA GPU Operator GitHub Issues:**
   https://github.com/NVIDIA/gpu-operator/issues

4. **CNCF Slack:**
   #mlops-cncf-tutorial channel

5. **Tutorial Community Discussions:**
   https://github.com/peopleforrester/2026_Kubecon_Europe_CNCF_MLOps_Pipeline_Tutorial/discussions

---

## Prevention Tips (from 100K+ Student Failures)

1. **Always set GPU resource limits** to prevent runaway costs
2. **Use HAMi, not time-slicing** for production GPU sharing
3. **Monitor GPU metrics with DCGM + OpenCost** from day one
4. **Test driver installation** on one node before rolling out to cluster
5. **Disable Secure Boot** on GPU nodes before driver installation
6. **Use pre-installed drivers** if available (faster, more reliable)

---

## Next Steps

- [Validate GPU Setup](gpu-validation.sh)
- [GPU Sharing Decision Framework](../../docs/decision-frameworks/gpu-sharing.md)
- [Deploy Training Examples](../../components/02-training/examples/)
