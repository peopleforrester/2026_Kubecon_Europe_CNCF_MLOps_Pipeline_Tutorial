# CI/CD Automation

End-to-end ML pipeline automation using Argo Workflows and Argo Events.

## Overview

Automate ML workflows from training to deployment with event-driven pipelines, enabling continuous training, automated testing, and model promotion workflows.

### Components

1. **Argo Workflows** (CNCF Graduated)
   - DAG-based ML pipelines
   - Parallel execution
   - Retry and error handling
   - Artifact management
   - Pipeline templates

2. **Argo Events**
   - Event-driven triggers
   - GitHub webhooks
   - S3 notifications
   - Cron schedules
   - Custom event sources

3. **ML Pipeline Patterns**
   - Training pipeline
   - Model validation pipeline
   - Deployment pipeline
   - Retraining pipeline
   - A/B testing pipeline

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   CI/CD Pipeline Flow                        │
└─────────────────────────────────────────────────────────────┘

Event Sources          Argo Events           Argo Workflows
┌──────────────┐      ┌──────────────┐      ┌────────────────┐
│ GitHub Push  │─────▶│  EventSource │      │   Training     │
│              │      │              │      │   Pipeline     │
└──────────────┘      │  Sensors:    │─────▶│                │
┌──────────────┐      │  - GitHub    │      │  Steps:        │
│ S3 Upload    │─────▶│  - S3        │      │  1. Data prep  │
│              │      │  - Cron      │      │  2. Train      │
└──────────────┘      │  - Webhook   │      │  3. Validate   │
┌──────────────┐      └──────────────┘      │  4. Package    │
│ Cron         │─────▶       │              │  5. Sign       │
│ (daily)      │             │              └────────┬───────┘
└──────────────┘             │                       │
                             ▼                       ▼
                      ┌──────────────┐      ┌────────────────┐
                      │  Workflow    │      │   Deployment   │
                      │  Triggers    │      │   Pipeline     │
                      │              │─────▶│                │
                      │  Conditions: │      │  Steps:        │
                      │  - Branch    │      │  1. Promote    │
                      │  - File path │      │  2. Deploy     │
                      │  - Labels    │      │  3. Test       │
                      └──────────────┘      │  4. Monitor    │
                                            └────────────────┘
```

## Quick Start

### Prerequisites

- Kubernetes 1.28+
- kubectl with admin access
- GitHub repository (for webhooks)

### Installation

#### Install Argo Workflows

```bash
# Create namespace
kubectl create namespace argo

# Install Argo Workflows
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.5.4/install.yaml

# Wait for pods
kubectl wait --for=condition=ready pod \
  -l app=workflow-controller \
  -n argo \
  --timeout=5m

# Install Argo CLI
curl -sLO https://github.com/argoproj/argo-workflows/releases/download/v3.5.4/argo-linux-amd64.gz
gunzip argo-linux-amd64.gz
chmod +x argo-linux-amd64
sudo mv argo-linux-amd64 /usr/local/bin/argo
argo version

# Access Argo UI
kubectl port-forward -n argo svc/argo-server 2746:2746
# Open: http://localhost:2746
```

#### Install Argo Events

```bash
# Install Argo Events
kubectl apply -n argo -f https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install.yaml

# Install EventBus
kubectl apply -n argo -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/eventbus/native.yaml

# Wait for pods
kubectl wait --for=condition=ready pod \
  -l app=eventbus-controller \
  -n argo \
  --timeout=5m
```

## ML Pipeline Examples

### 1. Training Pipeline

Complete training workflow with data prep, training, validation, and packaging:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: ml-training-pipeline-
  namespace: argo
spec:
  entrypoint: training-pipeline
  arguments:
    parameters:
      - name: model-name
        value: "fraud-detection"
      - name: dataset-path
        value: "s3://ml-data/fraud-detection/v1"
      - name: epochs
        value: "100"

  templates:
    # Main pipeline DAG
    - name: training-pipeline
      dag:
        tasks:
          - name: data-preparation
            template: prep-data

          - name: train-model
            dependencies: [data-preparation]
            template: train
            arguments:
              parameters:
                - name: epochs
                  value: "{{workflow.parameters.epochs}}"

          - name: validate-model
            dependencies: [train-model]
            template: validate

          - name: package-model
            dependencies: [validate-model]
            template: package

          - name: sign-model
            dependencies: [package-model]
            template: sign

          - name: deploy-to-staging
            dependencies: [sign-model]
            template: deploy
            arguments:
              parameters:
                - name: environment
                  value: "staging"

    # Data preparation step
    - name: prep-data
      container:
        image: python:3.11-slim
        command: [python]
        args:
          - -c
          - |
            print("Preparing training data...")
            # Data cleaning, augmentation, splitting
            print("Data preparation complete")

    # Training step
    - name: train
      inputs:
        parameters:
          - name: epochs
      container:
        image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
        command: [python]
        args:
          - train.py
          - --epochs={{inputs.parameters.epochs}}
          - --output=/models/trained-model.pth
        resources:
          limits:
            nvidia.com/gpu: 2
            memory: 32Gi
            cpu: 8
        volumeMounts:
          - name: models
            mountPath: /models
      outputs:
        artifacts:
          - name: model-weights
            path: /models/trained-model.pth
            s3:
              key: models/{{workflow.parameters.model-name}}/{{workflow.uid}}/model.pth

    # Validation step
    - name: validate
      container:
        image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
        command: [python]
        args:
          - validate.py
          - --model=/models/trained-model.pth
          - --test-data=/data/test.csv
        volumeMounts:
          - name: models
            mountPath: /models

    # Package with KitOps
    - name: package
      container:
        image: jozu/kit:latest
        command: [sh, -c]
        args:
          - |
            kit pack . -t harbor.ml-platform.example.com/ml-models/{{workflow.parameters.model-name}}:{{workflow.uid}}
            kit push harbor.ml-platform.example.com/ml-models/{{workflow.parameters.model-name}}:{{workflow.uid}}

    # Sign with Cosign
    - name: sign
      container:
        image: gcr.io/projectsigstore/cosign:v2.2.3
        command: [sh, -c]
        args:
          - |
            export COSIGN_EXPERIMENTAL=1
            cosign sign --yes harbor.ml-platform.example.com/ml-models/{{workflow.parameters.model-name}}:{{workflow.uid}}

    # Deploy step
    - name: deploy
      inputs:
        parameters:
          - name: environment
      resource:
        action: apply
        manifest: |
          apiVersion: serving.kserve.io/v1beta1
          kind: InferenceService
          metadata:
            name: {{workflow.parameters.model-name}}
            namespace: ml-{{inputs.parameters.environment}}
          spec:
            predictor:
              pytorch:
                storageUri: oci://harbor.ml-platform.example.com/ml-models/{{workflow.parameters.model-name}}:{{workflow.uid}}
                resources:
                  requests:
                    cpu: "2"
                    memory: "4Gi"

  volumeClaimTemplates:
    - metadata:
        name: models
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 100Gi
```

### 2. Model Validation Pipeline

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: model-validation-
spec:
  entrypoint: validation-pipeline
  arguments:
    parameters:
      - name: model-image
        value: "harbor.ml-platform.example.com/ml-models/fraud-detection:latest"

  templates:
    - name: validation-pipeline
      dag:
        tasks:
          - name: security-scan
            template: trivy-scan

          - name: performance-test
            template: perf-test

          - name: accuracy-test
            dependencies: [performance-test]
            template: accuracy

          - name: promote-to-prod
            dependencies: [security-scan, accuracy-test]
            template: promote
            when: "{{tasks.security-scan.status}} == Succeeded && {{tasks.accuracy-test.outputs.parameters.accuracy}} > 0.95"

    - name: trivy-scan
      container:
        image: aquasec/trivy:latest
        command: [trivy]
        args:
          - image
          - --severity=CRITICAL,HIGH
          - --exit-code=1  # Fail if vulnerabilities found
          - "{{workflow.parameters.model-image}}"

    - name: perf-test
      container:
        image: locustio/locust:latest
        command: [locust]
        args:
          - --headless
          - --users=100
          - --spawn-rate=10
          - --run-time=5m
          - --host=http://{{workflow.parameters.model-name}}.ml-staging

    - name: accuracy
      script:
        image: python:3.11-slim
        command: [python]
        source: |
          import json

          # Run accuracy tests
          accuracy = 0.97  # Example result

          # Output accuracy as parameter
          with open('/tmp/accuracy.txt', 'w') as f:
              f.write(str(accuracy))

          print(f"Model accuracy: {accuracy}")
      outputs:
        parameters:
          - name: accuracy
            valueFrom:
              path: /tmp/accuracy.txt

    - name: promote
      resource:
        action: patch
        manifest: |
          apiVersion: serving.kserve.io/v1beta1
          kind: InferenceService
          metadata:
            name: {{workflow.parameters.model-name}}
            namespace: ml-production
          spec:
            predictor:
              pytorch:
                storageUri: "{{workflow.parameters.model-image}}"
```

### 3. Automated Retraining Pipeline

```yaml
apiVersion: argoproj.io/v1alpha1
kind: CronWorkflow
metadata:
  name: weekly-retraining
  namespace: argo
spec:
  schedule: "0 0 * * 0"  # Every Sunday at midnight
  concurrencyPolicy: "Forbid"
  workflowSpec:
    entrypoint: retraining-pipeline
    templates:
      - name: retraining-pipeline
        dag:
          tasks:
            - name: check-drift
              template: drift-detection

            - name: retrain
              dependencies: [check-drift]
              template: trigger-training
              when: "{{tasks.check-drift.outputs.parameters.drift}} == true"

            - name: notify
              dependencies: [retrain]
              template: slack-notification

      - name: drift-detection
        script:
          image: python:3.11-slim
          command: [python]
          source: |
            # Check for model drift
            drift_detected = True  # Example

            with open('/tmp/drift.txt', 'w') as f:
                f.write('true' if drift_detected else 'false')
        outputs:
          parameters:
            - name: drift
              valueFrom:
                path: /tmp/drift.txt

      - name: trigger-training
        resource:
          action: create
          manifest: |
            apiVersion: argoproj.io/v1alpha1
            kind: Workflow
            metadata:
              generateName: retraining-
            spec:
              workflowTemplateRef:
                name: ml-training-pipeline

      - name: slack-notification
        container:
          image: curlimages/curl:latest
          command: [sh, -c]
          args:
            - |
              curl -X POST https://hooks.slack.com/services/XXX/YYY/ZZZ \
                -H 'Content-Type: application/json' \
                -d '{"text":"Model retrained successfully: {{workflow.name}}"}'
```

## Event-Driven Pipelines

### GitHub Webhook Trigger

```yaml
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: github
  namespace: argo
spec:
  github:
    ml-repo:
      repositories:
        - owner: my-org
          names:
            - ml-models
      webhook:
        endpoint: /push
        port: "12000"
        method: POST
      events:
        - push
      apiToken:
        name: github-token
        key: token
---
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: github-workflow-trigger
  namespace: argo
spec:
  dependencies:
    - name: github-dep
      eventSourceName: github
      eventName: ml-repo
      filters:
        data:
          - path: body.ref
            type: string
            value:
              - refs/heads/main  # Only trigger on main branch
  triggers:
    - template:
        name: github-workflow-trigger
        k8s:
          operation: create
          source:
            resource:
              apiVersion: argoproj.io/v1alpha1
              kind: Workflow
              metadata:
                generateName: github-triggered-
              spec:
                workflowTemplateRef:
                  name: ml-training-pipeline
                arguments:
                  parameters:
                    - name: commit-sha
                      value: "{{inputs.parameters.commit-sha}}"
          parameters:
            - src:
                dependencyName: github-dep
                dataKey: body.after
              dest: spec.arguments.parameters.0.value
```

### S3 Event Trigger

```yaml
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: s3
  namespace: argo
spec:
  s3:
    training-data:
      bucket:
        name: ml-training-data
      endpoint: s3.amazonaws.com
      events:
        - s3:ObjectCreated:*
      filter:
        suffix: .csv
      accessKey:
        name: aws-credentials
        key: accesskey
      secretKey:
        name: aws-credentials
        key: secretkey
---
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: s3-workflow-trigger
  namespace: argo
spec:
  dependencies:
    - name: s3-dep
      eventSourceName: s3
      eventName: training-data
  triggers:
    - template:
        name: s3-workflow-trigger
        k8s:
          operation: create
          source:
            resource:
              apiVersion: argoproj.io/v1alpha1
              kind: Workflow
              metadata:
                generateName: s3-triggered-
              spec:
                workflowTemplateRef:
                  name: ml-training-pipeline
                arguments:
                  parameters:
                    - name: dataset-path
                      value: "s3://ml-training-data/{{inputs.parameters.s3-key}}"
          parameters:
            - src:
                dependencyName: s3-dep
                dataKey: notification.0.s3.object.key
              dest: spec.arguments.parameters.0.value
```

## Workflow Templates

### Reusable Training Template

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: ml-training-template
  namespace: argo
spec:
  entrypoint: train-and-deploy
  arguments:
    parameters:
      - name: model-name
      - name: framework
        enum:
          - pytorch
          - tensorflow
          - sklearn
      - name: epochs
        value: "100"
      - name: gpu-count
        value: "1"

  templates:
    - name: train-and-deploy
      steps:
        - - name: train
            template: training
        - - name: validate
            template: validation
        - - name: deploy
            template: deployment

    - name: training
      script:
        image: "{{workflow.parameters.framework}}/{{workflow.parameters.framework}}:latest"
        command: [python]
        source: |
          # Training logic here
          pass
        resources:
          limits:
            nvidia.com/gpu: "{{workflow.parameters.gpu-count}}"

    - name: validation
      # ... validation logic

    - name: deployment
      # ... deployment logic
```

### Use Template

```bash
# Submit workflow from template
argo submit -n argo --from workflowtemplate/ml-training-template \
  -p model-name=fraud-detection \
  -p framework=pytorch \
  -p epochs=50 \
  -p gpu-count=2

# Watch workflow
argo watch -n argo @latest
```

## Pipeline Monitoring

### View Workflows

```bash
# List all workflows
argo list -n argo

# Get workflow status
argo get -n argo <workflow-name>

# View workflow logs
argo logs -n argo <workflow-name>

# View specific step logs
argo logs -n argo <workflow-name> <step-name>
```

### Workflow Metrics

Argo Workflows exposes Prometheus metrics:

```promql
# Workflow execution time
histogram_quantile(0.95,
  sum(rate(argo_workflow_duration_seconds_bucket[5m])) by (le)
)

# Workflow success rate
sum(rate(argo_workflows_count{status="Succeeded"}[5m])) /
sum(rate(argo_workflows_count[5m]))

# Failed workflows
sum(rate(argo_workflows_count{status="Failed"}[5m])) by (workflow_name)
```

### Grafana Dashboard

```yaml
# Panel 1: Workflows per Day
Query: sum(increase(argo_workflows_count[24h])) by (status)

# Panel 2: Average Execution Time
Query: avg(argo_workflow_duration_seconds) by (workflow_name)

# Panel 3: Success Rate
Query:
  sum(rate(argo_workflows_count{status="Succeeded"}[1h])) /
  sum(rate(argo_workflows_count[1h]))
```

## Best Practices

### 1. Use Workflow Templates

```yaml
# Define once, use many times
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: common-tasks
spec:
  templates:
    - name: notify-slack
      # ... notification logic

# Use in workflows
templates:
  - name: my-step
    steps:
      - - name: notify
          templateRef:
            name: common-tasks
            template: notify-slack
```

### 2. Retry Failed Steps

```yaml
templates:
  - name: train
    retryStrategy:
      limit: 3
      retryPolicy: "Always"
      backoff:
        duration: "1m"
        factor: 2
        maxDuration: "10m"
```

### 3. Resource Management

```yaml
# Set resource limits
container:
  resources:
    requests:
      cpu: "4"
      memory: "16Gi"
    limits:
      cpu: "8"
      memory: "32Gi"
      nvidia.com/gpu: "2"

# Set workflow-level limits
spec:
  podGC:
    strategy: OnPodSuccess  # Clean up successful pods
```

### 4. Artifact Management

```yaml
# Store artifacts in S3
outputs:
  artifacts:
    - name: model-weights
      path: /models/trained-model.pth
      s3:
        bucket: ml-artifacts
        key: models/{{workflow.name}}/model.pth
        region: us-west-2

# Use artifacts in subsequent steps
inputs:
  artifacts:
    - name: model-weights
      path: /models/trained-model.pth
      s3:
        bucket: ml-artifacts
        key: models/{{workflow.name}}/model.pth
```

## Troubleshooting

### Workflow Stuck in Pending

```bash
# Check workflow events
kubectl describe workflow -n argo <workflow-name>

# Common causes:
# - Insufficient resources
# - Image pull errors
# - Volume mount issues

# Delete stuck workflow
argo delete -n argo <workflow-name>
```

### Workflow Failed

```bash
# View logs
argo logs -n argo <workflow-name>

# View specific step logs
argo logs -n argo <workflow-name> <step-name>

# Retry failed workflow
argo retry -n argo <workflow-name>

# Resubmit workflow
argo resubmit -n argo <workflow-name>
```

### EventSource Not Triggering

```bash
# Check EventSource status
kubectl get eventsource -n argo

# View EventSource logs
kubectl logs -n argo -l eventsource-name=github

# Check Sensor status
kubectl get sensor -n argo

# View Sensor logs
kubectl logs -n argo -l sensor-name=github-workflow-trigger
```

## Component Documentation

- **Argo Workflows Installation**: [argo/argo-workflows-install.yaml](argo/argo-workflows-install.yaml)
- **Pipeline Templates**: [argo/workflow-templates.yaml](argo/workflow-templates.yaml)
- **Event Sources**: [argo/event-sources.yaml](argo/event-sources.yaml)

## Tutorial

For a complete step-by-step tutorial, see:
[CI/CD Automation Tutorial](../../docs/tutorials/08-cicd.md)

## References

- [Argo Workflows Documentation](https://argoproj.github.io/argo-workflows/)
- [Argo Events Documentation](https://argoproj.github.io/argo-events/)
- [Workflow Examples](https://github.com/argoproj/argo-workflows/tree/master/examples)
- [Best Practices](https://argoproj.github.io/argo-workflows/workflow-concepts/)

---

[← Back: Security & Governance](../07-security/README.md) | [Components Overview](../README.md)
