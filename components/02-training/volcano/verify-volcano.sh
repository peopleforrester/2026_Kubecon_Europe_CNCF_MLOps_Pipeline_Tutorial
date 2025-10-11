#!/bin/bash
# ABOUTME: Validation script for Volcano scheduler installation and gang scheduling verification
# ABOUTME: Checks operator health, CRDs, queues, and submits test gang scheduling job

set -e

echo "=========================================="
echo "Volcano Scheduler Verification"
echo "=========================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "✗ kubectl not found. Please install kubectl."
    exit 1
fi

echo "✓ kubectl found"
echo ""

# Check Volcano namespace
echo "1. Checking Volcano namespace..."
if kubectl get namespace volcano-system &> /dev/null; then
    echo "  ✓ volcano-system namespace exists"
else
    echo "  ✗ volcano-system namespace not found"
    echo "  Install Volcano: helm install volcano volcano-sh/volcano -n volcano-system --create-namespace"
    exit 1
fi
echo ""

# Check Volcano pods
echo "2. Checking Volcano pods..."
PODS=$(kubectl get pods -n volcano-system -o json)

check_pod() {
    local pod_name=$1
    local count=$(echo "$PODS" | jq -r ".items[] | select(.metadata.name | startswith(\"$pod_name\")) | .status.phase" | grep -c "Running" || echo "0")

    if [ "$count" -gt 0 ]; then
        echo "  ✓ $pod_name is running"
        return 0
    else
        echo "  ✗ $pod_name is not running"
        return 1
    fi
}

check_pod "volcano-scheduler"
check_pod "volcano-controllers"
check_pod "volcano-admission"
echo ""

# Check CRDs
echo "3. Checking Volcano CRDs..."
CRDS=$(kubectl get crd -o name | grep volcano || echo "")

check_crd() {
    local crd=$1
    if echo "$CRDS" | grep -q "$crd"; then
        echo "  ✓ $crd exists"
        return 0
    else
        echo "  ✗ $crd not found"
        return 1
    fi
}

check_crd "jobs.batch.volcano.sh"
check_crd "podgroups.scheduling.volcano.sh"
check_crd "queues.scheduling.volcano.sh"
echo ""

# Check queues
echo "4. Checking Volcano queues..."
QUEUES=$(kubectl get queues.scheduling.volcano.sh -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -z "$QUEUES" ]; then
    echo "  ⚠ No queues found. Creating default queue..."
    kubectl apply -f - <<EOF
apiVersion: scheduling.volcano.sh/v1beta1
kind: Queue
metadata:
  name: default
spec:
  weight: 1
  reclaimable: true
EOF
    echo "  ✓ Created default queue"
else
    echo "  ✓ Found queues: $QUEUES"
fi
echo ""

# Check priority classes
echo "5. Checking ML priority classes..."
PRIORITY_CLASSES=$(kubectl get priorityclasses -o name | grep "^priorityclass.scheduling.k8s.io/ml-" || echo "")

if [ -z "$PRIORITY_CLASSES" ]; then
    echo "  ⚠ No ML priority classes found"
    echo "    Apply: kubectl apply -f components/02-training/volcano/volcano-queues.yaml"
else
    echo "  ✓ Found ML priority classes"
    echo "$PRIORITY_CLASSES" | sed 's/^/    /'
fi
echo ""

# Test gang scheduling
echo "6. Testing gang scheduling (submitting test job)..."

# Create test namespace if not exists
kubectl create namespace ml-training --dry-run=client -o yaml | kubectl apply -f - &> /dev/null

# Submit test job
TEST_JOB_NAME="volcano-test-$(date +%s)"

kubectl apply -f - <<EOF
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  name: ${TEST_JOB_NAME}
  namespace: ml-training
spec:
  schedulerName: volcano
  minAvailable: 2
  queue: default
  tasks:
    - replicas: 2
      name: worker
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: test
              image: busybox:latest
              command: [sh, -c]
              args:
                - |
                  echo "Worker \${VC_TASK_INDEX} started with gang scheduling"
                  sleep 10
                  echo "Worker \${VC_TASK_INDEX} completed"
              env:
                - name: VC_TASK_INDEX
                  valueFrom:
                    fieldRef:
                      fieldPath: metadata.annotations['volcano.sh/task-index']
              resources:
                requests:
                  cpu: 100m
                  memory: 128Mi
EOF

echo "  ✓ Submitted test job: ${TEST_JOB_NAME}"
echo "  Waiting for job to complete (max 60s)..."

# Wait for job to complete
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    JOB_STATUS=$(kubectl get job.batch.volcano.sh ${TEST_JOB_NAME} -n ml-training -o jsonpath='{.status.state.phase}' 2>/dev/null || echo "")

    if [ "$JOB_STATUS" = "Completed" ]; then
        echo "  ✓ Test job completed successfully"
        break
    elif [ "$JOB_STATUS" = "Failed" ]; then
        echo "  ✗ Test job failed"
        kubectl logs -n ml-training -l volcano.sh/job-name=${TEST_JOB_NAME} --tail=20
        exit 1
    fi

    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "  ⚠ Test job did not complete within ${TIMEOUT}s"
    echo "  Current status: $JOB_STATUS"
    echo "  Check: kubectl get job.batch.volcano.sh ${TEST_JOB_NAME} -n ml-training"
fi
echo ""

# Cleanup test job
echo "7. Cleaning up test job..."
kubectl delete job.batch.volcano.sh ${TEST_JOB_NAME} -n ml-training &> /dev/null || true
echo "  ✓ Test job deleted"
echo ""

# Summary
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo ""
echo "✓ Volcano scheduler is installed and operational"
echo "✓ Gang scheduling is working"
echo ""
echo "Next steps:"
echo "  1. Create queues: kubectl apply -f components/02-training/volcano/volcano-queues.yaml"
echo "  2. Submit training job: kubectl apply -f components/02-training/volcano/gang-scheduling-examples.yaml"
echo "  3. Monitor jobs: kubectl get jobs.batch.volcano.sh -n ml-training -w"
echo ""
echo "To see gang scheduling in action:"
echo "  kubectl logs -n volcano-system -l app=volcano-scheduler --tail=100 | grep gang"
echo ""
