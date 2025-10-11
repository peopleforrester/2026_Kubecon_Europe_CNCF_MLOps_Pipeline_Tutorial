# Training Infrastructure

Distributed training workloads with GPU scheduling and gang scheduling using Volcano.

## Overview

Volcano is a Kubernetes-native batch scheduler designed for high-performance workloads like ML training, providing gang scheduling, queue management, and fair resource sharing.

### Key Features

- **Gang Scheduling**: All-or-nothing pod scheduling (critical for distributed training)
- **GPU Scheduling**: Fair sharing of GPU resources across teams
- **Queue Management**: Multi-tenant resource allocation with priorities
- **Job Lifecycle**: Automatic retry, preemption, and backfill
- **Framework Support**: PyTorch DDP, Horovod, TensorFlow PS, Ray, Spark

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Volcano Architecture                      │
└─────────────────────────────────────────────────────────────┘

Training Request         Volcano Scheduler           GPU Nodes
┌──────────────┐        ┌──────────────────┐       ┌───────────┐
│ PyTorch Job  │        │  Gang Scheduler  │       │ Node 1    │
│ Replicas: 4  │───────▶│                  │──────▶│ GPU: 8    │
│ GPU/pod: 2   │        │  Checks:         │       │ Available │
│              │        │  - 8 GPUs free?  │       └───────────┘
└──────────────┘        │  - Queue quota?  │       ┌───────────┐
                        │  - Priority?     │       │ Node 2    │
┌──────────────┐        │                  │──────▶│ GPU: 8    │
│ TF Job       │───────▶│  Actions:        │       │ Available │
│ Workers: 8   │        │  - Reserve GPUs  │       └───────────┘
│ PS: 2        │        │  - Schedule all  │       ┌───────────┐
│              │        │  - Or none       │       │ Node 3    │
└──────────────┘        └──────────────────┘──────▶│ GPU: 8    │
                                                    │ Available │
                                                    └───────────┘
```

## Quick Start

### Prerequisites

- Kubernetes 1.28+
- kubectl with admin access
- GPU nodes (optional, but recommended)

### Installation

```bash
# Install Volcano using kubectl
kubectl apply -f https://raw.githubusercontent.com/volcano-sh/volcano/v1.8.2/installer/volcano-development.yaml

# Wait for Volcano pods to be ready
kubectl wait --for=condition=ready pod \
  -l app=volcano \
  -n volcano-system \
  --timeout=5m

# Verify installation
kubectl get pods -n volcano-system
# Expected output:
# volcano-admission-xxx    Running
# volcano-controllers-xxx  Running
# volcano-scheduler-xxx    Running
```

### Submit Your First Training Job

#### PyTorch Distributed Training

```yaml
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  name: pytorch-mnist
  namespace: ml-team
spec:
  minAvailable: 2        # Gang scheduling: need 2 pods or none
  schedulerName: volcano
  policies:
    - event: PodEvicted
      action: RestartJob
  queue: default
  tasks:
    - replicas: 2
      name: worker
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: trainer
              image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
              command:
                - python
                - -m
                - torch.distributed.launch
                - --nproc_per_node=2
                - train.py
              resources:
                requests:
                  cpu: "4"
                  memory: "16Gi"
                  nvidia.com/gpu: "2"
                limits:
                  cpu: "8"
                  memory: "32Gi"
                  nvidia.com/gpu: "2"
```

Submit the job:
```bash
kubectl apply -f pytorch-mnist.yaml

# Check job status
kubectl get vcjob -n ml-team

# View pod logs
kubectl logs -n ml-team -l volcano.sh/job-name=pytorch-mnist
```

## Features

### 1. Gang Scheduling

Ensures all pods in a job start together (critical for distributed training):

```yaml
spec:
  minAvailable: 4  # Need 4 pods or schedule none
  tasks:
    - replicas: 4
      name: worker
      # All 4 workers scheduled together or not at all
```

**Why gang scheduling matters:**
- **Distributed training**: All workers must start simultaneously
- **Resource efficiency**: No partial allocations blocking cluster
- **Deadlock prevention**: Avoids circular waiting for resources

### 2. Queue Management

Create queues for multi-tenant resource allocation:

```yaml
apiVersion: scheduling.volcano.sh/v1beta1
kind: Queue
metadata:
  name: ml-team-a
spec:
  weight: 50        # Priority weight
  capability:
    cpu: "100"
    memory: "500Gi"
    nvidia.com/gpu: "16"
  reclaimable: true  # Allow other queues to borrow when idle
```

Apply queue:
```bash
kubectl apply -f queue-ml-team-a.yaml

# Submit job to queue
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
spec:
  queue: ml-team-a  # Use this queue
```

### 3. Fair Share Scheduling

Distribute resources fairly across teams:

```bash
# Create queues for 3 teams
# Team A: 50% weight → 8 GPUs
# Team B: 30% weight → 5 GPUs
# Team C: 20% weight → 3 GPUs
# Total: 16 GPUs

kubectl apply -f queues/ml-team-a.yaml  # weight: 50
kubectl apply -f queues/ml-team-b.yaml  # weight: 30
kubectl apply -f queues/ml-team-c.yaml  # weight: 20
```

### 4. Job Priority and Preemption

Higher priority jobs can preempt lower priority jobs:

```yaml
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  name: urgent-training
spec:
  queue: ml-team-a
  priorityClassName: high-priority
  policies:
    - event: PodEvicted
      action: RestartJob
  # This job can preempt lower-priority jobs
```

Create PriorityClasses:
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000
globalDefault: false
description: "High priority for urgent training jobs"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority
value: 100
globalDefault: false
description: "Low priority for experimental jobs"
```

### 5. Automatic Retry

Retry failed jobs automatically:

```yaml
spec:
  maxRetry: 3  # Retry up to 3 times
  policies:
    - event: PodFailed
      action: RestartJob
    - event: TaskCompleted
      action: CompleteJob
```

## Training Job Examples

### PyTorch Distributed Data Parallel (DDP)

```yaml
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  name: pytorch-ddp-training
  namespace: ml-team
spec:
  minAvailable: 4
  schedulerName: volcano
  queue: ml-team-a
  maxRetry: 2
  tasks:
    - replicas: 4
      name: worker
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: trainer
              image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
              command:
                - torchrun
                - --nnodes=4
                - --nproc_per_node=2
                - --rdzv_backend=c10d
                - --rdzv_endpoint=$(MASTER_ADDR):29400
                - train.py
                - --epochs=100
                - --batch-size=256
              env:
                - name: MASTER_ADDR
                  value: "pytorch-ddp-training-worker-0"
                - name: MASTER_PORT
                  value: "29400"
              resources:
                requests:
                  cpu: "8"
                  memory: "32Gi"
                  nvidia.com/gpu: "2"
                limits:
                  cpu: "16"
                  memory: "64Gi"
                  nvidia.com/gpu: "2"
              volumeMounts:
                - name: data
                  mountPath: /data
                - name: models
                  mountPath: /models
          volumes:
            - name: data
              persistentVolumeClaim:
                claimName: training-data
            - name: models
              persistentVolumeClaim:
                claimName: model-outputs
```

### TensorFlow Parameter Server

```yaml
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  name: tensorflow-ps-training
  namespace: ml-team
spec:
  minAvailable: 10  # 8 workers + 2 PS
  schedulerName: volcano
  queue: ml-team-a
  tasks:
    # Parameter servers
    - replicas: 2
      name: ps
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: tensorflow
              image: tensorflow/tensorflow:2.13.0-gpu
              command:
                - python
                - train.py
                - --job_name=ps
                - --task_index=$(VK_TASK_INDEX)
              env:
                - name: TF_CONFIG
                  value: '{"cluster":{"worker":["worker-0:2222","worker-1:2222"],"ps":["ps-0:2222","ps-1:2222"]}}'
              resources:
                requests:
                  cpu: "4"
                  memory: "16Gi"
    # Workers
    - replicas: 8
      name: worker
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: tensorflow
              image: tensorflow/tensorflow:2.13.0-gpu
              command:
                - python
                - train.py
                - --job_name=worker
                - --task_index=$(VK_TASK_INDEX)
              resources:
                requests:
                  cpu: "8"
                  memory: "32Gi"
                  nvidia.com/gpu: "1"
```

### Horovod Multi-Node Training

```yaml
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  name: horovod-training
  namespace: ml-team
spec:
  minAvailable: 4
  schedulerName: volcano
  queue: ml-team-a
  tasks:
    - replicas: 4
      name: worker
      policies:
        - event: TaskCompleted
          action: CompleteJob
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: horovod
              image: horovod/horovod:0.28.1-tf2.13.0-torch2.0.1-mxnet1.9.1-py3.10-gpu
              command:
                - mpirun
                - --allow-run-as-root
                - -np
                - "8"
                - -H
                - worker-0:2,worker-1:2,worker-2:2,worker-3:2
                - python
                - train.py
              resources:
                requests:
                  cpu: "8"
                  memory: "32Gi"
                  nvidia.com/gpu: "2"
```

### Ray Distributed Training

```yaml
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  name: ray-training
  namespace: ml-team
spec:
  minAvailable: 5  # 1 head + 4 workers
  schedulerName: volcano
  queue: ml-team-a
  tasks:
    # Ray head node
    - replicas: 1
      name: head
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: ray-head
              image: rayproject/ray:2.7.0-gpu
              command:
                - ray
                - start
                - --head
                - --port=6379
                - --dashboard-host=0.0.0.0
              ports:
                - containerPort: 6379
                - containerPort: 8265
              resources:
                requests:
                  cpu: "4"
                  memory: "16Gi"
    # Ray workers
    - replicas: 4
      name: worker
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: ray-worker
              image: rayproject/ray:2.7.0-gpu
              command:
                - ray
                - start
                - --address=head-0:6379
              resources:
                requests:
                  cpu: "8"
                  memory: "32Gi"
                  nvidia.com/gpu: "2"
```

## Monitoring

### Job Status

```bash
# List all Volcano jobs
kubectl get vcjob --all-namespaces

# Describe job
kubectl describe vcjob pytorch-mnist -n ml-team

# Job phases:
# - Pending: Waiting for resources
# - Running: Training in progress
# - Completed: Successfully finished
# - Failed: Job failed
# - Aborted: Manually terminated
```

### Queue Status

```bash
# List queues
kubectl get queue

# Expected output:
# NAME        WEIGHT   CAPABILITY
# ml-team-a   50       cpu:100,memory:500Gi,nvidia.com/gpu:16
# ml-team-b   30       cpu:60,memory:300Gi,nvidia.com/gpu:10

# Describe queue
kubectl describe queue ml-team-a
```

### Resource Usage

```bash
# View GPU allocation per queue
kubectl get queue -o custom-columns=\
NAME:.metadata.name,\
ALLOCATED_GPU:.status.allocated.nvidia\.com/gpu,\
CAPACITY_GPU:.spec.capability.nvidia\.com/gpu

# View running jobs per queue
kubectl get vcjob --all-namespaces -o json | \
  jq -r '.items[] | select(.status.state.phase=="Running") | "\(.spec.queue) \(.metadata.name)"'
```

## Troubleshooting

### Job Stuck in Pending

```bash
# Check job events
kubectl describe vcjob <name> -n <namespace>

# Common causes:
# 1. Insufficient resources
#    Solution: Reduce minAvailable or resource requests

# 2. Queue quota exceeded
#    Solution: Increase queue capacity or wait for jobs to complete

# 3. Gang scheduling deadlock
#    Solution: Adjust minAvailable to match available resources
```

### Pod Evicted

```bash
# Check why pod was evicted
kubectl describe pod <pod-name> -n <namespace>

# Common causes:
# 1. Higher priority job preempted
#    Solution: Increase job priority or use non-preemptible queue

# 2. Node maintenance
#    Solution: Job will automatically retry

# 3. Resource contention
#    Solution: Reduce resource requests or add more nodes
```

### Training Job Failed

```bash
# View pod logs
kubectl logs -n <namespace> -l volcano.sh/job-name=<job-name>

# Check for common issues:
# - Out of memory → Reduce batch size or increase memory limit
# - CUDA error → Check GPU availability
# - Network timeout → Check inter-pod communication
```

## Best Practices

### 1. Resource Requests

Set appropriate resource requests to avoid over-provisioning:

```yaml
resources:
  requests:
    cpu: "8"          # Actual CPU needed
    memory: "32Gi"    # Actual memory needed
    nvidia.com/gpu: "2"
  limits:
    cpu: "16"         # Max CPU (2x requests)
    memory: "64Gi"    # Max memory (2x requests)
    nvidia.com/gpu: "2"
```

### 2. Gang Scheduling Configuration

```yaml
spec:
  minAvailable: 4  # Match number of replicas for strict gang scheduling
  tasks:
    - replicas: 4
```

### 3. Queue Management

**Per-team queues:**
```yaml
# Create queue per team with appropriate weight
ml-team-a: weight=50 → 50% of cluster
ml-team-b: weight=30 → 30% of cluster
ml-team-c: weight=20 → 20% of cluster
```

**Reclaimable resources:**
```yaml
spec:
  reclaimable: true  # Allow borrowing when idle
```

### 4. Job Retry Policy

```yaml
spec:
  maxRetry: 2  # Retry 2 times
  policies:
    - event: PodFailed
      action: RestartJob
    - event: PodEvicted
      action: RestartJob
```

### 5. Data Management

**Use PVCs for large datasets:**
```yaml
volumes:
  - name: training-data
    persistentVolumeClaim:
      claimName: imagenet-dataset  # Pre-loaded dataset
```

**Use local SSDs for checkpoints:**
```yaml
volumes:
  - name: checkpoints
    hostPath:
      path: /mnt/local-ssd/checkpoints
      type: DirectoryOrCreate
```

## Performance Optimization

### Network Performance

```yaml
# Enable host network for multi-node training
spec:
  tasks:
    - template:
        spec:
          hostNetwork: true  # Bypass overlay network
```

### GPU Affinity

```yaml
# Pin to specific GPU nodes
spec:
  tasks:
    - template:
        spec:
          nodeSelector:
            accelerator: nvidia-tesla-v100
```

### Storage Performance

- **Local SSD**: 10x faster than network storage for checkpoints
- **Shared NFS**: Good for large datasets (read-only)
- **S3**: Good for final model storage

## Integration with MLOps Stack

### 1. Pull Models from Harbor

```yaml
spec:
  tasks:
    - template:
        spec:
          containers:
            - name: trainer
              image: harbor.ml-platform.example.com/ml-models/base-trainer:v1.0
```

### 2. Store Training Artifacts

```yaml
# Mount model registry storage
volumes:
  - name: model-output
    persistentVolumeClaim:
      claimName: harbor-storage
```

### 3. Monitor with Prometheus

Volcano exports metrics to Prometheus:
- `volcano_queue_allocated_resources`
- `volcano_job_duration_seconds`
- `volcano_job_retry_count`

## Component Documentation

- **Volcano Installation**: [volcano/volcano-install.yaml](volcano/volcano-install.yaml)
- **Queue Configuration**: [volcano/queue-examples.yaml](volcano/queue-examples.yaml)
- **Training Examples**: [volcano/training-examples.yaml](volcano/training-examples.yaml)

## Tutorial

For a complete step-by-step tutorial, see:
[Distributed Training Tutorial](../../docs/tutorials/02-training.md)

## References

- [Volcano Documentation](https://volcano.sh/en/docs/)
- [PyTorch Distributed Training](https://pytorch.org/tutorials/beginner/dist_overview.html)
- [TensorFlow Distributed Training](https://www.tensorflow.org/guide/distributed_training)
- [Horovod Documentation](https://horovod.readthedocs.io/)
- [Ray Train Documentation](https://docs.ray.io/en/latest/train/train.html)

---

[← Back: GPU Resources](../01-gpu-resources/README.md) | [Components Overview](../README.md) | [Next: Model Registry →](../03-model-registry/README.md)
