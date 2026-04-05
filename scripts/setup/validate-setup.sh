#!/usr/bin/env bash
# ABOUTME: Validates that all prerequisites are installed and cluster is ready for the tutorial.
# ABOUTME: Checks kubectl, helm, GPU operator, namespaces, and resource availability.
set -euo pipefail

echo "============================================"
echo "  CNCF MLOps Pipeline - Setup Validation"
echo "============================================"
echo ""

ERRORS=0

check_command() {
    local cmd="$1"
    local min_version="${2:-}"
    if command -v "$cmd" &> /dev/null; then
        local version
        version=$("$cmd" version --client --short 2>/dev/null || "$cmd" version 2>/dev/null || echo "installed")
        echo "[PASS] $cmd found: $version"
    else
        echo "[FAIL] $cmd not found. Please install it."
        ERRORS=$((ERRORS + 1))
    fi
}

check_namespace() {
    local ns="$1"
    if kubectl get namespace "$ns" &> /dev/null; then
        echo "[PASS] Namespace '$ns' exists"
    else
        echo "[WARN] Namespace '$ns' does not exist (will be created during setup)"
    fi
}

echo "--- Checking required CLI tools ---"
check_command kubectl
check_command helm
check_command git
check_command curl
check_command jq

echo ""
echo "--- Checking Kubernetes cluster access ---"
if kubectl cluster-info &> /dev/null; then
    CONTEXT=$(kubectl config current-context)
    echo "[PASS] Connected to cluster: $CONTEXT"

    NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    echo "[INFO] Cluster has $NODE_COUNT node(s)"
else
    echo "[FAIL] Cannot connect to Kubernetes cluster"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "--- Checking GPU availability ---"
GPU_NODES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null | grep -v "^$" || true)
if [ -n "$GPU_NODES" ]; then
    echo "[PASS] GPU nodes found:"
    echo "$GPU_NODES" | while read -r line; do echo "       $line"; done
else
    echo "[WARN] No GPU nodes detected. GPU workloads will not schedule."
fi

echo ""
echo "--- Checking expected namespaces ---"
for ns in ml-training ml-serving ml-data monitoring; do
    check_namespace "$ns"
done

echo ""
echo "--- Checking storage classes ---"
SC_COUNT=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l)
if [ "$SC_COUNT" -gt 0 ]; then
    echo "[PASS] $SC_COUNT storage class(es) available"
else
    echo "[WARN] No storage classes found. Persistent volumes may fail."
fi

echo ""
echo "============================================"
if [ "$ERRORS" -gt 0 ]; then
    echo "  VALIDATION FAILED: $ERRORS error(s) found"
    echo "  Please fix the issues above before proceeding."
    echo "============================================"
    exit 1
else
    echo "  VALIDATION PASSED"
    echo "  Your cluster is ready for the tutorial."
    echo "============================================"
fi
