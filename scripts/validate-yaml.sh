#!/bin/bash
# ABOUTME: YAML validation script for Kubernetes manifests using kubeconform
# ABOUTME: Validates syntax, schema compliance, and best practices for all YAML files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Kubernetes YAML Validation ==="
echo ""

# Check if kubeconform is installed
if ! command -v kubeconform &> /dev/null; then
    echo -e "${YELLOW}kubeconform not found. Installing...${NC}"

    # Detect OS and architecture
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
    esac

    # Download kubeconform
    VERSION="0.6.4"
    wget -q "https://github.com/yannh/kubeconform/releases/download/v${VERSION}/kubeconform-${OS}-${ARCH}.tar.gz"
    tar xzf "kubeconform-${OS}-${ARCH}.tar.gz"
    sudo mv kubeconform /usr/local/bin/
    rm "kubeconform-${OS}-${ARCH}.tar.gz"

    echo -e "${GREEN}kubeconform installed successfully${NC}"
    echo ""
fi

# Find all YAML files
YAML_FILES=$(find . -type f \( -name "*.yaml" -o -name "*.yml" \) \
    ! -path "./node_modules/*" \
    ! -path "./.git/*" \
    ! -path "./vendor/*")

TOTAL_FILES=$(echo "$YAML_FILES" | wc -l)
VALID_FILES=0
INVALID_FILES=0
SKIPPED_FILES=0

echo "Found $TOTAL_FILES YAML files to validate"
echo ""

# Validation results
VALIDATION_LOG=$(mktemp)

# Validate each file
for file in $YAML_FILES; do
    echo -n "Validating $file... "

    # Skip certain files
    if [[ "$file" == *"values.yaml"* ]] || [[ "$file" == *"Chart.yaml"* ]]; then
        echo -e "${YELLOW}SKIPPED (Helm chart)${NC}"
        ((SKIPPED_FILES++))
        continue
    fi

    # Run kubeconform
    if kubeconform \
        -strict \
        -ignore-missing-schemas \
        -kubernetes-version 1.28.0 \
        -schema-location default \
        -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
        "$file" > /dev/null 2>&1; then
        echo -e "${GREEN}VALID${NC}"
        ((VALID_FILES++))
    else
        echo -e "${RED}INVALID${NC}"
        echo "  File: $file" >> "$VALIDATION_LOG"
        kubeconform \
            -strict \
            -ignore-missing-schemas \
            -kubernetes-version 1.28.0 \
            -schema-location default \
            -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
            "$file" 2>&1 | sed 's/^/    /' >> "$VALIDATION_LOG"
        echo "" >> "$VALIDATION_LOG"
        ((INVALID_FILES++))
    fi
done

echo ""
echo "=== Validation Summary ==="
echo -e "Total files:   $TOTAL_FILES"
echo -e "${GREEN}Valid files:   $VALID_FILES${NC}"
echo -e "${RED}Invalid files: $INVALID_FILES${NC}"
echo -e "${YELLOW}Skipped files: $SKIPPED_FILES${NC}"

if [ $INVALID_FILES -gt 0 ]; then
    echo ""
    echo "=== Validation Errors ==="
    cat "$VALIDATION_LOG"
fi

rm "$VALIDATION_LOG"

# Exit with error if any files are invalid
if [ $INVALID_FILES -gt 0 ]; then
    echo ""
    echo -e "${RED}❌ Validation failed with $INVALID_FILES invalid files${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ All YAML files are valid!${NC}"
    exit 0
fi
