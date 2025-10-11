# MLOps Platform Components

This directory contains production-ready Kubernetes manifests for deploying a complete MLOps platform using CNCF and cloud-native technologies.

## Overview

The platform consists of 8 core components organized by function:

```
┌─────────────────────────────────────────────────────────────┐
│                    MLOps Platform Stack                     │
└─────────────────────────────────────────────────────────────┘

Training            Registry           Serving          Observability
┌──────────┐       ┌──────────┐      ┌──────────┐     ┌──────────────┐
│ Volcano  │       │  Harbor  │      │  KServe  │     │ Prometheus   │
│          │──────▶│ + KitOps │─────▶│ + Istio  │────▶│ + Grafana    │
│ GPU Sched│       │          │      │          │     │              │
└──────────┘       └──────────┘      └──────────┘     └──────────────┘
     │                  │                  │                  │
     ▼                  ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                          │
│                                                                     │
│  Security: Vault, Gatekeeper | GPU: HAMi, NVIDIA | Cost: OpenCost  │
└─────────────────────────────────────────────────────────────────────┘
```

## Components Directory Structure

```
components/
├── 01-gpu-resources/      # GPU sharing and scheduling
│   ├── hami/             # HAMi (GPU device plugin)
│   └── nvidia/           # NVIDIA GPU Operator
├── 02-training/          # Distributed training workloads
│   └── volcano/          # Volcano batch scheduler
├── 03-model-registry/    # Model versioning and storage
│   ├── harbor/           # Harbor OCI registry
│   ├── kitops/           # KitOps model packaging
│   └── in-toto/          # Supply chain security (SBOM, signing)
├── 04-model-serving/     # Serverless model inference
│   └── kserve/           # KServe + Knative + Istio
├── 05-observability/     # Metrics and monitoring
│   └── prometheus/       # Prometheus + Grafana stack
├── 06-cost-attribution/  # Cost tracking and optimization
│   └── opencost/         # OpenCost
├── 07-security/          # Security and governance
│   ├── secrets/          # Vault secrets management
│   ├── policies/         # OPA Gatekeeper policies
│   └── rbac/             # RBAC and network policies
└── 08-cicd/              # CI/CD automation
    └── argo/             # Argo Workflows + Events

```

## Quick Start

### Prerequisites

- Kubernetes 1.28+ cluster
- kubectl configured with admin access
- Helm 3.x installed
- 500Gi storage available
- NVIDIA GPU nodes (optional, for GPU workloads)

### Installation Order

Install components in this order to satisfy dependencies:

1. **GPU Resources** (if using GPUs)
   ```bash
   kubectl apply -f 01-gpu-resources/nvidia/gpu-operator-install.yaml
   kubectl apply -f 01-gpu-resources/hami/hami-install.yaml
   ```

2. **Training Infrastructure**
   ```bash
   kubectl apply -f 02-training/volcano/volcano-install.yaml
   ```

3. **Model Registry**
   ```bash
   # Install Harbor
   kubectl apply -f 03-model-registry/harbor/harbor-install.yaml

   # Install KitOps
   kubectl apply -f 03-model-registry/kitops/kitops-install.yaml

   # Configure supply chain security
   kubectl apply -f 03-model-registry/in-toto/sbom-generation.yaml
   ```

4. **Model Serving**
   ```bash
   kubectl apply -f 04-model-serving/kserve/kserve-install.yaml
   ```

5. **Observability**
   ```bash
   kubectl apply -f 05-observability/prometheus/prometheus-grafana-install.yaml
   ```

6. **Cost Attribution**
   ```bash
   kubectl apply -f 06-cost-attribution/opencost/opencost-install.yaml
   ```

7. **Security & Governance**
   ```bash
   # Vault secrets management
   kubectl apply -f 07-security/secrets/vault-secrets-management.yaml

   # OPA Gatekeeper policies
   kubectl apply -f 07-security/policies/gatekeeper-policies.yaml

   # RBAC and network policies
   kubectl apply -f 07-security/rbac/rbac-namespace-isolation.yaml
   ```

8. **CI/CD** (optional)
   ```bash
   kubectl apply -f 08-cicd/argo/argo-workflows-install.yaml
   ```

### Verification

After installation, verify all components are running:

```bash
# Check all component namespaces
kubectl get pods --all-namespaces | grep -E 'volcano|harbor|kserve|prometheus|opencost|vault|gatekeeper|argo'

# Check GPU resources (if applicable)
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.capacity.nvidia\.com/gpu

# Verify Volcano
kubectl get pods -n volcano-system

# Verify Harbor
kubectl get svc -n harbor harbor

# Verify KServe
kubectl get crd inferenceservices.serving.kserve.io

# Verify Prometheus
kubectl get pods -n monitoring

# Verify Vault
kubectl get pods -n vault

# Verify Gatekeeper
kubectl get pods -n gatekeeper-system
```

## Component Details

### 01. GPU Resources

Enables GPU sharing and efficient scheduling for ML workloads.

- **NVIDIA GPU Operator**: Manages NVIDIA GPU drivers and runtime
- **HAMi**: GPU device plugin for fractional GPU allocation
- **Use cases**: Multi-tenant GPU sharing, cost optimization

[Read more: GPU Resources README](01-gpu-resources/README.md)

### 02. Training Infrastructure

Distributed training with gang scheduling and GPU support.

- **Volcano**: Kubernetes-native batch scheduler
- **Features**: Gang scheduling, fair sharing, queue management
- **Use cases**: PyTorch distributed training, hyperparameter tuning

[Read more: Training README](02-training/README.md)

### 03. Model Registry

Version control and supply chain security for ML models.

- **Harbor**: OCI-compliant registry with vulnerability scanning
- **KitOps**: Git-like workflows for ML artifacts
- **in-toto/Sigstore**: SBOM generation, model signing, provenance
- **Use cases**: Model versioning, security scanning, compliance

[Read more: Model Registry README](03-model-registry/README.md)

### 04. Model Serving

Serverless inference with autoscaling and canary deployments.

- **KServe**: Unified API for PyTorch, TensorFlow, ONNX, Hugging Face
- **Knative**: Serverless runtime with scale-to-zero
- **Istio**: Traffic management and canary rollouts
- **Use cases**: Production model serving, A/B testing, cost optimization

[Read more: Model Serving README](04-model-serving/README.md)

### 05. Observability

Comprehensive metrics and monitoring for ML workloads.

- **Prometheus**: Metrics collection and alerting
- **Grafana**: Dashboards for training, serving, and GPU metrics
- **Pre-built dashboards**: 6 dashboards (GPU, training, serving, cost, security)
- **Use cases**: Performance monitoring, anomaly detection, capacity planning

[Read more: Observability README](05-observability/README.md)

### 06. Cost Attribution

Track and optimize ML infrastructure costs.

- **OpenCost**: Kubernetes cost allocation
- **Features**: Per-team, per-model, per-job cost tracking
- **Integrations**: Prometheus, Grafana dashboards
- **Use cases**: Chargeback, budget tracking, cost optimization

[Read more: Cost Attribution README](06-cost-attribution/README.md)

### 07. Security & Governance

Enterprise-grade security and compliance.

- **Vault**: Secrets management with dynamic credentials
- **OPA Gatekeeper**: Policy enforcement (15+ policies)
- **RBAC**: Role-based access control (5 roles)
- **Network Policies**: Namespace isolation
- **Use cases**: Compliance (SOC 2, HIPAA), secrets rotation, audit logging

[Read more: Security README](07-security/README.md)

### 08. CI/CD Automation

End-to-end ML pipeline automation.

- **Argo Workflows**: DAG-based ML pipelines
- **Argo Events**: Event-driven triggers
- **Features**: Training pipelines, model promotion, automated testing
- **Use cases**: MLOps automation, continuous training, deployment automation

[Read more: CI/CD README](08-cicd/README.md)

## Architecture Patterns

### Multi-Tenancy

The platform supports multi-tenant ML teams with:

- **Namespace isolation**: Each team gets dedicated namespace(s)
- **RBAC**: Fine-grained access control per team
- **Network policies**: Default-deny with selective allows
- **Resource quotas**: CPU, memory, GPU limits per team
- **Cost tracking**: OpenCost attribution per team

Example team setup:
```bash
# Create namespace for ml-team-a
kubectl create namespace ml-team-a

# Apply RBAC
kubectl apply -f 07-security/rbac/rbac-namespace-isolation.yaml

# Set resource quotas
kubectl apply -f examples/team-quotas.yaml

# Configure cost attribution
kubectl label namespace ml-team-a team=ml-team-a
```

### High Availability

Production deployment recommendations:

- **Harbor**: 2+ replicas with PVC persistence
- **Vault**: 3 replicas with HA Raft storage
- **KServe**: minScale ≥ 2 for critical models
- **Prometheus**: Remote write to long-term storage
- **GPU nodes**: 3+ nodes for fault tolerance

### Disaster Recovery

Backup strategies:

- **Harbor**: Persistent volumes + S3 backup
- **Vault**: Raft snapshots to S3 (daily)
- **Prometheus**: Remote write to Thanos/Cortex
- **Models**: Multi-region Harbor replication

## Use Cases

### 1. Training a Model

```bash
# Submit distributed training job
kubectl apply -f examples/pytorch-distributed-training.yaml

# Monitor with Grafana
# Dashboard: Training Jobs Overview

# Track costs
# Dashboard: OpenCost - Team Costs
```

### 2. Deploying a Model

```bash
# Package model with KitOps
kit pack . -t harbor.example.com/models/my-model:v1.0

# Push to Harbor
kit push harbor.example.com/models/my-model:v1.0

# Sign with Cosign
cosign sign harbor.example.com/models/my-model:v1.0

# Deploy with KServe
kubectl apply -f examples/kserve-inference-service.yaml
```

### 3. Monitoring & Alerts

```bash
# View GPU utilization
# Grafana Dashboard: GPU Metrics

# Check model latency
# Grafana Dashboard: KServe Metrics

# Alert on high error rate
# Prometheus Alert: ModelErrorRate > 1%
```

## Troubleshooting

### Component Health Checks

```bash
# Check all component pods
kubectl get pods --all-namespaces -o wide

# Check component logs
kubectl logs -n <namespace> <pod-name>

# Describe failed pods
kubectl describe pod -n <namespace> <pod-name>
```

### Common Issues

#### GPU Not Available

```bash
# Check NVIDIA GPU Operator
kubectl get pods -n gpu-operator

# Check GPU resources
kubectl get nodes -o json | jq '.items[].status.capacity["nvidia.com/gpu"]'

# View HAMi logs
kubectl logs -n kube-system -l app=hami
```

#### Harbor Not Accessible

```bash
# Check Harbor pods
kubectl get pods -n harbor

# Check Harbor service
kubectl get svc -n harbor harbor

# View Harbor core logs
kubectl logs -n harbor -l app=harbor-core
```

#### KServe Model Not Ready

```bash
# Check InferenceService status
kubectl describe inferenceservice <name> -n <namespace>

# Check predictor pod logs
kubectl logs -n <namespace> -l serving.kserve.io/inferenceservice=<name>

# Common causes: Storage URI incorrect, credentials missing, resource limits too low
```

#### Vault Sealed

```bash
# Check Vault status
kubectl exec -n vault vault-0 -- vault status

# Unseal Vault (requires unseal keys)
kubectl exec -n vault vault-0 -- vault operator unseal <key1>
kubectl exec -n vault vault-0 -- vault operator unseal <key2>
kubectl exec -n vault vault-0 -- vault operator unseal <key3>
```

## Security Considerations

### Before Production Deployment

**Critical actions required:**

1. **Change all default passwords**
   - Harbor admin password
   - Grafana admin password
   - Database passwords

2. **Revoke Vault root token**
   ```bash
   vault token revoke <root-token>
   ```

3. **Enable TLS**
   - Harbor: Use cert-manager or external TLS
   - Vault: Enable TLS for all connections
   - KServe: Configure Istio mutual TLS

4. **Configure external authentication**
   - Harbor: Enable OIDC or LDAP
   - Grafana: Configure SSO
   - Vault: Enable OIDC or AppRole

5. **Enable audit logging**
   - Vault audit logs to file/syslog
   - Kubernetes audit logging
   - Gatekeeper audit mode → enforcement

6. **Review Gatekeeper policies**
   - Test in audit mode first
   - Adjust policies for your organization
   - Document policy exceptions

See [Security README](07-security/README.md) for complete security checklist.

## Performance Tuning

### Training Performance

- **GPU**: Use HAMi for fractional GPUs on small models
- **Batch size**: Tune based on GPU memory
- **Storage**: Use fast SSD PVCs for datasets
- **Network**: Deploy CNI with RDMA support for multi-node

### Serving Performance

- **Autoscaling**: Set target concurrency based on model latency
- **Cold starts**: minScale ≥ 1 for critical models
- **GPU**: Use full GPU for large models (LLMs)
- **Batching**: Enable dynamic batching in KServe

### Cost Optimization

- **Scale-to-zero**: Enable for non-critical models (80% savings)
- **Spot instances**: Use for training jobs (70% savings)
- **GPU sharing**: Use HAMi for small models (50% savings)
- **Storage**: Use S3/object storage instead of PVCs

## Contributing

This repository is designed for KubeCon 2026 EU tutorial. To contribute:

1. Fork the repository
2. Create a feature branch
3. Test changes in minikube or kind
4. Submit pull request with:
   - Description of changes
   - Test results
   - Updated documentation

## Support

For issues and questions:

- GitHub Issues: [Create an issue](../../issues)
- Tutorial: See [docs/tutorials/](../docs/tutorials/)
- Examples: See [examples/](../examples/)

## References

### CNCF Projects

- [Kubernetes](https://kubernetes.io/)
- [Harbor](https://goharbor.io/)
- [Volcano](https://volcano.sh/)
- [Prometheus](https://prometheus.io/)
- [Grafana](https://grafana.com/)
- [OpenCost](https://opencost.io/)

### Security & Governance

- [HashiCorp Vault](https://www.vaultproject.io/)
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/)
- [Sigstore](https://www.sigstore.dev/)
- [in-toto](https://in-toto.io/)

### ML/AI

- [KServe](https://kserve.github.io/)
- [Knative](https://knative.dev/)
- [Istio](https://istio.io/)
- [KitOps](https://github.com/jozu-ai/kitops)

### GPU

- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [HAMi](https://github.com/Project-HAMi/HAMi)

## License

See [LICENSE](../LICENSE) file in repository root.

---

**KubeCon 2026 EU Tutorial**
*Building Production-Ready MLOps Platforms with CNCF Tools*
