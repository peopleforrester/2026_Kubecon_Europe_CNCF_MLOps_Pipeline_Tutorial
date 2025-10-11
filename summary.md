# KubeCon 2026 EU - MLOps Tutorial Demo Repository

## Overview

This repository supports a 75-minute hands-on tutorial for KubeCon 2026 Europe that teaches intermediate to advanced developers how to build a complete end-to-end MLOps pipeline using CNCF graduated and incubating projects.

## Session Information

- **Title:** MLOps from Scratch: Build a Complete Data-to-Deployment Pipeline Using CNCF Projects
- **Format:** Hands-On Tutorial (75 minutes)
- **Track:** AI + Machine Learning on Kubernetes
- **Audience:** Intermediate to Advanced
- **Target:** CNCF-affiliated public, engineers, and developers

## Core Value Proposition

This tutorial addresses the overwhelming MLOps landscape (180+ projects) by providing a battle-tested reference architecture validated across 100,000+ learner deployments. It shows which CNCF projects solve which problems, how they integrate, and where teams consistently fail.

## Key Differentiators

1. **CNCF-Native Architecture:** Prioritizes CNCF graduated and incubating projects with minimal vendor lock-in
2. **Cutting-Edge Capabilities (2024-2025):** Features newest CNCF projects including Volcano v1.11, OpenCost (Incubating October 2024), HAMi, KAITO, KitOps, and in-toto (graduated February 2025)
3. **Cost-Aware by Design:** Built-in GPU cost attribution via OpenCost, preventing $50K surprise bills
4. **Failure-Informed:** Teaches what works by showing what breaks, based on 100K+ student deployment patterns

## Six-Stage MLOps Pipeline

1. **Data Pipeline:** Strimzi + Argo Workflows for real-time ingestion and preprocessing
2. **Distributed GPU Training:** Kubeflow + Volcano + HAMi + KAITO for training orchestration, gang scheduling, GPU virtualization, and LLM deployment
3. **Model Registry & Supply Chain Security:** Harbor + in-toto + KitOps for artifact storage, attestation, and ML-specific packaging
4. **Model Serving:** KServe + KEDA + Gateway API for inference endpoints, autoscaling, and canary deployments
5. **Observability & Cost Attribution:** OpenTelemetry + Prometheus + Fluentd + OpenCost for tracing, metrics, logs, and GPU cost tracking
6. **MLOps Automation:** ArgoCD + Argo Workflows + Crossplane for GitOps, CI/CD, and infrastructure provisioning

## Critical Cost & Failure Insights

Based on 100K+ student deployments:
- 67% misconfigure GPU resource limits → runaway costs
- 73% hit distributed training deadlocks without gang scheduling
- 81% lose training runs due to misconfigured checkpoint strategies
- Time-slicing on inference causes 5-10x latency degradation
- HAMi GPU virtualization achieves up to 57% cost savings

## What Attendees Will Build

- ✅ Working MLOps pipeline deployed in cluster
- ✅ Complete manifest repository with all YAML files and Helm charts
- ✅ Cost visibility dashboard showing GPU spend attribution via OpenCost
- ✅ Decision framework for CNCF vs ecosystem tools
- ✅ Integration patterns tested across 100K+ deployments

## Honest Ecosystem Gap Assessment

The tutorial acknowledges CNCF gaps and shows cross-foundation integration:
- **Feature Stores:** Feast (LF AI & Data Foundation)
- **Experiment Tracking:** MLflow (Linux Foundation)
- **Model Monitoring:** Custom Prometheus + OpenTelemetry metrics
- **Device Management:** NVIDIA GPU Operator (ecosystem)
- **Visualization:** Grafana (ecosystem)

## Repository Purpose

This repository serves as the reference implementation and hands-on lab environment for tutorial attendees, providing:
- Working manifests and Helm charts
- Step-by-step deployment instructions
- Cost optimization strategies
- Common failure patterns and solutions
- Decision frameworks for production adoption

## Target Outcomes

1. Deploy complete MLOps pipeline using CNCF projects
2. Understand integration patterns validated across 100K+ deployments
3. Build GPU cost visibility from day one
4. Learn from common mistakes (67-81% of students encounter)
5. Navigate CNCF ecosystem with honest gap assessment
