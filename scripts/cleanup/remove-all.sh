#!/usr/bin/env bash
# ABOUTME: Removes all CNCF MLOps pipeline components from the cluster.
# ABOUTME: Deletes resources in reverse installation order to avoid dependency issues.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "============================================"
echo "  CNCF MLOps Pipeline - Cleanup"
echo "============================================"
echo ""
echo "WARNING: This will remove ALL tutorial components."
echo "Press Ctrl+C within 5 seconds to cancel..."
sleep 5
echo ""

# Remove in reverse order of installation
echo "--- Removing security policies ---"
kubectl delete -f "$REPO_ROOT/components/07-security/policies/gatekeeper-policies.yaml" --ignore-not-found
echo ""

echo "--- Removing cost attribution ---"
kubectl delete -f "$REPO_ROOT/components/06-cost-attribution/opencost/opencost-install.yaml" --ignore-not-found
echo ""

echo "--- Removing model serving ---"
kubectl delete -f "$REPO_ROOT/components/04-model-serving/kserve/kserve-install.yaml" --ignore-not-found
echo ""

echo "--- Removing training infrastructure ---"
kubectl delete -f "$REPO_ROOT/components/02-training/hami/hami-install.yaml" --ignore-not-found
kubectl delete -f "$REPO_ROOT/components/02-training/volcano/volcano-install.yaml" --ignore-not-found
echo ""

echo "--- Removing data pipeline ---"
kubectl delete -f "$REPO_ROOT/components/01-data-pipeline/argo-workflows/argo-workflows-install.yaml" --ignore-not-found
echo ""

echo "--- Removing namespaces ---"
for ns in ml-data ml-training ml-serving monitoring ml-security; do
    kubectl delete namespace "$ns" --ignore-not-found
    echo "  Removed namespace '$ns'"
done
echo ""

echo "============================================"
echo "  CLEANUP COMPLETE"
echo "  All tutorial components have been removed."
echo "============================================"
