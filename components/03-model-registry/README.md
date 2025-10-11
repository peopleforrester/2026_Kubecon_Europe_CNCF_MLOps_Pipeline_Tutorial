# Model Registry

Version control, storage, and supply chain security for ML models and artifacts.

## Overview

The Model Registry provides enterprise-grade storage for ML models with complete supply chain security, vulnerability scanning, and Git-like workflows.

### Components

1. **Harbor** (CNCF Graduated)
   - OCI-compliant registry for model containers
   - Vulnerability scanning with Trivy
   - Image signing with Notary
   - Multi-tenancy with RBAC
   - Replication for disaster recovery

2. **KitOps**
   - Git-like workflows for ML artifacts
   - Pack, push, pull, tag models
   - OCI-native storage
   - Model cards and metadata

3. **in-toto / Sigstore**
   - SBOM (Software Bill of Materials) generation
   - Cryptographic model signing with Cosign
   - Provenance tracking (training lineage)
   - Supply chain attestations

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Model Registry Flow                      │
└─────────────────────────────────────────────────────────────┘

Training Job              Harbor Registry              Deployment
┌──────────┐             ┌──────────────┐            ┌──────────┐
│  Train   │──pack──────▶│  ml-models/  │◀──pull────│  KServe  │
│  Model   │             │  llama2-7b   │            │  Server  │
│          │             │   :1.0.0     │            │          │
│  - Data  │             │              │            │          │
│  - Code  │             │  Tags:       │            │          │
│  - Config│             │  - dev       │            │          │
└──────────┘             │  - staging   │            └──────────┘
     │                   │  - prod      │
     │                   │  - latest    │
     └──sign + SBOM─────▶│              │
           Cosign        │  Security:   │
                         │  - Trivy     │
                         │  - Notary    │
                         │  - RBAC      │
                         └──────────────┘
```

## Quick Start

### Prerequisites

- Kubernetes 1.28+
- kubectl with admin access
- Helm 3.x
- 500Gi storage for model artifacts

### Installation

#### 1. Install Harbor

```bash
# Add Harbor Helm repo
helm repo add harbor https://helm.goharbor.io
helm repo update

# Install Harbor
helm install harbor harbor/harbor \
  --namespace harbor \
  --create-namespace \
  --set expose.type=loadBalancer \
  --set externalURL=https://harbor.ml-platform.example.com \
  --set harborAdminPassword="$(openssl rand -base64 32)" \
  --set persistence.enabled=true \
  --set persistence.persistentVolumeClaim.registry.size=500Gi \
  --set trivy.enabled=true \
  --set notary.enabled=true

# Wait for Harbor to be ready
kubectl wait --for=condition=ready pod -l app=harbor -n harbor --timeout=10m

# Get Harbor URL
kubectl get svc -n harbor harbor
```

#### 2. Configure Harbor Projects

```bash
export HARBOR_URL="https://$(kubectl get svc -n harbor harbor -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
export HARBOR_PASSWORD="<your-password-from-install>"

# Create ML models project
curl -X POST "$HARBOR_URL/api/v2.0/projects" \
  -u "admin:$HARBOR_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "project_name": "ml-models",
    "public": false,
    "metadata": {
      "auto_scan": "true",
      "severity": "high"
    }
  }'
```

#### 3. Install KitOps

```bash
# Install KitOps CLI
curl -LO https://github.com/jozu-ai/kitops/releases/download/v0.2.0/kit-linux-x86_64.tar.gz
tar -xzf kit-linux-x86_64.tar.gz
sudo mv kit /usr/local/bin/
kit version

# Login to Harbor
echo "$HARBOR_PASSWORD" | kit login $HARBOR_URL \
  --username admin \
  --password-stdin
```

#### 4. Install Cosign (for signing)

```bash
curl -LO https://github.com/sigstore/cosign/releases/download/v2.2.3/cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign
chmod +x /usr/local/bin/cosign
cosign version
```

### Usage Examples

#### Package and Push a Model

```bash
# Create Kitfile
cat > Kitfile << 'EOF'
manifestVersion: 1.0
package:
  name: fraud-detection
  version: 1.0.0
  description: Fraud detection model for credit card transactions
  authors:
    - name: ML Team
      email: ml-team@example.com

model:
  name: fraud-detection
  path: ./model
  framework: pytorch
  version: 2.1.0

code:
  - path: ./train.py
  - path: ./inference.py
  - path: ./requirements.txt
EOF

# Pack model
kit pack . -t $HARBOR_URL/ml-models/fraud-detection:1.0.0

# Push to Harbor
kit push $HARBOR_URL/ml-models/fraud-detection:1.0.0
```

#### Sign Model with Cosign

```bash
MODEL_IMAGE="$HARBOR_URL/ml-models/fraud-detection:1.0.0"

# Sign model (keyless signing with OIDC)
export COSIGN_EXPERIMENTAL=1
cosign sign --yes $MODEL_IMAGE

# Verify signature
cosign verify \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  $MODEL_IMAGE
```

#### Generate and Attach SBOM

```bash
# Install Syft
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

# Generate SBOM
syft $MODEL_IMAGE -o spdx-json > sbom.spdx.json

# Attach SBOM as attestation
cosign attest \
  --yes \
  --predicate sbom.spdx.json \
  --type spdx \
  $MODEL_IMAGE

# Verify SBOM
cosign verify-attestation \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  --type spdx \
  $MODEL_IMAGE | jq .
```

#### Model Versioning

```bash
MODEL_NAME="fraud-detection"
VERSION="1.0.0"

# Semantic versioning
kit tag $HARBOR_URL/ml-models/$MODEL_NAME:$VERSION \
  $HARBOR_URL/ml-models/$MODEL_NAME:1.0.0-$(git rev-parse --short HEAD)

# Environment tags
kit tag $HARBOR_URL/ml-models/$MODEL_NAME:$VERSION \
  $HARBOR_URL/ml-models/$MODEL_NAME:dev

kit tag $HARBOR_URL/ml-models/$MODEL_NAME:$VERSION \
  $HARBOR_URL/ml-models/$MODEL_NAME:latest

# Push all tags
kit push $HARBOR_URL/ml-models/$MODEL_NAME:dev
kit push $HARBOR_URL/ml-models/$MODEL_NAME:latest
```

#### Pull and Unpack Model

```bash
# Pull model
kit pull $HARBOR_URL/ml-models/fraud-detection:1.0.0

# Unpack to directory
kit unpack $HARBOR_URL/ml-models/fraud-detection:1.0.0 -d ./model-artifacts

# Inspect contents
ls -la ./model-artifacts/
```

## Features

### Vulnerability Scanning

Harbor automatically scans all models with Trivy:

```bash
# View scan results via API
curl -u "admin:$HARBOR_PASSWORD" \
  "$HARBOR_URL/api/v2.0/projects/ml-models/repositories/fraud-detection/artifacts/1.0.0" \
  | jq '.scan_overview'

# Block deployment if critical vulnerabilities found
# Configure in Harbor UI: Projects → ml-models → Configuration → Automatically scan images
```

### Multi-Tenancy

Create separate projects per team:

```bash
# Create project for ml-team-a
curl -X POST "$HARBOR_URL/api/v2.0/projects" \
  -u "admin:$HARBOR_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "project_name": "ml-team-a",
    "public": false,
    "metadata": {
      "auto_scan": "true",
      "reuse_sys_cve_allowlist": "true"
    }
  }'

# Assign RBAC roles
# Go to Harbor UI → Projects → ml-team-a → Members → Add User
# Roles: Project Admin, Developer, Guest
```

### Replication (Disaster Recovery)

Replicate models across regions:

```bash
# Configure via Harbor UI:
# 1. Administration → Registrations → New Registration Endpoint
# 2. Add remote Harbor: harbor-us-east.example.com
# 3. Administration → Replications → New Replication Rule
# 4. Source: ml-models/* → Destination: harbor-us-east/ml-models/*
# 5. Trigger: Event Based (on push)

# Models automatically replicated to DR site on push
```

### Retention Policies

Keep only recent model versions:

```bash
# Configure via Harbor UI:
# Projects → ml-models → Policy
# Keep last 10 versions of each model
# Run garbage collection weekly
```

## Model Promotion Workflow

### Dev → Staging → Production

```bash
# 1. Train and tag as dev
kit pack . -t $HARBOR_URL/ml-models/fraud-detection:1.0.0-dev
kit push $HARBOR_URL/ml-models/fraud-detection:1.0.0-dev
cosign sign --yes $HARBOR_URL/ml-models/fraud-detection:1.0.0-dev

# 2. Run tests in dev environment
kubectl run test --rm -i --restart=Never \
  --image=$HARBOR_URL/ml-models/fraud-detection:1.0.0-dev \
  -- python -m pytest /tests/

# 3. Promote to staging
docker pull $HARBOR_URL/ml-models/fraud-detection:1.0.0-dev
docker tag $HARBOR_URL/ml-models/fraud-detection:1.0.0-dev \
  $HARBOR_URL/ml-models/fraud-detection:1.0.0-staging
docker push $HARBOR_URL/ml-models/fraud-detection:1.0.0-staging

# 4. Manual approval (team lead)
echo "Approve promotion to production? (yes/no)"
read APPROVAL
if [ "$APPROVAL" = "yes" ]; then
  # 5. Promote to prod
  docker tag $HARBOR_URL/ml-models/fraud-detection:1.0.0-staging \
    $HARBOR_URL/ml-models/fraud-detection:1.0.0-prod
  docker push $HARBOR_URL/ml-models/fraud-detection:1.0.0-prod
fi
```

## Supply Chain Security

### Complete SBOM Example

```bash
# 1. Train model (capture metadata)
python train.py --output-provenance provenance.json

# 2. Pack with KitOps
kit pack . -t $HARBOR_URL/ml-models/fraud-detection:1.0.0

# 3. Push to Harbor
kit push $HARBOR_URL/ml-models/fraud-detection:1.0.0

# 4. Generate SBOM
syft $HARBOR_URL/ml-models/fraud-detection:1.0.0 -o spdx-json > sbom.json

# 5. Attach SBOM
cosign attest --yes --predicate sbom.json --type spdx \
  $HARBOR_URL/ml-models/fraud-detection:1.0.0

# 6. Attach provenance
cosign attest --yes --predicate provenance.json --type slsaprovenance \
  $HARBOR_URL/ml-models/fraud-detection:1.0.0

# 7. Sign model
cosign sign --yes $HARBOR_URL/ml-models/fraud-detection:1.0.0

# 8. Scan for vulnerabilities
grype $HARBOR_URL/ml-models/fraud-detection:1.0.0
```

### Query SBOM

```bash
# Extract SBOM
cosign verify-attestation \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  --type spdx \
  $HARBOR_URL/ml-models/fraud-detection:1.0.0 \
  | jq '.payload | @base64d | fromjson | .predicate'

# Find all models using PyTorch 2.0.0 (vulnerable version)
# Query Harbor API or SBOM database
```

## Troubleshooting

### Harbor Not Accessible

```bash
# Check Harbor pods
kubectl get pods -n harbor

# Common issues:
# - LoadBalancer not provisioned (check cloud provider)
# - TLS certificate issue (check cert-manager)
# - Database not ready (check harbor-database pod)

# View logs
kubectl logs -n harbor -l app=harbor-core --tail=100
```

### KitOps Push Fails

```bash
# Re-login to Harbor
echo "$HARBOR_PASSWORD" | kit login $HARBOR_URL \
  --username admin \
  --password-stdin

# Check network connectivity
curl -k https://$HARBOR_URL/api/v2.0/systeminfo

# Common causes:
# - Wrong credentials
# - Project doesn't exist
# - Insufficient RBAC permissions
```

### Cosign Signature Verification Fails

```bash
# Check Rekor transparency log
rekor-cli search --artifact $HARBOR_URL/ml-models/fraud-detection:1.0.0

# Verify certificate chain
cosign verify \
  --certificate-identity="ml-team@example.com" \
  --certificate-oidc-issuer="https://accounts.google.com" \
  $HARBOR_URL/ml-models/fraud-detection:1.0.0

# Common causes:
# - Certificate identity mismatch
# - OIDC issuer not trusted
# - Signature not found (model not signed)
```

## Best Practices

### 1. Versioning Strategy

- **Semantic versioning**: MAJOR.MINOR.PATCH (e.g., 1.2.3)
- **Git commit SHA**: Append for traceability (1.2.3-abc1234)
- **Immutable tags**: Never overwrite 1.2.3
- **Mutable tags**: dev, staging, prod, latest

### 2. Security

- **Sign all production models**: Use Cosign keyless signing
- **Attach SBOM**: Required for compliance
- **Scan before deployment**: Block if critical CVEs
- **Rotate credentials**: Use Harbor robot accounts with 90-day expiration

### 3. Storage Management

- **Retention policies**: Keep last 10 versions
- **Garbage collection**: Weekly cleanup of unused layers
- **Replication**: Multi-region for DR
- **Compression**: Use OCI layer compression

### 4. CI/CD Integration

```yaml
# GitHub Actions example
- name: Build and push model
  run: |
    kit pack . -t $HARBOR_URL/ml-models/my-model:${{ github.sha }}
    kit push $HARBOR_URL/ml-models/my-model:${{ github.sha }}
    cosign sign --yes $HARBOR_URL/ml-models/my-model:${{ github.sha }}
```

## Metrics & Monitoring

Monitor Harbor health:

```bash
# Enable Prometheus metrics
kubectl apply -f harbor/harbor-servicemonitor.yaml

# Key metrics:
# - harbor_project_repo_total: Number of repositories
# - harbor_project_artifact_total: Number of artifacts
# - harbor_health: Harbor health status
# - harbor_up: Harbor availability
```

Grafana dashboards:

- **Harbor Overview**: Projects, repos, storage usage
- **Model Registry**: Push/pull rates, vulnerability scan results
- **Replication**: Replication status, bandwidth usage

## Migration

### From Docker Registry

```bash
# Export images from Docker Registry
docker save my-model:1.0 -o my-model.tar

# Import to Harbor
docker load -i my-model.tar
docker tag my-model:1.0 $HARBOR_URL/ml-models/my-model:1.0
docker push $HARBOR_URL/ml-models/my-model:1.0
```

### From S3

```bash
# Pull model from S3
aws s3 cp s3://ml-models/my-model.tar.gz .
tar -xzf my-model.tar.gz

# Pack with KitOps
kit pack . -t $HARBOR_URL/ml-models/my-model:1.0
kit push $HARBOR_URL/ml-models/my-model:1.0
```

## Component Documentation

- **Harbor Installation**: [harbor/harbor-install.yaml](harbor/harbor-install.yaml)
- **KitOps Setup**: [kitops/kitops-install.yaml](kitops/kitops-install.yaml)
- **SBOM Generation**: [in-toto/sbom-generation.yaml](in-toto/sbom-generation.yaml)
- **Sigstore Signing**: [in-toto/sigstore-signing.yaml](in-toto/sigstore-signing.yaml)

## Tutorial

For a complete step-by-step tutorial, see:
[Model Registry & Packaging Tutorial](../../docs/tutorials/03-model-registry.md)

## References

- [Harbor Documentation](https://goharbor.io/docs/)
- [KitOps GitHub](https://github.com/jozu-ai/kitops)
- [Sigstore/Cosign](https://docs.sigstore.dev/)
- [in-toto](https://in-toto.io/)
- [SLSA Framework](https://slsa.dev/)
- [SPDX SBOM Specification](https://spdx.dev/)

---

[← Back to Components](../README.md) | [Next: Model Serving →](../04-model-serving/README.md)
