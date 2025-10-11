# ML Platform Troubleshooting Guide

This guide provides solutions to common issues encountered when running the ML platform.

## Table of Contents

1. [Training Issues](#training-issues)
2. [Model Serving Issues](#model-serving-issues)
3. [Data Pipeline Issues](#data-pipeline-issues)
4. [Resource Issues](#resource-issues)
5. [Networking Issues](#networking-issues)
6. [Security Issues](#security-issues)
7. [Performance Issues](#performance-issues)

## Training Issues

### Issue: Training job stuck in Pending

**Symptoms:**
```bash
kubectl get pods -n ml-training
# NAME                  READY   STATUS    RESTARTS   AGE
# training-job-worker   0/1     Pending   0          10m
```

**Diagnosis:**
```bash
# Check pod events
kubectl describe pod training-job-worker -n ml-training

# Common causes:
# 1. Insufficient GPU resources
# 2. Resource quota exceeded
# 3. Node selector mismatch
# 4. PVC not bound
```

**Solution 1: Insufficient GPU resources**
```bash
# Check available GPUs
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'

# If no GPUs available:
# Option A: Wait for running jobs to complete
# Option B: Scale cluster (add GPU nodes)
# Option C: Reduce GPU request in job spec
```

**Solution 2: Resource quota exceeded**
```bash
# Check quota
kubectl describe resourcequota -n ml-training

# If exceeded:
kubectl edit resourcequota ml-team-budget-quota -n ml-training
# Increase: requests.nvidia.com/gpu: "25"  # Was 20
```

**Solution 3: PVC not bound**
```bash
# Check PVC
kubectl get pvc -n ml-training

# If pending:
# Check if StorageClass exists
kubectl get storageclass

# Check PV availability
kubectl get pv
```

---

### Issue: Training job OOM killed

**Symptoms:**
```bash
kubectl get pods -n ml-training
# NAME                  READY   STATUS      RESTARTS   AGE
# training-job-worker   0/1     OOMKilled   3          5m
```

**Diagnosis:**
```bash
# Check memory usage before crash
kubectl top pod training-job-worker -n ml-training --containers

# Check logs
kubectl logs training-job-worker -n ml-training --previous

# Typical output:
# Killed
# (process died due to out of memory)
```

**Solution:**
```bash
# Increase memory limits
kubectl edit job training-job -n ml-training

# Change:
resources:
  requests:
    memory: 32Gi  # Was 16Gi
  limits:
    memory: 64Gi  # Was 32Gi

# Or reduce batch size in training script:
# --batch-size=16  # Was 32
```

---

### Issue: Training fails with CUDA out of memory

**Symptoms:**
```
RuntimeError: CUDA out of memory. Tried to allocate 2.00 GiB (GPU 0; 39.59 GiB total capacity)
```

**Diagnosis:**
```bash
# Check GPU memory usage
kubectl exec -it training-job-worker -n ml-training -- nvidia-smi

# Check if multiple processes using GPU
kubectl get pods -n ml-training -o wide --field-selector spec.nodeName=<node-name>
```

**Solution 1: Reduce batch size**
```python
# In training script
batch_size = 16  # Was 32
```

**Solution 2: Enable gradient checkpointing**
```python
# Reduces memory at cost of compute
model.gradient_checkpointing_enable()
```

**Solution 3: Use mixed precision**
```python
# FP16 uses half the memory
from torch.cuda.amp import autocast, GradScaler

scaler = GradScaler()
with autocast():
    output = model(input)
```

**Solution 4: Request larger GPU**
```yaml
resources:
  requests:
    nvidia.com/gpu: 1
    nvidia.com/gpu-memory: 80Gi  # Request A100 80GB instead of 40GB
```

---

## Model Serving Issues

### Issue: InferenceService not ready

**Symptoms:**
```bash
kubectl get inferenceservice -n ml-serving
# NAME       URL   READY   AGE
# resnet50         False   10m
```

**Diagnosis:**
```bash
# Check conditions
kubectl describe inferenceservice resnet50 -n ml-serving

# Check underlying pods
kubectl get pods -n ml-serving -l serving.kserve.io/inferenceservice=resnet50

# Check logs
kubectl logs -n ml-serving -l serving.kserve.io/inferenceservice=resnet50 --all-containers
```

**Common causes and solutions:**

**Cause 1: Image pull failure**
```bash
# Symptoms in events:
# Failed to pull image "harbor.ml-platform/ml-models/resnet50:v1.0.0": rpc error: code = Unknown desc = Error response from daemon: unauthorized

# Solution: Fix image pull secret
kubectl create secret docker-registry harbor-registry \
  --docker-server=harbor.ml-platform.example.com \
  --docker-username=robot-account \
  --docker-password=<token> \
  -n ml-serving

# Add to ServiceAccount
kubectl patch serviceaccount default -n ml-serving \
  -p '{"imagePullSecrets": [{"name": "harbor-registry"}]}'
```

**Cause 2: Model loading failure**
```bash
# Symptoms in logs:
# Failed to load model: FileNotFoundError: /mnt/models/model.pt

# Solution: Check storageUri
kubectl edit inferenceservice resnet50 -n ml-serving

# Verify format:
storageUri: oras://harbor.ml-platform/ml-models/resnet50:v1.0.0  # Correct
storageUri: harbor.ml-platform/ml-models/resnet50:v1.0.0  # Wrong (missing oras://)
```

**Cause 3: Insufficient resources**
```bash
# Symptoms: Pod pending, events show:
# 0/5 nodes are available: 2 Insufficient nvidia.com/gpu

# Solution: Reduce resource requests or add nodes
kubectl edit inferenceservice resnet50 -n ml-serving

resources:
  requests:
    nvidia.com/gpu: 0  # Try CPU-only
    # Or wait for GPU to free up
```

---

### Issue: High inference latency

**Symptoms:**
```bash
# P95 latency > 500ms
curl -X POST http://resnet50.ml-serving/v1/models/resnet50:predict \
  -d '{"instances": [...]}' \
  -w "\nTime: %{time_total}s\n"

# Output:
# Time: 1.2s  # Too slow!
```

**Diagnosis:**
```bash
# Check Grafana dashboard
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Navigate to "Model Serving" dashboard
# Look at:
# - Latency P50/P95/P99
# - Request rate
# - Pod count (autoscaling working?)
# - GPU utilization

# Profile specific request
kubectl exec -it -n ml-serving <pod> -- python -m cProfile -o profile.out serve.py
```

**Solutions:**

**Solution 1: Enable batching**
```yaml
# In InferenceService
spec:
  predictor:
    minReplicas: 2
    maxReplicas: 10
    containerConcurrency: 10  # Allow batching
```

**Solution 2: Use TensorRT optimization**
```bash
# Convert model to TensorRT
trtexec --onnx=model.onnx --saveEngine=model.trt --fp16

# Update InferenceService to use TensorRT runtime
```

**Solution 3: Add model caching**
```python
# Cache model in memory (don't reload per request)
_model_cache = {}

def get_model():
    if 'resnet50' not in _model_cache:
        _model_cache['resnet50'] = load_model()
    return _model_cache['resnet50']
```

**Solution 4: Scale up replicas**
```bash
kubectl scale inferenceservice resnet50 --replicas=5 -n ml-serving

# Or adjust autoscaling
kubectl annotate inferenceservice resnet50 \
  autoscaling.knative.dev/maxScale=20 \
  -n ml-serving
```

---

## Data Pipeline Issues

### Issue: Kafka messages not being consumed

**Symptoms:**
```bash
# Consumer lag increasing
kafka-consumer-groups.sh --bootstrap-server ml-kafka-bootstrap:9092 \
  --describe --group ml-consumers

# GROUP           TOPIC      PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
# ml-consumers    transactions  0       1000            10000           9000  # High lag!
```

**Diagnosis:**
```bash
# Check consumer pod status
kubectl get pods -n data-pipeline -l app=kafka-consumer

# Check logs
kubectl logs -f -n data-pipeline <consumer-pod>

# Common errors:
# - Connection refused (Kafka unreachable)
# - Offset out of range (messages expired)
# - Rebalancing constantly (consumer crashes)
```

**Solutions:**

**Solution 1: Scale consumers**
```bash
# Add more consumer pods to process faster
kubectl scale deployment kafka-consumer --replicas=5 -n data-pipeline

# Or increase partitions (requires Kafka restart)
kafka-topics.sh --bootstrap-server ml-kafka-bootstrap:9092 \
  --alter --topic transactions --partitions 20
```

**Solution 2: Increase retention**
```bash
# If messages expiring before consumption
kubectl edit kafkatopic transactions -n data-pipeline

# Change:
spec:
  config:
    retention.ms: 1209600000  # 14 days (was 7 days)
```

**Solution 3: Fix consumer crashes**
```bash
# Check for OOM or errors
kubectl logs -n data-pipeline <consumer-pod> --previous

# Increase resources if OOM
kubectl edit deployment kafka-consumer -n data-pipeline

resources:
  requests:
    memory: 2Gi  # Was 1Gi
```

---

## Resource Issues

### Issue: Cluster running out of resources

**Symptoms:**
```bash
kubectl get nodes
# NAME       STATUS   ROLES    AGE   VERSION
# node-1     Ready    <none>   30d   v1.28.0
# node-2     Ready    <none>   30d   v1.28.0
# node-3     Ready    <none>   30d   v1.28.0

kubectl top nodes
# NAME     CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
# node-1   15800m       99%    58Gi            95%      # Maxed out!
# node-2   15900m       99%    60Gi            98%      # Maxed out!
# node-3   15700m       98%    57Gi            94%      # Maxed out!
```

**Diagnosis:**
```bash
# Check pod resource usage
kubectl top pods --all-namespaces --sort-by=memory | head -20

# Check resource requests vs limits
kubectl describe nodes | grep -A 5 "Allocated resources"

# Find pods without resource limits
kubectl get pods --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.containers[].resources.limits == null) | .metadata.name'
```

**Solutions:**

**Solution 1: Add nodes**
```bash
# If using managed Kubernetes (GKE, EKS, AKS)
gcloud container clusters resize ml-cluster --num-nodes=5  # Was 3

# Or enable cluster autoscaler
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-autoscaler-config
data:
  min-nodes: "3"
  max-nodes: "10"
EOF
```

**Solution 2: Right-size pods**
```bash
# Find over-provisioned pods (request >> usage)
kubectl top pods --all-namespaces | awk '{if ($3 ~ /%/ && $3+0 < 20) print $0}'

# Reduce requests for low-utilization pods
kubectl edit deployment <deployment> -n <namespace>

resources:
  requests:
    cpu: 500m  # Was 2
    memory: 1Gi  # Was 4Gi
```

**Solution 3: Delete unused resources**
```bash
# Find old completed jobs
kubectl get jobs --all-namespaces --field-selector status.successful=1

# Delete jobs older than 7 days
kubectl delete jobs --all-namespaces --field-selector status.successful=1 \
  --dry-run=client | grep "job.batch" | \
  xargs -I {} kubectl delete {}

# Delete old pods
kubectl delete pods --all-namespaces --field-selector status.phase=Succeeded
```

---

## Networking Issues

### Issue: Cannot access model endpoint

**Symptoms:**
```bash
curl http://resnet50.ml-serving/v1/models/resnet50
# curl: (7) Failed to connect to resnet50.ml-serving port 80: Connection refused
```

**Diagnosis:**
```bash
# Check Service exists
kubectl get svc -n ml-serving

# Check endpoints
kubectl get endpoints -n ml-serving

# Check network policies
kubectl get networkpolicies -n ml-serving

# Test from within cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  wget -O- http://resnet50.ml-serving/v1/models/resnet50
```

**Solutions:**

**Solution 1: Service not created**
```bash
# KServe should create Service automatically
# If missing, check InferenceService status
kubectl describe inferenceservice resnet50 -n ml-serving

# Manually create Service if needed
kubectl expose deployment resnet50-predictor -n ml-serving \
  --port=80 --target-port=8080
```

**Solution 2: Network policy blocking traffic**
```bash
# Check if default-deny-all policy exists
kubectl get networkpolicy default-deny-all -n ml-serving

# If exists, add policy to allow traffic
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-model-access
  namespace: ml-serving
spec:
  podSelector:
    matchLabels:
      serving.kserve.io/inferenceservice: resnet50
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 8080
EOF
```

**Solution 3: Istio/Ingress misconfiguration**
```bash
# Check VirtualService
kubectl get virtualservice -n ml-serving

# Check Ingress
kubectl get ingress -n ml-serving

# Test with port-forward (bypasses ingress)
kubectl port-forward -n ml-serving svc/resnet50-predictor 8080:80

# Then test: curl http://localhost:8080/v1/models/resnet50
```

---

## Security Issues

### Issue: Pod rejected by admission webhook

**Symptoms:**
```bash
kubectl apply -f deployment.yaml
# Error from server: admission webhook "validation.gatekeeper.sh" denied the request:
# [require-cost-labels] Resource is missing required labels: [team, project]
```

**Solution:**
```bash
# Add required labels
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
  labels:
    team: ml-team          # Required!
    project: my-project    # Required!
    environment: dev       # Required!
spec:
  template:
    metadata:
      labels:
        team: ml-team
        project: my-project
        environment: dev
    spec:
      # ... rest of spec
EOF
```

---

### Issue: Cannot access secrets from Vault

**Symptoms:**
```bash
# Pod logs show:
# Error: failed to read secret: permission denied
```

**Diagnosis:**
```bash
# Check Vault policy
kubectl exec -n vault vault-0 -- vault policy read ml-team-policy

# Check Kubernetes role
kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/ml-team

# Check ServiceAccount matches
kubectl get pod <pod> -n ml-team -o jsonpath='{.spec.serviceAccountName}'
```

**Solution:**
```bash
# Update Vault role to include ServiceAccount
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/ml-team \
  bound_service_account_names=ml-app,training-job \  # Add training-job
  bound_service_account_namespaces=ml-team \
  policies=ml-team-policy \
  ttl=1h
```

---

## Performance Issues

### Issue: Training extremely slow

**Symptoms:**
- Training taking 10x longer than expected
- GPU utilization < 20%

**Diagnosis:**
```bash
# Check GPU utilization
kubectl exec -it training-pod -n ml-training -- nvidia-smi

# Check if using GPU
kubectl exec -it training-pod -n ml-training -- python -c "import torch; print(torch.cuda.is_available())"

# Check CPU usage
kubectl top pod training-pod -n ml-training
```

**Solutions:**

**Solution 1: Data loading bottleneck**
```python
# Increase DataLoader workers
train_loader = DataLoader(
    dataset,
    batch_size=32,
    num_workers=8,  # Was 0
    pin_memory=True
)
```

**Solution 2: Not using GPU**
```python
# Ensure model on GPU
device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
model = model.to(device)
```

**Solution 3: Small batch size**
```python
# Increase batch size to saturate GPU
batch_size = 128  # Was 32

# Use gradient accumulation if OOM
accumulation_steps = 4
```

---

## Quick Reference

### Essential Commands

```bash
# Check pod status
kubectl get pods -n <namespace> -w

# Get pod logs
kubectl logs -f <pod> -n <namespace>

# Get previous pod logs (after crash)
kubectl logs <pod> -n <namespace> --previous

# Describe resource (shows events)
kubectl describe <resource> <name> -n <namespace>

# Check resource usage
kubectl top pods -n <namespace>
kubectl top nodes

# Port forward for debugging
kubectl port-forward -n <namespace> <pod> <local-port>:<pod-port>

# Execute command in pod
kubectl exec -it <pod> -n <namespace> -- <command>

# Get events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

### Debugging Workflow

1. **Identify symptoms** - What's not working?
2. **Check pod status** - `kubectl get pods`
3. **View events** - `kubectl describe pod`
4. **Read logs** - `kubectl logs`
5. **Check resources** - `kubectl top`
6. **Test connectivity** - Port forward and curl
7. **Apply fix** - Edit resource
8. **Verify** - Recheck status and logs

### Getting Help

- **Logs**: `kubectl logs` is your friend
- **Events**: `kubectl describe` shows recent events
- **Metrics**: Grafana dashboards show trends
- **Community**: #kubeflow, #kserve on CNCF Slack

