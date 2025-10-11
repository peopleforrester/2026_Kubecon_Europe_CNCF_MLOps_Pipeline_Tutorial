#!/usr/bin/env bash
# ABOUTME: GPU validation script to verify NVIDIA GPU Operator installation
# ABOUTME: Checks driver, device plugin, DCGM exporter, and runs sample GPU workload

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VALIDATION_PASSED=true

print_section() {
    echo ""
    echo "==========================================="
    echo "$1"
    echo "==========================================="
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    VALIDATION_PASSED=false
}

# Check GPU Operator namespace exists
check_namespace() {
    print_section "Checking GPU Operator Namespace"

    if kubectl get namespace gpu-operator >/dev/null 2>&1; then
        print_success "Namespace 'gpu-operator' exists"
    else
        print_error "Namespace 'gpu-operator' not found. Install GPU Operator first."
        return 1
    fi
}

# Check GPU Operator pods are running
check_operator_pods() {
    print_section "Checking GPU Operator Pods"

    local total_pods running_pods
    total_pods=$(kubectl get pods -n gpu-operator --no-headers 2>/dev/null | wc -l)
    running_pods=$(kubectl get pods -n gpu-operator --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

    if [ "$running_pods" -gt 0 ]; then
        print_success "GPU Operator pods running: ${running_pods}/${total_pods}"

        # Show pod details
        echo ""
        kubectl get pods -n gpu-operator -o wide
    else
        print_error "No GPU Operator pods running. Check: kubectl get pods -n gpu-operator"
    fi
}

# Check NVIDIA driver is loaded
check_nvidia_driver() {
    print_section "Checking NVIDIA Driver"

    # Check if driver DaemonSet is running
    local driver_pods
    driver_pods=$(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

    if [ "$driver_pods" -gt 0 ]; then
        print_success "NVIDIA driver pods running: $driver_pods"

        # Get driver version from one pod
        local driver_pod
        driver_pod=$(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

        if [ -n "$driver_pod" ]; then
            echo ""
            echo "Driver version:"
            kubectl exec -n gpu-operator "$driver_pod" -- nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "Unable to query driver version"
        fi
    else
        print_warning "No NVIDIA driver pods running. Check: kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset"
    fi
}

# Check device plugin is running
check_device_plugin() {
    print_section "Checking NVIDIA Device Plugin"

    local plugin_pods
    plugin_pods=$(kubectl get pods -n gpu-operator -l app=nvidia-device-plugin-daemonset --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

    if [ "$plugin_pods" -gt 0 ]; then
        print_success "NVIDIA device plugin pods running: $plugin_pods"
    else
        print_warning "No device plugin pods running. GPUs will not be allocatable to pods."
    fi
}

# Check DCGM exporter is running
check_dcgm_exporter() {
    print_section "Checking DCGM Exporter (GPU Metrics)"

    local dcgm_pods
    dcgm_pods=$(kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

    if [ "$dcgm_pods" -gt 0 ]; then
        print_success "DCGM Exporter pods running: $dcgm_pods"

        # Check if metrics endpoint is accessible
        local dcgm_pod
        dcgm_pod=$(kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

        if [ -n "$dcgm_pod" ]; then
            echo ""
            echo "Testing metrics endpoint..."
            if kubectl exec -n gpu-operator "$dcgm_pod" -- curl -s localhost:9400/metrics | grep -q "DCGM_FI_DEV_GPU_UTIL"; then
                print_success "Metrics endpoint responding with GPU utilization data"
            else
                print_warning "Metrics endpoint not responding properly"
            fi
        fi
    else
        print_warning "DCGM Exporter not running. GPU metrics will not be available for Prometheus."
    fi
}

# Check GPU nodes are labeled
check_gpu_node_labels() {
    print_section "Checking GPU Node Labels"

    local gpu_nodes
    gpu_nodes=$(kubectl get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l)

    if [ "$gpu_nodes" -gt 0 ]; then
        print_success "GPU nodes detected: $gpu_nodes"

        echo ""
        echo "GPU Node Details:"
        kubectl get nodes -l nvidia.com/gpu.present=true -o custom-columns=\
NAME:.metadata.name,\
GPU-PRODUCT:.metadata.labels.nvidia\\.com/gpu\\.product,\
GPU-COUNT:.status.capacity.nvidia\\.com/gpu,\
GPU-MEMORY:.metadata.labels.nvidia\\.com/gpu\\.memory
    else
        print_error "No nodes with nvidia.com/gpu.present=true label found"
    fi
}

# Check GPU allocatable resources
check_gpu_allocatable() {
    print_section "Checking GPU Allocatable Resources"

    local total_gpus allocatable_gpus
    total_gpus=$(kubectl get nodes -o json | jq '[.items[].status.capacity."nvidia.com/gpu" | select(. != null) | tonumber] | add' 2>/dev/null || echo "0")
    allocatable_gpus=$(kubectl get nodes -o json | jq '[.items[].status.allocatable."nvidia.com/gpu" | select(. != null) | tonumber] | add' 2>/dev/null || echo "0")

    if [ "$allocatable_gpus" -gt 0 ]; then
        print_success "Allocatable GPUs: ${allocatable_gpus} (Total capacity: ${total_gpus})"
    else
        print_error "No allocatable GPUs found. Device plugin may not be working."
    fi
}

# Run sample GPU workload
run_sample_workload() {
    print_section "Running Sample GPU Workload"

    echo "Deploying CUDA vector-add test pod..."

    # Create test pod
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test-pod
  namespace: default
spec:
  restartPolicy: OnFailure
  containers:
  - name: cuda-test
    image: nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda11.7.1
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

    # Wait for pod to complete
    echo "Waiting for test to complete (max 60 seconds)..."
    local wait_count=0
    while [ $wait_count -lt 60 ]; do
        local phase
        phase=$(kubectl get pod gpu-test-pod -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

        if [ "$phase" == "Succeeded" ]; then
            print_success "GPU test passed! Checking logs..."
            echo ""
            kubectl logs gpu-test-pod 2>/dev/null || echo "Unable to retrieve logs"
            break
        elif [ "$phase" == "Failed" ]; then
            print_error "GPU test failed. Check logs: kubectl logs gpu-test-pod"
            break
        fi

        sleep 2
        wait_count=$((wait_count + 2))
    done

    if [ $wait_count -ge 60 ]; then
        print_warning "GPU test timed out. Check: kubectl describe pod gpu-test-pod"
    fi

    # Cleanup
    echo ""
    echo "Cleaning up test pod..."
    kubectl delete pod gpu-test-pod --ignore-not-found=true >/dev/null 2>&1
}

# Check for common issues
check_common_issues() {
    print_section "Checking for Common Issues"

    # Check if nodes have NoSchedule taint without tolerations
    local tainted_nodes
    tainted_nodes=$(kubectl get nodes -o json | jq -r '.items[] | select(.spec.taints[]? | select(.key == "nvidia.com/gpu" and .effect == "NoSchedule")) | .metadata.name' 2>/dev/null || echo "")

    if [ -n "$tainted_nodes" ]; then
        print_warning "GPU nodes have NoSchedule taint. Ensure pods have tolerations."
        echo "Tainted nodes: $tainted_nodes"
    fi

    # Check if time-slicing is enabled (production anti-pattern)
    local time_slicing_replicas
    time_slicing_replicas=$(kubectl get configmap -n gpu-operator time-slicing-config -o jsonpath='{.data.any}' 2>/dev/null | grep -oP 'replicas:\s*\K\d+' || echo "1")

    if [ "$time_slicing_replicas" -gt 1 ]; then
        print_warning "Time-slicing enabled with ${time_slicing_replicas} replicas. This causes 5-10x latency in production. Use HAMi for GPU sharing instead."
    fi
}

# Main validation
main() {
    echo "NVIDIA GPU Operator Validation"
    echo "==============================="

    check_namespace || exit 1
    check_operator_pods
    check_nvidia_driver
    check_device_plugin
    check_dcgm_exporter
    check_gpu_node_labels
    check_gpu_allocatable
    check_common_issues
    run_sample_workload

    # Summary
    print_section "Validation Summary"

    if [ "$VALIDATION_PASSED" = true ]; then
        print_success "GPU Operator validation passed!"
        echo ""
        echo "Next steps:"
        echo "  1. Deploy training workload: kubectl apply -f components/02-training/examples/pytorch/single-gpu-training.yaml"
        echo "  2. Monitor GPU metrics: kubectl port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400"
        echo "  3. See GPU utilization: curl localhost:9400/metrics | grep DCGM_FI_DEV_GPU_UTIL"
        exit 0
    else
        print_error "GPU Operator validation failed. Fix errors above."
        echo ""
        echo "Troubleshooting:"
        echo "  - Check logs: kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset"
        echo "  - See docs: infrastructure/gpu-operator/troubleshooting.md"
        exit 1
    fi
}

main "$@"
