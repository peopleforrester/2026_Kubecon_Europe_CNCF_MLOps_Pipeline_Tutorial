#!/bin/bash
# ABOUTME: Security scanning script for detecting hardcoded secrets and insecure configurations
# ABOUTME: Scans YAML, shell scripts, and documentation for security issues

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Security Scanner ==="
echo ""

# Counters
TOTAL_ISSUES=0
CRITICAL_ISSUES=0
HIGH_ISSUES=0
MEDIUM_ISSUES=0
LOW_ISSUES=0

# Temporary files for results
RESULTS=$(mktemp)
SUMMARY=$(mktemp)

# Function to report finding
report_finding() {
    local severity=$1
    local category=$2
    local file=$3
    local line=$4
    local message=$5

    echo "[$severity] $category: $file:$line - $message" >> "$RESULTS"
    ((TOTAL_ISSUES++))

    case $severity in
        CRITICAL) ((CRITICAL_ISSUES++)) ;;
        HIGH) ((HIGH_ISSUES++)) ;;
        MEDIUM) ((MEDIUM_ISSUES++)) ;;
        LOW) ((LOW_ISSUES++)) ;;
    esac
}

echo "Scanning for hardcoded secrets and security issues..."
echo ""

# 1. Scan for hardcoded passwords
echo -n "Checking for hardcoded passwords... "
while IFS= read -r file; do
    if [ -f "$file" ]; then
        # Check for password patterns (case-insensitive)
        grep -n -i 'password.*[:=].*["\047].*["\047]' "$file" 2>/dev/null | while IFS=: read -r line_num match; do
            # Skip if it's a placeholder
            if ! echo "$match" | grep -qE '<[A-Z-]+>|changeme|CHANGE.?ME|your-password|example|placeholder|\*\*\*\*'; then
                # Skip if it's in a comment explaining security
                if ! echo "$match" | grep -qE '^\s*#.*SECURITY|WARNING|⚠️'; then
                    report_finding "HIGH" "Hardcoded Password" "$file" "$line_num" "Potential hardcoded password detected"
                fi
            fi
        done
    fi
done < <(find . -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.sh" -o -name "*.md" \) \
    ! -path "./node_modules/*" \
    ! -path "./.git/*" \
    ! -path "./vendor/*")
echo -e "${GREEN}DONE${NC}"

# 2. Scan for API keys and tokens
echo -n "Checking for API keys and tokens... "
while IFS= read -r file; do
    if [ -f "$file" ]; then
        # Common API key patterns
        grep -nE '(api[_-]?key|apikey|access[_-]?key|secret[_-]?key|auth[_-]?token).*[:=].*["\047][A-Za-z0-9+/]{20,}["\047]' "$file" 2>/dev/null | while IFS=: read -r line_num match; do
            if ! echo "$match" | grep -qE '<[A-Z-]+>|CHANGE.?ME|your-|example|placeholder|\*\*\*\*|AKIAIOSFODNN7EXAMPLE'; then
                report_finding "CRITICAL" "API Key/Token" "$file" "$line_num" "Potential API key or token detected"
            fi
        done

        # AWS credentials
        grep -nE 'AKIA[0-9A-Z]{16}' "$file" 2>/dev/null | while IFS=: read -r line_num match; do
            if ! echo "$match" | grep -q 'AKIAIOSFODNN7EXAMPLE'; then
                report_finding "CRITICAL" "AWS Credentials" "$file" "$line_num" "AWS access key detected"
            fi
        done
    fi
done < <(find . -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.sh" -o -name "*.md" \) \
    ! -path "./node_modules/*" \
    ! -path "./.git/*" \
    ! -path "./vendor/*")
echo -e "${GREEN}DONE${NC}"

# 3. Scan for insecure curl | sh patterns
echo -n "Checking for insecure curl | sh patterns... "
while IFS= read -r file; do
    if [ -f "$file" ]; then
        grep -n 'curl.*|.*sh' "$file" 2>/dev/null | while IFS=: read -r line_num match; do
            # Check if there's a security warning nearby (within 5 lines before)
            context_start=$((line_num - 5))
            [ $context_start -lt 1 ] && context_start=1

            if ! sed -n "${context_start},${line_num}p" "$file" | grep -qE 'SECURITY|WARNING|⚠️'; then
                report_finding "MEDIUM" "Insecure Installation" "$file" "$line_num" "curl | sh without security warning"
            fi
        done
    fi
done < <(find . -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.sh" -o -name "*.md" \) \
    ! -path "./node_modules/*" \
    ! -path "./.git/*" \
    ! -path "./vendor/*")
echo -e "${GREEN}DONE${NC}"

# 4. Scan for HTTP URLs (should be HTTPS)
echo -n "Checking for HTTP URLs (non-HTTPS)... "
while IFS= read -r file; do
    if [ -f "$file" ]; then
        grep -n 'http://[^[:space:]"'\'']*' "$file" 2>/dev/null | while IFS=: read -r line_num match; do
            # Skip localhost, internal services, and known exceptions
            if ! echo "$match" | grep -qE 'localhost|127\.0\.0\.1|\.svc\.|\.cluster\.local|http://archive\.ubuntu\.com|http://security\.ubuntu\.com'; then
                # Extract the URL
                url=$(echo "$match" | grep -oE 'http://[^[:space:]"'\'']*' | head -1)
                report_finding "LOW" "HTTP URL" "$file" "$line_num" "Non-HTTPS URL: $url"
            fi
        done
    fi
done < <(find . -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.sh" -o -name "*.md" \) \
    ! -path "./node_modules/*" \
    ! -path "./.git/*" \
    ! -path "./vendor/*")
echo -e "${GREEN}DONE${NC}"

# 5. Scan for insecure Kubernetes configurations
echo -n "Checking for insecure Kubernetes configurations... "
while IFS= read -r file; do
    if [ -f "$file" ]; then
        # Check for privileged containers
        grep -n 'privileged:.*true' "$file" 2>/dev/null | while IFS=: read -r line_num match; do
            report_finding "HIGH" "Privileged Container" "$file" "$line_num" "Container running in privileged mode"
        done

        # Check for hostNetwork
        grep -n 'hostNetwork:.*true' "$file" 2>/dev/null | while IFS=: read -r line_num match; do
            report_finding "MEDIUM" "Host Network" "$file" "$line_num" "Pod using host network"
        done

        # Check for hostPath volumes
        grep -n 'hostPath:' "$file" 2>/dev/null | while IFS=: read -r line_num match; do
            report_finding "MEDIUM" "Host Path Volume" "$file" "$line_num" "Pod using hostPath volume"
        done

        # Check for allowPrivilegeEscalation
        grep -n 'allowPrivilegeEscalation:.*true' "$file" 2>/dev/null | while IFS=: read -r line_num match; do
            report_finding "HIGH" "Privilege Escalation" "$file" "$line_num" "Container allows privilege escalation"
        done

        # Check for runAsNonRoot: false
        grep -n 'runAsNonRoot:.*false' "$file" 2>/dev/null | while IFS=: read -r line_num match; do
            report_finding "MEDIUM" "Root Container" "$file" "$line_num" "Container may run as root"
        done
    fi
done < <(find . -type f \( -name "*.yaml" -o -name "*.yml" \) \
    ! -path "./node_modules/*" \
    ! -path "./.git/*" \
    ! -path "./vendor/*")
echo -e "${GREEN}DONE${NC}"

# 6. Scan for missing security contexts
echo -n "Checking for missing security contexts... "
while IFS= read -r file; do
    if [ -f "$file" ]; then
        # Check if file contains Pod/Deployment but no securityContext
        if grep -q 'kind:.*\(Pod\|Deployment\|StatefulSet\|DaemonSet\|Job\)' "$file" 2>/dev/null; then
            if ! grep -q 'securityContext:' "$file" 2>/dev/null; then
                line_num=$(grep -n 'kind:.*\(Pod\|Deployment\|StatefulSet\|DaemonSet\|Job\)' "$file" | head -1 | cut -d: -f1)
                report_finding "LOW" "Missing Security Context" "$file" "$line_num" "Workload missing securityContext"
            fi
        fi
    fi
done < <(find . -type f \( -name "*.yaml" -o -name "*.yml" \) \
    ! -path "./node_modules/*" \
    ! -path "./.git/*" \
    ! -path "./vendor/*" \
    ! -path "*/tests/*")
echo -e "${GREEN}DONE${NC}"

# 7. Scan for Vault root token usage
echo -n "Checking for Vault root token usage... "
while IFS= read -r file; do
    if [ -f "$file" ]; then
        grep -n 'root-token\|VAULT_TOKEN.*root' "$file" 2>/dev/null | while IFS=: read -r line_num match; do
            # Check if there's a warning nearby
            context_start=$((line_num - 5))
            [ $context_start -lt 1 ] && context_start=1

            if ! sed -n "${context_start},${line_num}p" "$file" | grep -qE 'WARNING|TUTORIAL ONLY|⚠️'; then
                report_finding "HIGH" "Vault Root Token" "$file" "$line_num" "Root token usage without warning"
            fi
        done
    fi
done < <(find . -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.sh" -o -name "*.md" \) \
    ! -path "./node_modules/*" \
    ! -path "./.git/*" \
    ! -path "./vendor/*")
echo -e "${GREEN}DONE${NC}"

# 8. Scan for exposed ports
echo -n "Checking for potentially exposed ports... "
while IFS= read -r file; do
    if [ -f "$file" ]; then
        # Check for NodePort or LoadBalancer services
        if grep -q 'type:.*NodePort\|type:.*LoadBalancer' "$file" 2>/dev/null; then
            line_num=$(grep -n 'type:.*NodePort\|type:.*LoadBalancer' "$file" | head -1 | cut -d: -f1)
            # Skip if it's in a tutorial or example
            if ! echo "$file" | grep -qE 'tutorial|example'; then
                report_finding "LOW" "Exposed Service" "$file" "$line_num" "Service exposed via NodePort/LoadBalancer"
            fi
        fi
    fi
done < <(find . -type f \( -name "*.yaml" -o -name "*.yml" \) \
    ! -path "./node_modules/*" \
    ! -path "./.git/*" \
    ! -path "./vendor/*")
echo -e "${GREEN}DONE${NC}"

echo ""
echo "=== Scan Summary ==="
echo -e "Total issues found:   $TOTAL_ISSUES"
echo -e "${RED}Critical issues:      $CRITICAL_ISSUES${NC}"
echo -e "${RED}High issues:          $HIGH_ISSUES${NC}"
echo -e "${YELLOW}Medium issues:        $MEDIUM_ISSUES${NC}"
echo -e "${BLUE}Low issues:           $LOW_ISSUES${NC}"

if [ $TOTAL_ISSUES -gt 0 ]; then
    echo ""
    echo "=== Detailed Findings ==="

    if [ $CRITICAL_ISSUES -gt 0 ]; then
        echo ""
        echo -e "${RED}CRITICAL Issues:${NC}"
        grep "^\[CRITICAL\]" "$RESULTS" | while IFS= read -r line; do
            echo -e "  ${RED}$line${NC}"
        done
    fi

    if [ $HIGH_ISSUES -gt 0 ]; then
        echo ""
        echo -e "${RED}HIGH Issues:${NC}"
        grep "^\[HIGH\]" "$RESULTS" | while IFS= read -r line; do
            echo -e "  ${RED}$line${NC}"
        done
    fi

    if [ $MEDIUM_ISSUES -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}MEDIUM Issues:${NC}"
        grep "^\[MEDIUM\]" "$RESULTS" | while IFS= read -r line; do
            echo -e "  ${YELLOW}$line${NC}"
        done
    fi

    if [ $LOW_ISSUES -gt 0 ]; then
        echo ""
        echo -e "${BLUE}LOW Issues:${NC}"
        grep "^\[LOW\]" "$RESULTS" | while IFS= read -r line; do
            echo -e "  ${BLUE}$line${NC}"
        done
    fi

    echo ""
    echo "=== Recommendations ==="
    echo "1. Review all CRITICAL and HIGH issues immediately"
    echo "2. Use Kubernetes Secrets or external secret managers (Vault, ESO)"
    echo "3. Enable Pod Security Standards (restricted profile)"
    echo "4. Implement network policies to limit pod communication"
    echo "5. Use HTTPS for all external URLs"
    echo "6. Add securityContext to all workloads"
    echo "7. Follow principle of least privilege for all services"
fi

rm "$RESULTS"
rm "$SUMMARY"

# Exit with error if critical or high issues found
if [ $CRITICAL_ISSUES -gt 0 ] || [ $HIGH_ISSUES -gt 0 ]; then
    echo ""
    echo -e "${RED}❌ Security scan failed with $CRITICAL_ISSUES critical and $HIGH_ISSUES high severity issues${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ No critical or high severity issues found${NC}"
    if [ $TOTAL_ISSUES -gt 0 ]; then
        echo -e "${YELLOW}⚠️  However, $TOTAL_ISSUES medium/low severity issues should be reviewed${NC}"
    fi
    exit 0
fi
