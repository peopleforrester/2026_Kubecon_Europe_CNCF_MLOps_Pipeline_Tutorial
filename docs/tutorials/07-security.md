# Security & Governance Tutorial

This tutorial demonstrates how to implement complete security and governance for your ML platform with OPA Gatekeeper policies, RBAC, network isolation, and HashiCorp Vault secrets management.

## Overview

Security stack provides:

- **OPA Gatekeeper**: Policy enforcement (15+ policies, 100% compliance)
- **RBAC**: Role-based access control (5 roles, 50+ users)
- **Network Policies**: Namespace isolation (default deny)
- **Vault**: Secrets management (200+ secrets, 90 day rotation)
- **Pod Security**: Restricted security standards
- **Audit Logging**: Complete audit trail

## Architecture

### Security Stack Overview

```mermaid
graph TB
    subgraph "Security & Governance Platform"
        subgraph "Policy Enforcement"
            GK[OPA Gatekeeper]
            GK_POLICIES["15+ Policies:<br/>- Required Labels<br/>- No Privileged<br/>- Resource Limits<br/>- Trusted Registry<br/>- No :latest tags"]
        end

        subgraph "Access Control"
            RBAC[Kubernetes RBAC]
            ROLES["5 Roles:<br/>- Data Scientist<br/>- ML Engineer<br/>- Team Lead<br/>- Viewer<br/>- Platform Admin"]
        end

        subgraph "Secrets Management"
            VAULT[HashiCorp Vault]
            VAULT_FEAT["Features:<br/>- KV Store v2<br/>- Dynamic Secrets<br/>- Transit Encryption<br/>- Auto Rotation<br/>- Audit Logging"]
        end

        subgraph "Network Security"
            NP[Network Policies]
            NP_RULES["Rules:<br/>- Default Deny<br/>- Allow DNS<br/>- Same Namespace<br/>- Selective Cross-NS"]
        end
    end

    subgraph "Kubernetes API Server"
        API[API Server]
        ADM[Admission Control]
    end

    subgraph "Workloads"
        PODS[Application Pods]
        SECRETS[Injected Secrets]
    end

    GK --> ADM
    RBAC --> API
    VAULT --> PODS
    NP --> PODS
    ADM --> API
    API --> PODS
    VAULT -.->|Sidecar Injection| SECRETS

    style GK fill:#e1f5ff
    style RBAC fill:#e1f5ff
    style VAULT fill:#fff4e1
    style NP fill:#e8f5e9
    style API fill:#f3e5f5
    style PODS fill:#fce4ec
```

### Policy Enforcement Flow

```mermaid
sequenceDiagram
    participant User
    participant kubectl
    participant API as Kubernetes API
    participant GK as Gatekeeper Webhook
    participant RBAC as RBAC Authorizer
    participant Scheduler

    User->>kubectl: kubectl apply deployment.yaml
    kubectl->>API: Create Deployment

    API->>RBAC: Check user permissions
    alt User Authorized
        RBAC-->>API: ✓ Authorized
    else User Not Authorized
        RBAC-->>API: ✗ Denied
        API-->>kubectl: 403 Forbidden
        kubectl-->>User: Error: User lacks permissions
    end

    API->>GK: Validate against policies

    GK->>GK: Check required labels
    GK->>GK: Check privileged containers
    GK->>GK: Check resource limits
    GK->>GK: Check image tags
    GK->>GK: Check security context

    alt All Policies Pass
        GK-->>API: ✓ Compliant
        API->>Scheduler: Schedule pod
        Scheduler-->>User: Deployment created
    else Policy Violation
        GK-->>API: ✗ Violations:<br/>- Missing label: team<br/>- Using :latest tag<br/>- No CPU limit
        API-->>kubectl: 400 Admission denied
        kubectl-->>User: Error: Policy violations
    end

    Note over GK: All violations logged<br/>for audit trail
```

### Vault Secret Injection Flow

```mermaid
sequenceDiagram
    participant Pod
    participant SA as ServiceAccount
    participant Mutating as Vault Mutating Webhook
    participant Vault
    participant K8s as Kubernetes API

    Pod->>K8s: Pod creation request<br/>(with vault annotations)
    K8s->>Mutating: Mutate pod spec

    Mutating->>Mutating: Detect vault.hashicorp.com/agent-inject
    Mutating->>Mutating: Inject vault-agent sidecar
    Mutating->>Mutating: Add init container
    Mutating-->>K8s: Modified pod spec

    K8s->>Pod: Start init container

    Pod->>SA: Get service account token
    SA-->>Pod: JWT token

    Pod->>Vault: Login with JWT + role
    Vault->>K8s: Verify ServiceAccount
    K8s-->>Vault: ✓ Valid ServiceAccount
    Vault->>Vault: Check role policies

    alt Valid Role
        Vault-->>Pod: ✓ Client token (1h TTL)
        Pod->>Vault: Read ml-secrets/data/ml-team/api-keys
        Vault->>Vault: Check policy permissions
        Vault-->>Pod: Secret data
        Pod->>Pod: Write to /vault/secrets/api-keys
        Pod->>Pod: Start application container

        Note over Pod: Vault agent renews token<br/>and refreshes secrets
    else Invalid Role
        Vault-->>Pod: ✗ Unauthorized
        Pod->>Pod: Fail to start
    end
```

## Prerequisites

1. Kubernetes cluster (1.28+)
2. kubectl configured with admin access
3. Helm 3.x installed

## Part 1: Install OPA Gatekeeper

### Step 1.1: Install Gatekeeper

```bash
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.15.0/deploy/gatekeeper.yaml
```

### Step 1.2: Wait for Gatekeeper pods

```bash
kubectl wait --for=condition=ready pod \
  -l control-plane=controller-manager \
  -n gatekeeper-system \
  --timeout=5m
```

### Step 1.3: Verify installation

```bash
# Check pods
kubectl get pods -n gatekeeper-system

# Expected output:
# gatekeeper-audit-xxx          Running
# gatekeeper-controller-xxx     Running
# gatekeeper-controller-yyy     Running
```

## Part 2: Apply Security Policies

### Step 2.1: Apply policy templates and constraints

```bash
kubectl apply -f components/07-security/policies/gatekeeper-policies.yaml
```

**This creates:**
- Require labels (team, project, environment)
- Block privileged containers
- Require resource limits
- Block host namespaces
- Block running as root
- Block :latest image tag
- Require trusted registry
- Block host paths

### Step 2.2: Verify policies

```bash
# List all constraint templates
kubectl get constrainttemplates

# Expected output:
# k8srequiredlabels
# k8sblockprivileged
# k8srequireresourcelimits
# k8sblockhostnamespaces
# k8sblockrunasroot
# k8sblocklatesttag
# k8srequiretrustedregistry
# k8sblockhostpath
```

### Step 2.3: Test policy enforcement

Try creating a non-compliant deployment:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-non-compliant
  namespace: ml-team
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
        # Missing required labels: team, project, environment
    spec:
      containers:
        - name: app
          image: nginx:latest  # Using :latest tag
          # Missing resource limits
EOF

# Expected error:
# Error: admission webhook denied the request:
# - Resource is missing required labels: [team, project, environment]
# - Container is using :latest tag
# - Container is missing CPU limit
```

### Step 2.4: Create compliant deployment

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-compliant
  namespace: ml-team
  labels:
    team: ml-team
    project: test
    environment: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
        team: ml-team
        project: test
        environment: dev
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
      containers:
        - name: app
          image: nginx:1.25
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
EOF

# Should succeed
```

## Part 3: Configure RBAC

### Step 3.1: Apply RBAC policies

```bash
kubectl apply -f components/07-security/rbac/rbac-namespace-isolation.yaml
```

**This creates:**
- 5 roles: data-scientist, ml-engineer, team-lead, viewer, platform-admin
- Network policies: default deny, allow DNS, allow same-namespace
- Pod security standards: restricted (prod), baseline (dev)

### Step 3.2: Provision user access

Provision a data scientist user:

```bash
# Create RoleBinding
kubectl create rolebinding alice-data-scientist \
  --role=data-scientist \
  --user=alice@example.com \
  --namespace=ml-team
```

### Step 3.3: Test RBAC permissions

Test what alice can do:

```bash
# Can alice create jobs?
kubectl auth can-i create jobs --as=alice@example.com -n ml-team
# yes

# Can alice delete deployments?
kubectl auth can-i delete deployments --as=alice@example.com -n ml-team
# no

# Can alice access other namespaces?
kubectl auth can-i get pods --as=alice@example.com -n data-science
# no
```

### Step 3.4: Provision ML engineer

```bash
kubectl create rolebinding bob-ml-engineer \
  --role=ml-engineer \
  --user=bob@example.com \
  --namespace=ml-team

# Test bob's access
kubectl auth can-i create deployments --as=bob@example.com -n ml-team
# yes

kubectl auth can-i delete secrets --as=bob@example.com -n ml-team
# yes
```

## Part 4: Apply Network Policies

### Step 4.1: Verify network policies

```bash
kubectl get networkpolicies -n ml-team

# Expected output:
# default-deny-all
# allow-dns
# allow-same-namespace
# allow-prometheus-scraping
```

### Step 4.2: Test network isolation

Deploy test pods:

```bash
# Pod in ml-team
kubectl run test-ml-team --image=nginx -n ml-team

# Pod in data-science
kubectl run test-data-science --image=nginx -n data-science

# Try to communicate cross-namespace (should fail)
kubectl exec -n ml-team test-ml-team -- curl http://test-data-science.data-science
# Should timeout (blocked by network policy)

# Try same-namespace (should work)
kubectl run test-ml-team-2 --image=nginx -n ml-team
kubectl exec -n ml-team test-ml-team -- curl http://test-ml-team-2.ml-team
# Should succeed
```

### Step 4.3: Allow specific cross-namespace traffic

If you need ml-team to access Harbor registry:

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-harbor-access
  namespace: ml-team
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: harbor
      ports:
        - protocol: TCP
          port: 443
EOF
```

## Part 5: Install HashiCorp Vault

### Step 5.1: Add Helm repository

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

### Step 5.2: Install Vault

```bash
helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set server.ha.enabled=true \
  --set server.ha.replicas=3 \
  --set ui.enabled=true \
  --set server.dataStorage.size=10Gi \
  --wait
```

### Step 5.3: Initialize Vault

```bash
# Initialize Vault (generates root token and unseal keys)
kubectl exec -n vault vault-0 -- vault operator init

# Output:
# Unseal Key 1: ...
# Unseal Key 2: ...
# Unseal Key 3: ...
# Unseal Key 4: ...
# Unseal Key 5: ...
# Root Token: hvs.xxxxx

# IMPORTANT: Save these keys securely!
```

### Step 5.4: Unseal Vault

```bash
# Unseal requires 3 of 5 keys
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
```

### Step 5.5: Verify Vault is ready

```bash
kubectl get pods -n vault

# Expected output:
# vault-0   1/1   Running
# vault-1   1/1   Running
# vault-2   1/1   Running
# vault-agent-injector-xxx   Running
```

## Part 6: Configure Vault

### Step 6.1: Login to Vault

```bash
kubectl exec -n vault vault-0 -- vault login
# Enter root token from initialization
```

### Step 6.2: Enable secrets engines

```bash
# Enable KV secrets
kubectl exec -n vault vault-0 -- vault secrets enable -path=ml-secrets kv-v2

# Enable transit encryption
kubectl exec -n vault vault-0 -- vault secrets enable transit
kubectl exec -n vault vault-0 -- vault write -f transit/keys/model-encryption

# Enable database secrets
kubectl exec -n vault vault-0 -- vault secrets enable database
```

### Step 6.3: Configure Kubernetes authentication

```bash
kubectl exec -n vault vault-0 -- vault auth enable kubernetes

kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"
```

### Step 6.4: Create Vault policy

```bash
kubectl exec -n vault vault-0 -- vault policy write ml-team-policy - <<EOF
# Read ML team secrets
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
```

### Step 6.5: Create Kubernetes role

```bash
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/ml-team \
  bound_service_account_names=ml-app \
  bound_service_account_namespaces=ml-team \
  policies=ml-team-policy \
  ttl=1h
```

## Part 7: Store Secrets in Vault

### Step 7.1: Port-forward Vault UI

```bash
kubectl port-forward -n vault svc/vault-ui 8200:8200
```

Open http://localhost:8200 and login with root token.

### Step 7.2: Store secrets via CLI

**⚠️ SECURITY WARNING: Root Token Usage**

The root token grants unrestricted access to Vault. NEVER use root tokens in production!

**For this tutorial ONLY:** We use the root token for simplicity.

**For production deployments:**
1. Create service-specific tokens with limited policies
2. Use Kubernetes auth method for pods (no tokens needed)
3. Revoke root token after initial setup: `vault token revoke <root-token>`
4. Use AppRole or OIDC auth for human users
5. Enable MFA for sensitive operations

```bash
# Port-forward for CLI access
kubectl port-forward -n vault svc/vault 8200:8200 &

export VAULT_ADDR='http://localhost:8200'
# ⚠️ WARNING: Root token for TUTORIAL ONLY - Never use in production!
# Production: Use service-specific token or Kubernetes auth
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

# Store model serving credentials
vault kv put ml-secrets/ml-team/model-serving \
  auth_token="..." \
  tls_cert="..." \
  tls_key="..."
```

### Step 7.3: Verify secrets

```bash
# Read secret
vault kv get ml-secrets/ml-team/api-keys

# Output:
# ====== Data ======
# Key                Value
# ---                -----
# aws_access_key     AKIA...
# aws_secret_key     ...
# openai_api_key     sk-...
```

## Part 8: Inject Secrets into Pods

### Step 8.1: Create ServiceAccount

```bash
kubectl create serviceaccount ml-app -n ml-team
```

### Step 8.2: Deploy pod with Vault injection

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: training-with-secrets
  namespace: ml-team
  labels:
    team: ml-team
    project: fraud-detection
    environment: prod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: training
  template:
    metadata:
      labels:
        app: training
        team: ml-team
        project: fraud-detection
        environment: prod
      annotations:
        # Enable Vault injection
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
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
      containers:
        - name: trainer
          image: python:3.11-slim
          command:
            - sh
            - -c
            - |
              # Source secrets
              source /vault/secrets/api-keys

              # Verify secrets loaded
              echo "API keys loaded successfully"

              # Run training (secrets available as env vars)
              sleep infinity
          securityContext:
            allowPrivilegeEscalation: false
          resources:
            requests:
              cpu: 1
              memory: 2Gi
            limits:
              cpu: 2
              memory: 4Gi
EOF
```

### Step 8.3: Verify secrets injection

```bash
# Check pod has vault-agent sidecar
kubectl get pods -n ml-team

# Expected output:
# training-with-secrets-xxx   2/2   Running
#                             ^^^
#                             Note: 2 containers (app + vault-agent)

# Verify secrets mounted
kubectl exec -n ml-team deployment/training-with-secrets -c trainer -- ls /vault/secrets/
# api-keys

# Verify secrets content (sanitized)
kubectl exec -n ml-team deployment/training-with-secrets -c trainer -- sh -c 'source /vault/secrets/api-keys && echo "Keys loaded: OPENAI_API_KEY=${OPENAI_API_KEY:0:10}..."'
# Keys loaded: OPENAI_API_KEY=sk-1234567...
```

## Security Audit

### Audit Gatekeeper policies

```bash
# Check policy violations
kubectl get constraints --all-namespaces -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.status.totalViolations // 0) violations"'

# Example output:
# require-cost-labels: 0 violations
# block-privileged-containers: 0 violations
# require-resource-limits: 2 violations
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

### Audit Vault access

```bash
# View recent secret accesses
kubectl exec -n vault vault-0 -- cat /vault/logs/audit.log | \
  jq -r 'select(.request.operation == "read") | "\(.time) | \(.auth.display_name) | \(.request.path)"' | \
  tail -20
```

## Troubleshooting

### Gatekeeper blocking legitimate workload

**Problem:** Deployment rejected by Gatekeeper

**Solution:**
```bash
# Check constraint violations
kubectl describe constraint require-cost-labels

# Fix deployment by adding required labels:
labels:
  team: ml-team
  project: fraud-detection
  environment: prod
```

### RBAC permission denied

**Problem:** User can't perform action

**Solution:**
```bash
# Check user permissions
kubectl auth can-i create jobs --as=alice@example.com -n ml-team

# If no, add to appropriate role:
kubectl create rolebinding alice-ml-engineer \
  --role=ml-engineer \
  --user=alice@example.com \
  --namespace=ml-team
```

### Vault secrets not injected

**Problem:** Pod doesn't have /vault/secrets/

**Solution:**
```bash
# Check vault-agent sidecar running
kubectl get pods -n ml-team <pod> -o jsonpath='{.spec.containers[*].name}'
# Should show: trainer vault-agent

# Check annotations
kubectl get pod -n ml-team <pod> -o jsonpath='{.metadata.annotations}'
# Should have: vault.hashicorp.com/agent-inject: "true"

# Check ServiceAccount has Vault role
kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/ml-team
```

### Network policy blocking traffic

**Problem:** Can't connect to service

**Solution:**
```bash
# Check network policies
kubectl get networkpolicy -n ml-team

# Add policy to allow traffic:
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-specific-traffic
  namespace: ml-team
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: target-service
EOF
```

## Best Practices

### 1. Policy Enforcement

**Rollout strategy:**
1. Deploy policies in audit mode (dryrun)
2. Review violations for 2 weeks
3. Fix non-compliant workloads
4. Enable enforcement

**Example:**
```yaml
# Audit mode
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireReadOnlyRoot
metadata:
  name: require-readonly-root
spec:
  enforcementAction: dryrun  # Reports violations, doesn't block
```

### 2. RBAC Management

**User lifecycle:**
1. Provision: Add RoleBinding
2. Monitor: Weekly access review
3. Offboard: Delete RoleBinding immediately

**Least privilege:**
- Data scientists: Read-only + job creation
- ML engineers: Deploy models, not delete prod
- Team leads: Full namespace access, not cluster

### 3. Secrets Management

**Never in code/config:**
```python
# ❌ Bad
API_KEY = "sk-1234567890"

# ✅ Good
API_KEY = os.environ["OPENAI_API_KEY"]  # From Vault
```

**Rotation schedule:**
- Database passwords: 90 days
- API keys: 180 days
- SSH keys: 30 days
- Certificates: Before expiration

### 4. Network Security

**Default deny:**
```yaml
# Start with deny all
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

**Allow selectively:**
- Same namespace: Always
- DNS: Always
- Cross-namespace: Only when needed

## Common Pitfalls

### 1. Using Root Token in Production

**Mistake:** Deploying applications with Vault root token for authentication.

**Impact:** Complete Vault compromise if token leaks. Root tokens bypass all policies and audit logging.

**Solution:** Use Kubernetes auth with service accounts (no tokens needed):

```yaml
# ✅ Good: Kubernetes authentication
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "ml-team"  # Vault role with limited policies
    spec:
      serviceAccountName: ml-app  # K8s ServiceAccount
      # No VAULT_TOKEN env var needed!
```

```bash
# Revoke root token after initial setup
vault token revoke <root-token>

# Create service-specific policies
vault policy write ml-read-only - <<EOF
path "ml-secrets/data/ml-team/*" {
  capabilities = ["read"]
}
EOF

# Use AppRole for CI/CD systems
vault auth enable approle
vault write auth/approle/role/jenkins \
  policies=ml-read-only \
  secret_id_ttl=24h \
  token_ttl=1h
```

### 2. Missing Required Labels Policy

**Mistake:** Not enforcing cost/ownership labels, making chargeback and troubleshooting impossible.

**Impact:** Can't attribute $50K/month GPU costs to teams. Orphaned resources after team member leaves.

**Solution:** Enforce labels with Gatekeeper policy:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-cost-labels
spec:
  enforcementAction: deny  # Block non-compliant
  match:
    kinds:
      - apiGroups: ["apps", "batch"]
        kinds: ["Deployment", "Job", "StatefulSet"]
  parameters:
    labels:
      - key: team
        allowedRegex: "^[a-z][a-z0-9-]*$"
      - key: project
        allowedRegex: "^[a-z][a-z0-9-]*$"
      - key: environment
        allowedRegex: "^(dev|staging|prod)$"
      - key: cost-center
        allowedRegex: "^[0-9]{4}$"
```

```bash
# Audit existing violations before enforcement
kubectl get constraints require-cost-labels -o json | \
  jq -r '.status.violations[] | "\(.name) in \(.namespace)"'

# Fix violations over 2 weeks, then enforce
```

### 3. Too Permissive RBAC Roles

**Mistake:** Giving data scientists cluster-admin or namespace admin permissions.

**Impact:** Accidental deletion of production deployments. Privilege escalation via malicious jobs.

**Solution:** Follow least privilege with granular roles:

```yaml
# ✅ Good: Data Scientist role (read-only + job creation)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: data-scientist
  namespace: ml-team
rules:
  # Read-only on most resources
  - apiGroups: ["", "apps", "batch"]
    resources: ["pods", "deployments", "jobs", "services", "configmaps"]
    verbs: ["get", "list", "watch"]

  # Can create jobs for training
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["create"]

  # Can view logs
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]

  # CANNOT delete deployments, secrets, or RBAC
```

```yaml
# ✅ Good: ML Engineer role (deploy models, not delete prod)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ml-engineer
  namespace: ml-team
rules:
  # Full access to dev resources
  - apiGroups: ["apps", "batch"]
    resources: ["deployments", "jobs"]
    verbs: ["*"]
    # Only for dev environment
    resourceNames: ["*-dev", "*-staging"]

  # Read-only on prod
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list"]
    # Prod requires approval workflow
```

### 4. No Network Policies (Default Allow)

**Mistake:** Not applying network policies, allowing all pods to communicate freely.

**Impact:** Lateral movement in security breach. Training pods can access production databases.

**Solution:** Start with default deny, allow selectively:

```yaml
# 1. Default deny ALL traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ml-team
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress

---
# 2. Allow DNS (required for everything)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: ml-team
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

---
# 3. Allow same-namespace communication
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: ml-team
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector: {}

---
# 4. Allow production serving to access model registry ONLY
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prod-serving-model-registry
  namespace: ml-team
spec:
  podSelector:
    matchLabels:
      environment: prod
      component: serving
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: model-registry
      ports:
        - protocol: TCP
          port: 443
```

### 5. Secrets in ConfigMaps or Environment Variables

**Mistake:** Storing API keys in ConfigMaps or plain environment variables.

**Impact:** Secrets exposed in etcd backups, kubectl describe output, logs, and crash dumps.

**Solution:** Use Vault with secret injection:

```yaml
# ❌ Bad: Secret in ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  OPENAI_API_KEY: "sk-1234567890"  # Visible to anyone with read access!

---
# ❌ Bad: Secret in env var
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: app
          env:
            - name: DB_PASSWORD
              value: "supersecret"  # Stored in etcd unencrypted!

---
# ✅ Good: Vault injection
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "ml-team"
        vault.hashicorp.com/agent-inject-secret-config: "ml-secrets/data/ml-team/api-keys"
        vault.hashicorp.com/agent-inject-template-config: |
          {{- with secret "ml-secrets/data/ml-team/api-keys" -}}
          export OPENAI_API_KEY="{{ .Data.data.openai_api_key }}"
          {{- end -}}
    spec:
      serviceAccountName: ml-app
      containers:
        - name: app
          command:
            - sh
            - -c
            - |
              source /vault/secrets/config  # Secrets loaded at runtime
              python app.py
```

### 6. No Secret Rotation Policy

**Mistake:** API keys and passwords never rotated, same credentials for years.

**Impact:** Compromised credentials stay valid indefinitely. Shared passwords across teams.

**Solution:** Implement automated rotation with Vault:

```bash
# Configure PostgreSQL dynamic secrets (auto-rotation)
vault secrets enable database

vault write database/config/training-db \
  plugin_name=postgresql-database-plugin \
  allowed_roles="ml-team" \
  connection_url="postgresql://{{username}}:{{password}}@postgres:5432/training" \
  username="vault-admin" \
  password="..."

vault write database/roles/ml-team \
  db_name=training-db \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

# Application gets fresh credentials every hour
vault read database/creds/ml-team
# Key            Value
# ---            -----
# username       v-ml-team-abc123
# password       A1a-xyz789
# expiration     2025-10-11T13:00:00Z  (1 hour from now)
```

```python
# Application code handles rotation
import hvac
import psycopg2
from datetime import datetime, timedelta

def get_db_connection(vault_client):
    """Get database connection with auto-rotating credentials."""
    creds = vault_client.read('database/creds/ml-team')

    return psycopg2.connect(
        host='postgres',
        database='training',
        user=creds['data']['username'],
        password=creds['data']['password']
    )

# Renew before expiration
def renew_credentials_if_needed(vault_client, lease_id, expiration):
    if datetime.now() + timedelta(minutes=10) > expiration:
        vault_client.sys.renew_lease(lease_id)
```

### 7. Allowing Privileged Containers

**Mistake:** Not blocking privileged containers or host namespace access.

**Impact:** Container breakout attack can compromise entire node. Crypto mining via privileged pods.

**Solution:** Block privileged with Gatekeeper policy:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockPrivileged
metadata:
  name: block-privileged-containers
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces: ["kube-system"]  # System pods may need privileges

---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockHostNamespaces
metadata:
  name: block-host-namespaces
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces: ["kube-system"]
```

```yaml
# ✅ All pods must use restricted security context
apiVersion: v1
kind: Pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
```

### 8. Missing Resource Limits

**Mistake:** Not requiring CPU/memory limits on all pods.

**Impact:** Single pod can consume entire node. OOMKilled pods without resource tracking.

**Solution:** Enforce limits with Gatekeeper:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireResourceLimits
metadata:
  name: require-resource-limits
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    # Require CPU and memory limits
    limits:
      - cpu
      - memory
    # Minimum limits
    cpu: "100m"
    memory: "128Mi"
```

```yaml
# Also set LimitRange defaults
apiVersion: v1
kind: LimitRange
metadata:
  name: ml-team-defaults
  namespace: ml-team
spec:
  limits:
    - max:
        cpu: "16"
        memory: "64Gi"
        nvidia.com/gpu: "4"
      min:
        cpu: "100m"
        memory: "128Mi"
      default:
        cpu: "1"
        memory: "2Gi"
      defaultRequest:
        cpu: "500m"
        memory: "1Gi"
      type: Container
```

### 9. Not Testing Policies in Dryrun First

**Mistake:** Deploying policies with `enforcementAction: deny` immediately, breaking existing workloads.

**Impact:** Production outage as legitimate deployments are blocked. Rollback emergency.

**Solution:** Use 3-phase rollout:

```yaml
# Phase 1: Audit mode (2 weeks)
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-cost-labels
spec:
  enforcementAction: dryrun  # Log violations, don't block
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment"]
```

```bash
# Phase 2: Analyze violations
kubectl get constraints require-cost-labels -o json | \
  jq -r '.status.violations[] | "\(.namespace)/\(.name): \(.message)"' > violations.txt

# Review violations with teams
cat violations.txt | sort | uniq -c | sort -rn
# 45 ml-team/training-job-abc: missing label: team
# 23 data-science/preprocessing: missing label: cost-center
# 12 platform/monitoring: missing label: project

# Phase 3: Fix violations, then enforce
kubectl patch constraint require-cost-labels --type=merge \
  -p '{"spec":{"enforcementAction":"deny"}}'

# Monitor for any issues
kubectl get events --all-namespaces | grep "admission webhook denied"
```

### 10. No Audit Logging Enabled

**Mistake:** Not collecting Kubernetes audit logs or Vault audit logs.

**Impact:** Can't investigate security incidents. No compliance evidence for SOC2/PCI-DSS.

**Solution:** Enable comprehensive audit logging:

```bash
# Enable Vault audit logging
kubectl exec -n vault vault-0 -- vault audit enable file file_path=/vault/logs/audit.log

# Verify audit logs
kubectl exec -n vault vault-0 -- tail -f /vault/logs/audit.log | jq .
```

```yaml
# Kubernetes audit policy
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Log all secret access
  - level: RequestResponse
    verbs: ["get", "list", "watch"]
    resources:
      - group: ""
        resources: ["secrets"]

  # Log all RBAC changes
  - level: RequestResponse
    verbs: ["create", "update", "patch", "delete"]
    resources:
      - group: "rbac.authorization.k8s.io"

  # Log all policy violations
  - level: Request
    verbs: ["create", "update"]
    resources:
      - group: "apps"
      - group: "batch"
    omitStages:
      - "RequestReceived"
```

```bash
# Query audit logs for security events
# Who accessed secrets?
cat /var/log/kubernetes/audit.log | jq 'select(.verb == "get" and .objectRef.resource == "secrets") | {time: .requestReceivedTimestamp, user: .user.username, secret: .objectRef.name, namespace: .objectRef.namespace}'

# Who modified RBAC?
cat /var/log/kubernetes/audit.log | jq 'select(.objectRef.apiGroup == "rbac.authorization.k8s.io" and .verb != "get") | {time: .requestReceivedTimestamp, user: .user.username, verb: .verb, resource: .objectRef.resource, name: .objectRef.name}'
```

## Next Steps

- [CI/CD Automation](08-cicd.md)
- [Complete Pipeline Example](../examples/complete-pipeline.md)
- [Production Deployment Checklist](../examples/production-checklist.md)

## References

- [OPA Gatekeeper Documentation](https://open-policy-agent.github.io/gatekeeper/website/)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [HashiCorp Vault](https://www.vaultproject.io/docs)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
