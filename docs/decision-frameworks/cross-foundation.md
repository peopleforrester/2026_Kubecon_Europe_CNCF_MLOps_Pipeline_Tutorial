# Cross-Foundation Integration: When to Use Non-CNCF Tools

## Overview

While this tutorial prioritizes CNCF graduated and incubating projects, some MLOps capabilities require cross-foundation or ecosystem tools. This guide provides honest assessment of CNCF gaps and recommended alternatives.

**Philosophy:** Use CNCF projects where available. When gaps exist, use Linux Foundation projects (same governance model) or vetted ecosystem tools with clear migration paths.

---

## CNCF MLOps Gap Analysis

| MLOps Stage | CNCF Solution | Gap | Alternative | Foundation |
|-------------|---------------|-----|-------------|------------|
| **Feature Store** | ✗ None | No CNCF project | Feast | LF AI & Data (Incubating) |
| **Experiment Tracking** | Kubeflow Metadata (basic) | Limited features | MLflow | Linux Foundation |
| **Model Monitoring** | Prometheus (infra only) | No ML-specific | Custom + Evidently | Prometheus (CNCF) + ecosystem |
| **Data Versioning** | ✗ None | No CNCF project | DVC, LakeFS | Iterative (vendor), LF (Incubating) |
| **Workflow Orchestration** | Argo Workflows (Graduated) | ✓ Sufficient | - | - |
| **Model Registry** | Harbor (Graduated) | ✓ Sufficient with KitOps | - | - |
| **GPU Scheduling** | Volcano (Incubating) | ✓ Sufficient | - | - |
| **Model Serving** | KServe (Incubating) | ✓ Sufficient | - | - |

---

## Feature Stores: Feast (LF AI & Data)

### The Problem CNCF Doesn't Solve

**Feature stores** manage:
- Feature computation and storage
- Point-in-time correct feature retrieval (training vs inference)
- Feature versioning and lineage
- Low-latency online serving

**No CNCF project provides this.**

### Solution: Feast (LF AI & Data Foundation)

**Status:** LF AI & Data Incubating (same governance model as CNCF)

**Why Feast:**
- Open-source with vendor-neutral governance
- Integrates with CNCF projects (Kubernetes, Prometheus)
- Production deployments at Uber, Twitter, Gojek

### Feast Integration with CNCF Stack

```yaml
# Feast deployed on Kubernetes (CNCF)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: feast-online-serving
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: feast-server
        image: feastdev/feature-server:0.36.0
        env:
          - name: FEAST_REDIS_HOST
            value: redis-service  # Redis for online store
          - name: FEAST_S3_BUCKET
            value: s3://feast-features  # S3 for offline store
```

**Integration Points:**
1. **Data Pipeline:** Argo Workflows → Feast feature ingestion
2. **Training:** Kubeflow reads features from Feast offline store
3. **Serving:** KServe queries Feast online store for real-time features

### Feast Example

```python
# Define features
from feast import Entity, FeatureView, Field
from feast.types import Float32, Int64

user = Entity(name="user", join_keys=["user_id"])

user_features = FeatureView(
    name="user_features",
    entities=[user],
    schema=[
        Field(name="age", dtype=Int64),
        Field(name="avg_purchase_amount", dtype=Float32),
    ],
    source=batch_source,  # Read from S3/BigQuery
)

# Training: Get historical features
training_df = store.get_historical_features(
    entity_df=user_ids,
    features=["user_features:age", "user_features:avg_purchase_amount"],
).to_df()

# Inference: Get online features
features = store.get_online_features(
    features=["user_features:age", "user_features:avg_purchase_amount"],
    entity_rows=[{"user_id": 123}],
).to_dict()
```

### Alternative: Build Custom with CNCF Tools

If Feast is too heavy, build minimal feature store:

```yaml
# Use Harbor (CNCF) for feature versioning
# Use Redis (ecosystem) for online serving
# Use S3 (ecosystem) + Argo Workflows (CNCF) for offline features
```

**Tradeoff:** More engineering effort, fewer guarantees.

---

## Experiment Tracking: MLflow (Linux Foundation)

### The Problem

**Kubeflow Metadata** (CNCF) provides basic experiment tracking:
- ✓ Logs metrics, parameters, artifacts
- ✗ No UI for comparing runs
- ✗ No model registry (separate from training)
- ✗ Limited search/filtering

### Solution: MLflow (Linux Foundation)

**Status:** Linux Foundation project (vendor-neutral)

**Why MLflow:**
- Comprehensive experiment tracking with UI
- Integrated model registry
- Wide adoption (easier to hire engineers familiar with it)

### MLflow Integration with CNCF Stack

```yaml
# MLflow server on Kubernetes
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow-server
spec:
  template:
    spec:
      containers:
      - name: mlflow
        image: python:3.10
        command:
          - mlflow
          - server
          - --backend-store-uri
          - postgresql://mlflow-db:5432/mlflow  # Postgres for metadata
          - --default-artifact-root
          - s3://mlflow-artifacts  # S3 for artifacts
          - --host
          - 0.0.0.0
```

**Integration with Kubeflow:**
```python
# In Kubeflow training job
import mlflow

mlflow.set_tracking_uri("http://mlflow-server.ml-platform.svc.cluster.local")
mlflow.set_experiment("llama2-finetuning")

with mlflow.start_run():
    mlflow.log_param("learning_rate", 1e-4)
    mlflow.log_param("batch_size", 32)

    # Training loop
    for epoch in range(epochs):
        loss = train_epoch()
        mlflow.log_metric("loss", loss, step=epoch)

    # Log model to MLflow registry
    mlflow.pytorch.log_model(model, "model")
```

### Alternative: Use Kubeflow Metadata

If MLflow dependency is unacceptable:

```python
# Kubeflow Metadata (CNCF)
from kubeflow.metadata import metadata

metadata_store = metadata.Store(grpc_host="metadata-grpc-service.kubeflow")
workspace = metadata.Workspace(store=metadata_store, name="workspace")
run = metadata.Run(workspace=workspace, name="run-123")

run.log_metric("loss", 0.5)
run.log_param("learning_rate", 1e-4)
```

**Tradeoff:** Less mature UI, limited features.

---

## Model Monitoring: Prometheus + Custom ML Metrics

### The Problem

**Prometheus (CNCF)** monitors infrastructure:
- ✓ GPU utilization, memory, CPU
- ✗ Model drift (feature distribution changes)
- ✗ Prediction quality (accuracy degradation)
- ✗ Training-serving skew

### Solution: Build Custom with Prometheus + Python

**No open-source CNCF project for ML monitoring.** Commercial options: Evidently AI, WhyLabs.

**DIY Approach:**
```python
# Custom Prometheus exporter for ML metrics
from prometheus_client import Gauge, start_http_server

# Define metrics
prediction_accuracy = Gauge('model_prediction_accuracy', 'Model accuracy')
feature_drift = Gauge('feature_drift_score', 'Feature drift KL divergence')

# In KServe model server
class CustomModel:
    def predict(self, inputs):
        predictions = self.model(inputs)

        # Calculate accuracy (if labels available)
        accuracy = calculate_accuracy(predictions, labels)
        prediction_accuracy.set(accuracy)

        # Calculate feature drift
        drift_score = calculate_drift(inputs, reference_distribution)
        feature_drift.set(drift_score)

        return predictions

# Start Prometheus exporter
start_http_server(8000)
```

**Prometheus Alert:**
```yaml
groups:
  - name: model-quality
    rules:
      - alert: ModelAccuracyDegraded
        expr: model_prediction_accuracy < 0.85
        for: 1h
        annotations:
          summary: "Model accuracy dropped below 85%"

      - alert: FeatureDriftDetected
        expr: feature_drift_score > 0.3
        for: 30m
        annotations:
          summary: "Feature drift detected (KL divergence > 0.3)"
```

### Commercial Alternative: Evidently AI

If budget allows, Evidently AI provides:
- Pre-built drift detection
- Data quality monitoring
- Model performance tracking

**Integration:**
```python
from evidently import ColumnMapping
from evidently.metric_preset import DataDriftPreset
from evidently.report import Report

report = Report(metrics=[DataDriftPreset()])
report.run(reference_data=train_df, current_data=production_df)

# Export to Prometheus
report.save_html("drift_report.html")
```

---

## Data Versioning: DVC or LakeFS

### The Problem

**No CNCF project for dataset versioning.**

Training reproducibility requires:
- Version control for datasets (like Git for data)
- Track data lineage
- Time-travel (reproduce training with historical data)

### Solution 1: DVC (Iterative, vendor-backed)

**Status:** Open-source, VC-backed company (Iterative)

```bash
# Initialize DVC
dvc init

# Track dataset
dvc add data/training-set.parquet

# Commit metadata to Git
git add data/training-set.parquet.dvc .dvc/config
git commit -m "Add training dataset v1"

# Push data to S3
dvc push

# Reproduce training with specific data version
git checkout v1.0
dvc pull  # Downloads training-set.parquet from v1.0
python train.py
```

**Integration with Argo Workflows:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
spec:
  templates:
    - name: load-data
      container:
        image: python:3.10
        command:
          - sh
          - -c
          - |
            pip install dvc[s3]
            dvc pull  # Fetch versioned data
            python train.py
```

### Solution 2: LakeFS (LF AI & Data Sandbox)

**Status:** LF AI & Data Sandbox (newer, less mature than DVC)

Git-like interface for data lakes:

```bash
# Create branch for experiment
lakefs branch create lakefs://repo/experiment-1 --source main

# Modify data in experiment branch
aws s3 cp new-data.parquet lakefs://repo/experiment-1/data/

# Commit changes
lakefs commit lakefs://repo/experiment-1 -m "Add augmented data"

# Merge to main if experiment successful
lakefs merge lakefs://repo/experiment-1 lakefs://repo/main
```

**Recommendation:** DVC for mature solution, LakeFS for LF governance.

---

## Cross-Foundation Integration Pattern

### Layered Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Application Layer (Your ML Models)                      │
└─────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────┐
│  ML Platform Layer                                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │  MLflow  │  │  Feast   │  │  DVC     │              │
│  │   (LF)   │  │(LF AI&D) │  │(vendor)  │              │
│  └──────────┘  └──────────┘  └──────────┘              │
└─────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────┐
│  CNCF MLOps Layer                                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │ KServe   │  │ Volcano  │  │  Argo    │              │
│  │(Incubat) │  │(Incubat) │  │(Graduat) │              │
│  └──────────┘  └──────────┘  └──────────┘              │
└─────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────┐
│  Infrastructure Layer (CNCF)                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │Kubernetes│  │Prometheus│  │ Harbor   │              │
│  │(Graduat) │  │(Graduat) │  │(Graduat) │              │
│  └──────────┘  └──────────┘  └──────────┘              │
└─────────────────────────────────────────────────────────┘
```

**Principle:** CNCF forms the foundation. Cross-foundation tools fill specific gaps.

---

## Vendor Risk Assessment

### Low Risk (LF Projects)

**Feast, MLflow, LakeFS** - Linux Foundation governance
- ✓ Open-source with multiple contributors
- ✓ Vendor-neutral governance
- ✓ Apache 2.0 license
- ✓ Clear succession planning

**Migration Path:** If project archived, fork or migrate to alternative (effort: weeks).

### Medium Risk (VC-Backed Open-Source)

**DVC** - Open-source but single vendor (Iterative)
- ⚠ Company-driven development
- ⚠ Potential for proprietary features
- ✓ Still open-source (Apache 2.0)

**Mitigation:** Use only open-source features, avoid vendor-specific extensions.

### High Risk (Commercial/Closed-Source)

**Evidently AI, WhyLabs** - Closed-source SaaS
- ✗ Vendor lock-in
- ✗ No code access
- ✗ Pricing changes risk

**Mitigation:** Build abstraction layer, use only for non-critical features.

---

## Decision Framework: CNCF First, Then Cross-Foundation

```
Need MLOps capability?
        │
        ▼
┌──────────────────────────────────┐
│ Is there a CNCF graduated         │
│ or incubating project?            │
└──────────────────────────────────┘
        │
        ├─▶ YES ──▶ Use CNCF project (preferred)
        │
        └─▶ NO
                │
                ▼
        ┌──────────────────────────────────┐
        │ Is there a Linux Foundation       │
        │ project (LF AI & Data, etc.)?     │
        └──────────────────────────────────┘
                │
                ├─▶ YES ──▶ Use LF project (same governance)
                │
                └─▶ NO
                        │
                        ▼
                ┌──────────────────────────────────┐
                │ Is there a mature open-source    │
                │ alternative (Apache 2.0)?        │
                └──────────────────────────────────┘
                        │
                        ├─▶ YES ──▶ Evaluate vendor risk
                        │
                        └─▶ NO
                                │
                                ▼
                        ┌──────────────────────────────────┐
                        │ Build custom with CNCF primitives │
                        │ or use commercial tool            │
                        └──────────────────────────────────┘
```

---

## Recommended Cross-Foundation Stack

| Capability | Recommended Tool | Foundation | Rationale |
|------------|------------------|------------|-----------|
| **Feature Store** | Feast | LF AI & Data | Only mature open-source option |
| **Experiment Tracking** | MLflow | Linux Foundation | Better UX than Kubeflow Metadata |
| **Data Versioning** | DVC | Iterative (vendor) | Most mature, wide adoption |
| **Model Monitoring** | Custom (Prometheus) | Build on CNCF | No good open-source alternative |
| **Workflow Orchestration** | Argo Workflows | CNCF (Graduated) | **Use CNCF, no alternative needed** |
| **Model Registry** | Harbor + KitOps | CNCF (Graduated + Sandbox) | **Use CNCF, no alternative needed** |

---

## Migration Strategy

### Phase 1: CNCF Core (Month 1)
- Deploy Kubernetes, Prometheus, Harbor, Argo Workflows
- **No cross-foundation dependencies yet**

### Phase 2: Add Cross-Foundation (Month 2-3)
- Add MLflow for experiment tracking
- Add Feast if feature store needed
- **Integrate with CNCF core**

### Phase 3: Optimize (Month 4+)
- Evaluate if cross-foundation tools worth complexity
- Consider building custom with CNCF primitives if team has bandwidth

**Goal:** Minimize non-CNCF dependencies, use only when clear value.

---

## Conclusion

**CNCF projects cover 80% of MLOps needs.** The remaining 20%:
- **Feature stores:** Feast (LF AI & Data)
- **Experiment tracking:** MLflow (Linux Foundation) or Kubeflow Metadata (basic)
- **Model monitoring:** Build custom with Prometheus
- **Data versioning:** DVC or LakeFS (LF AI & Data)

**Prioritize CNCF, use cross-foundation only when necessary.**

---

## Next Steps

- **CNCF Stack Setup:** [docs/getting-started/quickstart.md](../getting-started/quickstart.md)
- **Feast Integration:** [components/01-data-pipeline/feast/](../../components/01-data-pipeline/feast/)
- **MLflow Setup:** [components/05-observability/mlflow/](../../components/05-observability/mlflow/)
