#!/usr/bin/env bash
# ABOUTME: Validation script to check Kubernetes cluster prerequisites for CNCF MLOps pipeline
# ABOUTME: Verifies GPU nodes, storage classes, Kubernetes version, and required tools

set -euo pipefail

# Color output for readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

# Track overall validation status
VALIDATION_PASSED=true

# Print section header
print_section() {
    echo ""
    echo "==========================================="
    echo "$1"
    echo "==========================================="
}

# Print success message
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Print warning message
print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Print error message
print_error() {
    echo -e "${RED}✗${NC} $1"
    VALIDATION_PASSED=false
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate kubectl is installed
validate_kubectl() {
    print_section "Checking Required Tools"

    if command_exists kubectl; then
        local version
        version=$(kubectl version --client --short 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
        print_success "kubectl installed (version ${version})"
    else
        print_error "kubectl not found. Install: https://kubernetes.io/docs/tasks/tools/"
        return 1
    fi
}

# Validate cluster connectivity
validate_cluster_access() {
    print_section "Checking Cluster Access"

    if kubectl cluster-info >/dev/null 2>&1; then
        print_success "Cluster accessible"
    else
        print_error "Cannot connect to Kubernetes cluster. Check kubeconfig."
        return 1
    fi
}

# Validate Kubernetes version
validate_k8s_version() {
    print_section "Checking Kubernetes Version"

    local version
    version=$(kubectl version --short 2>/dev/null | grep "Server Version" | grep -oE '[0-9]+\.[0-9]+' || echo "0.0")
    local major minor
    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)

    if [ "$major" -ge 1 ] && [ "$minor" -ge 28 ]; then
        print_success "Kubernetes version ${version} (>= 1.28 required)"
    else
        print_warning "Kubernetes version ${version} detected. Recommended: >= 1.28"
    fi
}

# Validate GPU nodes
validate_gpu_nodes() {
    print_section "Checking GPU Nodes"

    local gpu_node_count
    gpu_node_count=$(kubectl get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l)

    if [ "$gpu_node_count" -ge 2 ]; then
        print_success "Found $gpu_node_count GPU nodes (>= 2 required for distributed training)"

        # Show GPU details
        echo ""
        echo "GPU Node Details:"
        kubectl get nodes -l nvidia.com/gpu.present=true -o custom-columns=\
NAME:.metadata.name,\
GPU-TYPE:.metadata.labels.nvidia\.com/gpu\.product,\
GPU-COUNT:.status.capacity.nvidia\.com/gpu
    elif [ "$gpu_node_count" -eq 1 ]; then
        print_warning "Found only 1 GPU node. Distributed training examples will not work."
    else
        print_error "No GPU nodes found. Label GPU nodes with: nvidia.com/gpu.present=true"
    fi
}

# Validate storage classes
validate_storage_classes() {
    print_section "Checking Storage Classes"

    local storage_count
    storage_count=$(kubectl get storageclasses --no-headers 2>/dev/null | wc -l)

    if [ "$storage_count" -ge 1 ]; then
        print_success "Found $storage_count storage class(es)"

        # Check for default storage class
        if kubectl get storageclass -o json | grep -q '"is-default-class":"true"'; then
            print_success "Default storage class configured"
        else
            print_warning "No default storage class set. Set with: kubectl patch storageclass <name> -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'"
        fi
    else
        print_error "No storage classes found. Create storage class for persistent volumes."
    fi
}

# Validate namespace quotas (optional but recommended)
validate_namespace_setup() {
    print_section "Checking Namespace Setup"

    # Check if ml-training namespace exists (example namespace)
    if kubectl get namespace ml-training >/dev/null 2>&1; then
        print_success "Namespace 'ml-training' exists"
    else
        print_warning "Namespace 'ml-training' not found. Create with: kubectl create ns ml-training"
    fi
}

# Validate GPU operator (optional)
validate_gpu_operator() {
    print_section "Checking GPU Operator (Optional)"

    if kubectl get pods -n gpu-operator >/dev/null 2>&1; then
        local gpu_operator_pods
        gpu_operator_pods=$(kubectl get pods -n gpu-operator --no-headers 2>/dev/null | grep -c "Running" || echo "0")

        if [ "$gpu_operator_pods" -gt 0 ]; then
            print_success "GPU Operator running ($gpu_operator_pods pods)"
        else
            print_warning "GPU Operator namespace exists but no running pods"
        fi
    else
        print_warning "GPU Operator not installed. Install: https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/"
    fi
}

# Validate Helm (optional but recommended)
validate_helm() {
    print_section "Checking Helm (Optional)"

    if command_exists helm; then
        local version
        version=$(helm version --short 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        print_success "Helm installed (version ${version})"
    else
        print_warning "Helm not found. Many CNCF projects use Helm charts. Install: https://helm.sh/docs/intro/install/"
    fi
}

# Main validation flow
main() {
    echo "CNCF MLOps Pipeline - Prerequisites Validation"
    echo "=============================================="

    validate_kubectl || exit 1
    validate_cluster_access || exit 1
    validate_k8s_version
    validate_gpu_nodes
    validate_storage_classes
    validate_namespace_setup
    validate_gpu_operator
    validate_helm

    # Final summary
    print_section "Validation Summary"

    if [ "$VALIDATION_PASSED" = true ]; then
        print_success "All critical prerequisites validated successfully!"
        echo ""
        echo "Next steps:"
        echo "  1. Review warnings above (if any)"
        echo "  2. Run: ./scripts/setup/quick-start.sh"
        echo "  3. See: docs/getting-started/quickstart.md"
        exit 0
    else
        print_error "Prerequisites validation failed. Fix errors above before proceeding."
        echo ""
        echo "See: docs/getting-started/quickstart.md for setup instructions"
        exit 1
    fi
}

main "$@"
