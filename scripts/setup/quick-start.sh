#!/usr/bin/env bash
# ABOUTME: Deploys the complete CNCF MLOps pipeline to a Kubernetes cluster.
# ABOUTME: Installs all components in order: data pipeline, training, registry, serving, monitoring, security.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "============================================"
echo "  CNCF MLOps Pipeline - Quick Start"
echo "============================================"
echo ""
echo "This will deploy the complete MLOps pipeline."
echo "Estimated time: 5-10 minutes"
echo ""

# Validate prerequisites first
echo "--- Step 1/7: Validating prerequisites ---"
"$SCRIPT_DIR/validate-setup.sh"
echo ""

# Create namespaces
echo "--- Step 2/7: Creating namespaces ---"
for ns in ml-data ml-training ml-serving monitoring ml-security; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
    echo "  Namespace '$ns' ready"
done
echo ""

# Install data pipeline components
echo "--- Step 3/7: Installing data pipeline (Kafka, Argo Workflows) ---"
kubectl apply -f "$REPO_ROOT/components/01-data-pipeline/argo-workflows/argo-workflows-install.yaml"
echo "  Argo Workflows installed"
echo ""

# Install training components
echo "--- Step 4/7: Installing training infrastructure (Volcano, HAMi) ---"
kubectl apply -f "$REPO_ROOT/components/02-training/volcano/volcano-install.yaml"
echo "  Volcano scheduler installed"
kubectl apply -f "$REPO_ROOT/components/02-training/hami/hami-install.yaml"
echo "  HAMi GPU sharing installed"
echo ""

# Install model serving
echo "--- Step 5/7: Installing model serving (KServe) ---"
kubectl apply -f "$REPO_ROOT/components/04-model-serving/kserve/kserve-install.yaml"
echo "  KServe installed"
echo ""

# Install cost monitoring
echo "--- Step 6/7: Installing cost attribution (OpenCost) ---"
kubectl apply -f "$REPO_ROOT/components/06-cost-attribution/opencost/opencost-install.yaml"
echo "  OpenCost installed"
echo ""

# Install security policies
echo "--- Step 7/7: Installing security policies (Gatekeeper, Vault) ---"
kubectl apply -f "$REPO_ROOT/components/07-security/policies/gatekeeper-policies.yaml"
echo "  Gatekeeper policies installed"
echo ""

echo "============================================"
echo "  DEPLOYMENT COMPLETE"
echo ""
echo "  Next steps:"
echo "  1. Deploy an example pipeline:"
echo "     kubectl apply -f examples/complete-pipeline/fraud-detection-pipeline.yaml"
echo "  2. Check the OpenCost dashboard for cost visibility"
echo "  3. Follow the tutorials in docs/tutorials/"
echo "============================================"
