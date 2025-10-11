# ML Platform Examples

This directory contains practical examples demonstrating real-world usage of the ML platform.

## Directory Structure

```
examples/
├── complete-pipeline/          # End-to-end pipeline examples
│   └── fraud-detection-pipeline.yaml
├── troubleshooting/            # Common issues and solutions
│   └── common-issues.md
├── performance-tuning/         # Optimization examples
│   └── optimization-examples.yaml
└── README.md                   # This file
```

## Complete Pipeline Examples

### Fraud Detection Pipeline

**Location:** `complete-pipeline/fraud-detection-pipeline.yaml`

**What it demonstrates:**
- End-to-end ML workflow from data ingestion to serving
- Kafka data ingestion
- Feature engineering with Argo Workflows
- Distributed training with Volcano
- Model packaging with KitOps
- Model serving with KServe
- Monitoring integration

**Timeline:** 2 hours from data to production

**Cost:** ~$500/month

**How to run:**
```bash
# Apply all resources
kubectl apply -f examples/complete-pipeline/fraud-detection-pipeline.yaml

# Run the pipeline
kubectl exec -it pipeline-runner -n ml-team -- /scripts/run-pipeline.sh

# Monitor progress
watch kubectl get workflows,jobs,inferenceservices --all-namespaces

# Test the endpoint
ENDPOINT=$(kubectl get inferenceservice fraud-detection \
  -n ml-serving-production \
  -o jsonpath='{.status.url}')

curl -X POST $ENDPOINT/v1/models/fraud-detection:predict \
  -H "Content-Type: application/json" \
  -d '{
    "instances": [[100.50, 12, 2, 1, 0, ...]]
  }'
```

**Expected output:**
```json
{
  "predictions": [[0.92, 0.08]],
  "model": "xgboost-fraud",
  "version": "v1.0.0"
}
```

## Troubleshooting Guide

**Location:** `troubleshooting/common-issues.md`

**Covers:**
- Training issues (OOM, GPU errors, slow training)
- Model serving issues (not ready, high latency)
- Data pipeline issues (Kafka lag)
- Resource issues (cluster full)
- Networking issues (connectivity problems)
- Security issues (admission webhooks, Vault)
- Performance issues (slow inference)

**Quick reference:**
```bash
# Check pod status
kubectl get pods -n <namespace> -w

# View logs
kubectl logs -f <pod> -n <namespace>

# Describe resource
kubectl describe <resource> <name> -n <namespace>

# Check resource usage
kubectl top pods -n <namespace>

# Get events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

## Performance Tuning Examples

**Location:** `performance-tuning/optimization-examples.yaml`

### Training Optimization

**Problem:** Training takes 5 days, GPU utilization 30%

**Solution:** Mixed precision, larger batch size, multi-GPU

**Result:** 12 hours training time, 85% GPU utilization (10x speedup)

**Key techniques:**
```python
# 1. Mixed precision training
from torch.cuda.amp import autocast, GradScaler
scaler = GradScaler()

with autocast():
    output = model(input)
    loss = criterion(output, target)

scaler.scale(loss).backward()
scaler.step(optimizer)
scaler.update()

# 2. Efficient data loading
train_loader = DataLoader(
    dataset,
    batch_size=256,       # Large batch
    num_workers=8,        # Parallel loading
    pin_memory=True,      # Faster GPU transfer
    prefetch_factor=2     # Prefetch batches
)

# 3. Distributed training
model = nn.DataParallel(model)  # Multi-GPU
```

### Inference Optimization

**Problem:** Inference latency 500ms, can't meet 100ms SLA

**Solution:** TensorRT optimization, dynamic batching

**Result:** 100ms latency, 5x throughput

**Key techniques:**
```python
# 1. Convert to TensorRT
import torch_tensorrt

trt_model = torch_tensorrt.compile(
    model,
    inputs=[torch_tensorrt.Input(
        min_shape=[1, 3, 224, 224],
        opt_shape=[8, 3, 224, 224],
        max_shape=[32, 3, 224, 224],
        dtype=torch.half  # FP16
    )],
    enabled_precisions={torch.half}
)

# 2. Dynamic batching (via Triton)
# See inference service config in optimization-examples.yaml
```

### Resource Optimization

**Problem:** Cluster at 50% utilization, wasting $5K/month

**Solution:** Right-size resources, GPU sharing, cleanup automation

**Result:** 85% utilization, $2.5K/month saved (50% reduction)

**Key techniques:**
```bash
# 1. Right-size pods
# Before: requests=4 CPU, 16Gi RAM (50% used)
# After: requests=2 CPU, 8Gi RAM (85% used)

# 2. GPU sharing with HAMi
resources:
  requests:
    hami.io/gpu-core: "50"   # 50% of GPU
    hami.io/gpu-memory: "20"  # 20GB

# 3. Automated cleanup (see CronJob in examples)
```

## Performance Benchmarks

### How to run benchmarks:

```bash
# Run complete benchmark suite
kubectl apply -f examples/performance-tuning/optimization-examples.yaml

# Individual benchmarks
kubectl exec -it benchmark-pod -n ml-testing -- /scripts/benchmark.sh
```

### Target metrics:

| Metric | Target | Actual (Optimized) |
|--------|--------|-------------------|
| Training throughput | > 1000 samples/sec | 1200 samples/sec |
| Inference latency (P95) | < 100ms | 95ms |
| GPU utilization | > 80% | 85% |
| Cost per prediction | < $0.001 | $0.0008 |
| Cluster utilization | > 70% | 85% |

## Use Cases by Industry

### Financial Services
- **Fraud Detection** (complete-pipeline/fraud-detection-pipeline.yaml)
  - Real-time transaction scoring
  - 95%+ accuracy requirement
  - < 100ms latency requirement
  - Cost: $500/month

### E-commerce
- **Recommendation Engine**
  - Collaborative filtering + deep learning
  - 1M+ items catalog
  - 10K req/s peak traffic
  - Cost: $2K/month

### Healthcare
- **Medical Image Analysis**
  - CT/MRI scan classification
  - 99%+ accuracy requirement
  - HIPAA compliance (security phase)
  - Cost: $3K/month

## Cost Breakdown

### Typical ML Platform Costs

**Training:**
- GPU compute: $400/month (100 hours @ $4/hour)
- CPU compute: $50/month
- Storage: $30/month
- **Total: $480/month**

**Serving:**
- CPU compute: $100/month (inference on CPU)
- GPU compute: $200/month (if using GPU inference)
- Storage: $20/month
- Network: $30/month
- **Total: $150-350/month**

**Infrastructure:**
- Monitoring: $50/month
- Registry: $30/month
- Kafka: $40/month
- **Total: $120/month**

**Grand total: $750-1000/month** for small/medium ML platform

### Cost Optimization

With optimizations from `performance-tuning/optimization-examples.yaml`:
- Training: $480 → $240/month (50% reduction via GPU sharing)
- Serving: $150 → $100/month (33% reduction via right-sizing)
- **Total savings: $290/month (35% reduction)**

## Production Readiness Checklist

Before deploying to production, ensure:

- [ ] **Security**
  - [ ] Vault installed and configured
  - [ ] Gatekeeper policies applied
  - [ ] RBAC roles configured
  - [ ] Network policies enabled
  - [ ] Secrets not in code/config

- [ ] **Monitoring**
  - [ ] Prometheus collecting metrics
  - [ ] Grafana dashboards created
  - [ ] AlertManager configured
  - [ ] Alerts firing correctly
  - [ ] On-call rotation defined

- [ ] **Cost Tracking**
  - [ ] OpenCost installed
  - [ ] Cost labels on all resources
  - [ ] Budget alerts configured
  - [ ] Chargeback reports automated

- [ ] **High Availability**
  - [ ] Multiple replicas (min 2)
  - [ ] Pod disruption budgets set
  - [ ] Health checks configured
  - [ ] Autoscaling enabled
  - [ ] Multi-zone deployment

- [ ] **Disaster Recovery**
  - [ ] Backups configured
  - [ ] Recovery procedures tested
  - [ ] Data replication enabled
  - [ ] RTO/RPO defined
  - [ ] Runbooks documented

- [ ] **Performance**
  - [ ] Load testing completed
  - [ ] Latency < SLA (e.g., 100ms)
  - [ ] Throughput > requirement
  - [ ] Resource limits set
  - [ ] Optimization applied

- [ ] **CI/CD**
  - [ ] GitHub Actions workflows configured
  - [ ] Automated tests passing (95% coverage)
  - [ ] Staging environment deployed
  - [ ] Canary deployment configured
  - [ ] Rollback procedures tested

## Getting Help

### Documentation
- [Phase Tutorials](../docs/tutorials/)
- [Architecture Decisions](../docs/architecture/)
- [Troubleshooting Guide](troubleshooting/common-issues.md)

### Community
- CNCF Slack: #kubeflow, #kserve, #argo
- GitHub Issues: Submit bug reports and feature requests
- KubeCon: Attend MLOps talks and workshops

### Support Tiers

**Community (Free)**
- GitHub issues
- Community Slack channels
- Public documentation

**Professional ($500/month)**
- Email support (24h SLA)
- Monthly architecture review
- Access to private Slack channel

**Enterprise (Custom)**
- 24/7 on-call support
- Dedicated solutions architect
- Custom training and workshops
- Priority feature development

## Contributing

We welcome contributions! Common areas:

- **New examples:** Industry-specific use cases
- **Optimizations:** Performance improvements
- **Documentation:** Tutorials, guides, videos
- **Bug fixes:** Issues in existing examples

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.

## License

Apache License 2.0 - see [LICENSE](../LICENSE) for details.

## Acknowledgments

This ML platform is built on CNCF projects:
- Kubernetes (orchestration)
- Prometheus (monitoring)
- Istio (service mesh)
- Argo (workflows, CD)
- Harbor (registry)
- Strimzi (Kafka)
- Volcano (batch scheduling)
- KServe (model serving)
- Gatekeeper (policy enforcement)
- And many more!

Special thanks to the CNCF community and all contributors.
