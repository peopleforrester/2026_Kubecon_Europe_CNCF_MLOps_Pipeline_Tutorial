#!/usr/bin/env bash
# ABOUTME: Pushes a trained model to Harbor registry with in-toto attestation.
# ABOUTME: Packages model with KitOps and signs with cosign for supply chain security.
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <model-name:version> [--model-path PATH]"
    echo ""
    echo "Examples:"
    echo "  $0 fraud-detection:v1"
    echo "  $0 resnet50:latest --model-path ./models/resnet50.pt"
    exit 1
fi

MODEL_REF="$1"
MODEL_NAME="${MODEL_REF%%:*}"
MODEL_VERSION="${MODEL_REF##*:}"
MODEL_PATH="${3:-./model-artifacts/model.pt}"
REGISTRY="${HARBOR_REGISTRY:-harbor.ml-platform.example.com}"
REGISTRY_PATH="${REGISTRY}/ml-models"

echo "============================================"
echo "  Push Model to Harbor"
echo "============================================"
echo "  Model:    $MODEL_NAME"
echo "  Version:  $MODEL_VERSION"
echo "  Registry: $REGISTRY_PATH"
echo ""

# Check prerequisites
for cmd in kitops cosign; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "[ERROR] $cmd is required but not installed."
        exit 1
    fi
done

if [ ! -f "$MODEL_PATH" ]; then
    echo "[ERROR] Model file not found: $MODEL_PATH"
    exit 1
fi

# Package model with KitOps
echo "--- Step 1/3: Packaging model with KitOps ---"
kitops pack \
    --model-path="$MODEL_PATH" \
    --name="$MODEL_NAME" \
    --version="$MODEL_VERSION"
echo "  Model packaged"

# Push to Harbor
echo "--- Step 2/3: Pushing to Harbor ---"
kitops push "${REGISTRY_PATH}/${MODEL_NAME}:${MODEL_VERSION}"
echo "  Pushed to ${REGISTRY_PATH}/${MODEL_NAME}:${MODEL_VERSION}"

# Sign with cosign for supply chain attestation
echo "--- Step 3/3: Signing with cosign ---"
cosign sign --yes "${REGISTRY_PATH}/${MODEL_NAME}:${MODEL_VERSION}"
echo "  Model signed"

echo ""
echo "============================================"
echo "  Model pushed and signed successfully"
echo "  Pull with: kitops pull ${REGISTRY_PATH}/${MODEL_NAME}:${MODEL_VERSION}"
echo "============================================"
