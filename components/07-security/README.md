# Security & Governance

Enterprise-grade security and compliance for ML platforms using Vault, OPA Gatekeeper, RBAC, and network policies.

## Overview

Comprehensive security controls for ML platforms, providing secrets management, policy enforcement, access control, and network isolation to meet enterprise compliance requirements (SOC 2, HIPAA, PCI DSS).

### Components

1. **HashiCorp Vault**
   - Centralized secrets management
   - Dynamic secrets (auto-generated, short-lived)
   - Encryption as a service
   - Audit logging
   - Secret rotation
   - Fine-grained access policies

2. **OPA Gatekeeper**
   - Policy enforcement (15+ policies)
   - Admission control
   - Audit mode and enforcement
   - Compliance reporting
   - Custom policy templates

3. **RBAC (Role-Based Access Control)**
   - 5 predefined roles
   - Namespace isolation
   - Least privilege principle
   - Service account management

4. **Network Policies**
   - Default deny all traffic
   - Selective egress/ingress rules
   - Namespace isolation
   - Pod-level security

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 Security & Governance Stack                  │
└─────────────────────────────────────────────────────────────┘

Policy Enforcement      Access Control       Secrets Management
┌──────────────┐       ┌──────────────┐      ┌──────────────┐
│  Gatekeeper  │       │     RBAC     │      │    Vault     │
│              │       │              │      │              │
│ 15+ Policies:│       │ 5 Roles:     │      │ Features:    │
│ - Labels ✓   │──────▶│ - Data Sci   │      │ - KV Store   │
│ - Privileged │       │ - ML Engineer│      │ - Dynamic    │
│ - Resources  │       │ - Team Lead  │      │ - Encryption │
│ - Images ✓   │       │ - Admin      │      │ - Rotation   │
└──────────────┘       └──────────────┘      └──────┬───────┘
       │                       │                     │
       │                       │                     │
       ▼                       ▼                     ▼
┌──────────────────────────────────────────────────────────┐
│                   Kubernetes API Server                   │
│                  (Admission Controller)                   │
└──────────────────────────────────────────────────────────┘
       │                       │                     │
       ▼                       ▼                     ▼
┌──────────────┐       ┌──────────────┐      ┌──────────────┐
│ Deny non-    │       │ Authorize    │      │ Inject       │
│ compliant    │       │ requests     │      │ secrets      │
│ resources    │       │              │      │              │
└──────────────┘       └──────────────┘      └──────────────┘

Network Security
┌──────────────────────────────────────────┐
│        Network Policies                   │
│                                          │
│  Default: Deny all                       │
│  Allow:                                  │
│  - DNS                                   │
│  - Same namespace                        │
│  - Prometheus scraping                   │
│  - Explicit cross-namespace (optional)   │
└──────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Kubernetes 1.28+
- kubectl with cluster-admin access
- Helm 3.x

## Part 1: HashiCorp Vault

### Install Vault

```bash
# Add HashiCorp Helm repository
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install Vault with HA
helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set server.ha.enabled=true \
  --set server.ha.replicas=3 \
  --set ui.enabled=true \
  --set server.dataStorage.size=10Gi \
  --wait

# Initialize Vault (generates root token and unseal keys)
kubectl exec -n vault vault-0 -- vault operator init

# ⚠️ CRITICAL: Save output securely!
# Output contains:
# - 5 unseal keys (need 3 to unseal)
# - Root token (initial admin access)
```

### Unseal Vault

```bash
# Unseal each Vault pod (requires 3 of 5 keys)
kubectl exec -n vault vault-0 -- vault operator unseal <key1>
kubectl exec -n vault vault-0 -- vault operator unseal <key2>
kubectl exec -n vault vault-0 -- vault operator unseal <key3>

# Repeat for vault-1 and vault-2
kubectl exec -n vault vault-1 -- vault operator unseal <key1>
kubectl exec -n vault vault-1 -- vault operator unseal <key2>
kubectl exec -n vault vault-1 -- vault operator unseal <key3>

kubectl exec -n vault vault-2 -- vault operator unseal <key1>
kubectl exec -n vault vault-2 -- vault operator unseal <key2>
kubectl exec -n vault vault-2 -- vault operator unseal <key3>

# Verify all pods are ready
kubectl get pods -n vault
```

### Configure Vault

```bash
# Login with root token
kubectl exec -n vault vault-0 -- vault login
# Enter root token from initialization

# Enable KV secrets engine
kubectl exec -n vault vault-0 -- vault secrets enable -path=ml-secrets kv-v2

# Enable Kubernetes authentication
kubectl exec -n vault vault-0 -- vault auth enable kubernetes

# Configure Kubernetes auth
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"

# Create policy for ML team
kubectl exec -n vault vault-0 -- vault policy write ml-team-policy - <<EOF
# Read ML secrets
path "ml-secrets/data/ml-team/*" {
  capabilities = ["read", "list"]
}

# Use encryption
path "transit/encrypt/model-encryption" {
  capabilities = ["update"]
}

path "transit/decrypt/model-encryption" {
  capabilities = ["update"]
}
EOF

# Create Kubernetes role
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/ml-team \
  bound_service_account_names=ml-app \
  bound_service_account_namespaces=ml-team \
  policies=ml-team-policy \
  ttl=1h
```

### Store Secrets in Vault

```bash
# Port-forward for CLI access
kubectl port-forward -n vault svc/vault 8200:8200 &

export VAULT_ADDR='http://localhost:8200'
export VAULT_TOKEN='<root-token>'

# Store API keys
vault kv put ml-secrets/ml-team/api-keys \
  openai_api_key="sk-..." \
  aws_access_key="AKIA..." \
  aws_secret_key="..."

# Store database credentials
vault kv put ml-secrets/ml-team/databases \
  training_db_host="postgres.example.com" \
  training_db_user="ml_user" \
  training_db_password="..."

# Verify
vault kv get ml-secrets/ml-team/api-keys
```

### Inject Secrets into Pods

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ml-app
  namespace: ml-team
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: training-with-secrets
  namespace: ml-team
spec:
  replicas: 1
  selector:
    matchLabels:
      app: training
  template:
    metadata:
      labels:
        app: training
      annotations:
        # Enable Vault agent injection
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "ml-team"

        # Inject API keys
        vault.hashicorp.com/agent-inject-secret-api-keys: "ml-secrets/data/ml-team/api-keys"
        vault.hashicorp.com/agent-inject-template-api-keys: |
          {{- with secret "ml-secrets/data/ml-team/api-keys" -}}
          export OPENAI_API_KEY="{{ .Data.data.openai_api_key }}"
          export AWS_ACCESS_KEY_ID="{{ .Data.data.aws_access_key }}"
          export AWS_SECRET_ACCESS_KEY="{{ .Data.data.aws_secret_key }}"
          {{- end -}}
    spec:
      serviceAccountName: ml-app
      containers:
        - name: trainer
          image: python:3.11-slim
          command:
            - sh
            - -c
            - |
              # Source secrets from Vault
              source /vault/secrets/api-keys

              # Verify secrets loaded
              echo "API keys loaded successfully"

              # Run training (secrets available as env vars)
              python train.py
```

## Part 2: OPA Gatekeeper

### Install Gatekeeper

```bash
# Install Gatekeeper
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.15.0/deploy/gatekeeper.yaml

# Wait for pods
kubectl wait --for=condition=ready pod \
  -l control-plane=controller-manager \
  -n gatekeeper-system \
  --timeout=5m

# Verify installation
kubectl get pods -n gatekeeper-system
```

### Apply Security Policies

Gatekeeper provides 15+ security policies for ML platforms:

#### 1. Require Labels Policy

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels
      validation:
        openAPIV3Schema:
          properties:
            labels:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels

        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Missing required labels: %v", [missing])
        }
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-cost-labels
spec:
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment"]
    namespaces: ["ml-team-a", "ml-team-b"]
  parameters:
    labels:
      - "team"
      - "project"
      - "environment"
```

#### 2. Block Privileged Containers

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockPrivileged
metadata:
  name: block-privileged-containers
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces: ["kube-system", "gpu-operator"]
```

#### 3. Require Resource Limits

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireResourceLimits
metadata:
  name: require-resource-limits
spec:
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment"]
  parameters:
    resources: ["cpu", "memory"]
```

#### 4. Block :latest Tag

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockLatestTag
metadata:
  name: block-latest-tag
spec:
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment"]
    namespaces: ["ml-serving"]
```

#### 5. Require Trusted Registry

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireTrustedRegistry
metadata:
  name: require-trusted-registry
spec:
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment"]
  parameters:
    registries:
      - "harbor.ml-platform.example.com"
      - "gcr.io"
      - "docker.io/library"  # Official images only
```

### Test Policy Enforcement

```bash
# Try creating non-compliant deployment (should fail)
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-non-compliant
  namespace: ml-team-a
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
        # Missing: team, project, environment labels
    spec:
      containers:
        - name: app
          image: nginx:latest  # Using :latest tag
          # Missing: resource limits
EOF

# Expected error:
# Error from server: admission webhook denied the request:
# - Missing required labels: [team, project, environment]
# - Container is using :latest tag
# - Container is missing CPU limit
```

## Part 3: RBAC Configuration

### 5 Standard Roles

#### 1. Data Scientist Role

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: data-scientist
  namespace: ml-team-a
rules:
  # Can create training jobs
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["create", "get", "list", "watch"]

  # Can view pods and logs
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]

  # Cannot delete or modify deployments
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch"]

  # Cannot access secrets
```

#### 2. ML Engineer Role

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ml-engineer
  namespace: ml-team-a
rules:
  # Full control over deployments and services
  - apiGroups: ["apps", ""]
    resources: ["deployments", "services", "configmaps"]
    verbs: ["*"]

  # Can manage InferenceServices
  - apiGroups: ["serving.kserve.io"]
    resources: ["inferenceservices"]
    verbs: ["*"]

  # Can read secrets (but not create)
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list"]
```

#### 3. Team Lead Role

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: team-lead
  namespace: ml-team-a
rules:
  # Full control over namespace resources
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]

  # Cannot modify ResourceQuota or LimitRange
  - apiGroups: [""]
    resources: ["resourcequotas", "limitranges"]
    verbs: ["get", "list", "watch"]
```

#### 4. Viewer Role (Read-Only)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: viewer
  namespace: ml-team-a
rules:
  # Read-only access to most resources
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
```

#### 5. Platform Admin Role

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: platform-admin
rules:
  # Full cluster access (excluding kube-system)
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]
```

### Assign Roles to Users

```bash
# Create RoleBinding for user
kubectl create rolebinding alice-data-scientist \
  --role=data-scientist \
  --user=alice@example.com \
  --namespace=ml-team-a

# Test permissions
kubectl auth can-i create jobs --as=alice@example.com -n ml-team-a
# yes

kubectl auth can-i delete deployments --as=alice@example.com -n ml-team-a
# no
```

## Part 4: Network Policies

### Default Deny All

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ml-team-a
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

### Allow DNS

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: ml-team-a
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53
```

### Allow Same Namespace

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: ml-team-a
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}
  egress:
    - to:
        - podSelector: {}
```

### Allow Prometheus Scraping

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scraping
  namespace: ml-team-a
spec:
  podSelector:
    matchLabels:
      monitoring: "true"
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
      ports:
        - protocol: TCP
          port: 8080  # Metrics port
```

## Security Audit

### Audit Gatekeeper Policies

```bash
# Check policy violations
kubectl get constraints --all-namespaces -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.status.totalViolations // 0) violations"'

# View specific violations
kubectl get K8sRequiredLabels require-cost-labels -o yaml
```

### Audit RBAC

```bash
# List all users and their roles
kubectl get rolebindings --all-namespaces -o json | \
  jq -r '.items[] | "\(.metadata.namespace) | \(.subjects[].name) | \(.roleRef.name)"'

# Find cluster-admins
kubectl get clusterrolebindings -o json | \
  jq -r '.items[] | select(.roleRef.name == "cluster-admin") | .subjects[].name'
```

### Audit Vault Access

```bash
# View recent secret accesses
kubectl exec -n vault vault-0 -- cat /vault/logs/audit.log | \
  jq -r 'select(.request.operation == "read") | "\(.time) | \(.auth.display_name) | \(.request.path)"' | \
  tail -20
```

## Compliance Reports

### Generate SOC 2 Compliance Report

```bash
cat <<'EOF' > generate_compliance_report.sh
#!/bin/bash

echo "=== ML Platform Security Compliance Report ==="
echo "Generated: $(date)"
echo ""

echo "1. Secrets Management:"
echo "   - Vault Status:"
kubectl get pods -n vault | grep vault
echo ""

echo "2. Policy Enforcement:"
echo "   - Gatekeeper Violations:"
kubectl get constraints --all-namespaces -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.status.totalViolations // 0)"'
echo ""

echo "3. RBAC Configuration:"
echo "   - Total Roles:"
kubectl get roles --all-namespaces | wc -l
echo "   - Total RoleBindings:"
kubectl get rolebindings --all-namespaces | wc -l
echo ""

echo "4. Network Policies:"
echo "   - Total Policies:"
kubectl get networkpolicies --all-namespaces | wc -l
echo ""

echo "5. Audit Logging:"
echo "   - Vault Audit Entries (last 24h):"
kubectl exec -n vault vault-0 -- cat /vault/logs/audit.log | wc -l
EOF

chmod +x generate_compliance_report.sh
./generate_compliance_report.sh
```

## Best Practices

### 1. Secrets Management

```yaml
# ❌ Bad: Hardcoded secrets
env:
  - name: API_KEY
    value: "sk-1234567890"

# ✅ Good: Vault injection
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "ml-team"
  vault.hashicorp.com/agent-inject-secret-api-keys: "ml-secrets/data/ml-team/api-keys"
```

### 2. Policy Rollout

1. Deploy policies in **audit mode** (dryrun)
2. Review violations for 2 weeks
3. Fix non-compliant workloads
4. Enable **enforcement mode**

```yaml
# Audit mode
spec:
  enforcementAction: dryrun  # Reports violations, doesn't block
```

### 3. Least Privilege

```yaml
# Start with minimal permissions
# Add permissions incrementally as needed
# Regular access reviews (quarterly)
```

### 4. Secret Rotation

- Database passwords: 90 days
- API keys: 180 days
- SSH keys: 30 days
- Certificates: Before expiration

## Troubleshooting

### Vault Sealed

```bash
# Check status
kubectl exec -n vault vault-0 -- vault status

# Unseal (requires 3 keys)
kubectl exec -n vault vault-0 -- vault operator unseal <key1>
kubectl exec -n vault vault-0 -- vault operator unseal <key2>
kubectl exec -n vault vault-0 -- vault operator unseal <key3>
```

### Gatekeeper Blocking Legitimate Workload

```bash
# Check violations
kubectl describe constraint require-cost-labels

# Temporarily disable constraint
kubectl patch constraint require-cost-labels \
  --type merge \
  -p '{"spec":{"enforcementAction":"dryrun"}}'

# Fix workload, then re-enable
kubectl patch constraint require-cost-labels \
  --type merge \
  -p '{"spec":{"enforcementAction":"deny"}}'
```

### RBAC Permission Denied

```bash
# Check user permissions
kubectl auth can-i create jobs --as=alice@example.com -n ml-team-a

# If denied, add RoleBinding
kubectl create rolebinding alice-ml-engineer \
  --role=ml-engineer \
  --user=alice@example.com \
  --namespace=ml-team-a
```

## Component Documentation

- **Vault Installation**: [secrets/vault-secrets-management.yaml](secrets/vault-secrets-management.yaml)
- **Gatekeeper Policies**: [policies/gatekeeper-policies.yaml](policies/gatekeeper-policies.yaml)
- **RBAC Configuration**: [rbac/rbac-namespace-isolation.yaml](rbac/rbac-namespace-isolation.yaml)

## Tutorial

For a complete step-by-step tutorial, see:
[Security & Governance Tutorial](../../docs/tutorials/07-security.md)

## References

- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [OPA Gatekeeper Documentation](https://open-policy-agent.github.io/gatekeeper/website/)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)

---

[← Back: Cost Attribution](../06-cost-attribution/README.md) | [Components Overview](../README.md) | [Next: CI/CD Automation →](../08-cicd/README.md)
