#!/bin/bash
# ABOUTME: Link checker script for markdown files and documentation
# ABOUTME: Validates internal file references and external URLs for broken links

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Link Checker ==="
echo ""

# Counters
TOTAL_LINKS=0
INTERNAL_LINKS=0
EXTERNAL_LINKS=0
BROKEN_LINKS=0
VALID_LINKS=0
SKIPPED_LINKS=0

# Temporary files
BROKEN_LOG=$(mktemp)
CHECKED_URLS=$(mktemp)

# Function to check if URL was already checked
was_checked() {
    local url=$1
    grep -qF "$url" "$CHECKED_URLS" 2>/dev/null
}

# Function to mark URL as checked
mark_checked() {
    local url=$1
    local status=$2
    echo "$url|$status" >> "$CHECKED_URLS"
}

# Function to get cached status
get_cached_status() {
    local url=$1
    grep -F "$url|" "$CHECKED_URLS" 2>/dev/null | cut -d'|' -f2
}

# Function to check external URL
check_external_url() {
    local url=$1

    # Skip if already checked
    if was_checked "$url"; then
        echo "$(get_cached_status "$url")"
        return
    fi

    # Skip certain URLs that are known to block automated requests
    if echo "$url" | grep -qE 'linkedin\.com|facebook\.com|twitter\.com|x\.com'; then
        mark_checked "$url" "SKIP"
        echo "SKIP"
        return
    fi

    # Use curl with timeout and follow redirects
    if curl -s -L -f -m 10 --head "$url" > /dev/null 2>&1; then
        mark_checked "$url" "OK"
        echo "OK"
    else
        # Try GET request if HEAD fails (some servers don't support HEAD)
        if curl -s -L -f -m 10 "$url" > /dev/null 2>&1; then
            mark_checked "$url" "OK"
            echo "OK"
        else
            mark_checked "$url" "FAIL"
            echo "FAIL"
        fi
    fi

    # Rate limiting to avoid overwhelming servers
    sleep 0.5
}

# Function to check internal file reference
check_internal_file() {
    local file=$1
    local ref=$2

    # Get directory of the markdown file
    local dir=$(dirname "$file")

    # Resolve relative path
    local target_file="$dir/$ref"

    # Normalize path (resolve .. and .)
    target_file=$(readlink -m "$target_file")

    # Check if file exists
    if [ -f "$target_file" ] || [ -d "$target_file" ]; then
        echo "OK"
    else
        echo "FAIL"
    fi
}

# Function to extract and check links from a file
check_links_in_file() {
    local file=$1

    echo -n "Checking $file... "

    local file_links=0
    local file_broken=0

    # Extract markdown links [text](url) and [text]: url
    while IFS= read -r line; do
        # Extract links from [text](url) format
        echo "$line" | grep -oE '\[([^\]]+)\]\(([^)]+)\)' | while IFS= read -r match; do
            # Extract URL from parentheses
            url=$(echo "$match" | sed -E 's/.*\(([^)]+)\).*/\1/')

            # Skip anchors and empty links
            [ -z "$url" ] && continue
            [[ "$url" == \#* ]] && continue

            ((TOTAL_LINKS++))
            ((file_links++))

            # Check if it's an external URL
            if [[ "$url" =~ ^https?:// ]]; then
                ((EXTERNAL_LINKS++))

                status=$(check_external_url "$url")

                if [ "$status" == "FAIL" ]; then
                    echo "EXTERNAL|BROKEN|$file|$url" >> "$BROKEN_LOG"
                    ((BROKEN_LINKS++))
                    ((file_broken++))
                elif [ "$status" == "OK" ]; then
                    ((VALID_LINKS++))
                else
                    ((SKIPPED_LINKS++))
                fi
            else
                # Internal file reference
                ((INTERNAL_LINKS++))

                status=$(check_internal_file "$file" "$url")

                if [ "$status" == "FAIL" ]; then
                    echo "INTERNAL|BROKEN|$file|$url" >> "$BROKEN_LOG"
                    ((BROKEN_LINKS++))
                    ((file_broken++))
                else
                    ((VALID_LINKS++))
                fi
            fi
        done

        # Extract reference-style links [text]: url
        if echo "$line" | grep -qE '^\[([^\]]+)\]:\s*(.+)$'; then
            url=$(echo "$line" | sed -E 's/^\[([^\]]+)\]:\s*(.+)$/\2/' | tr -d ' ')

            # Skip anchors and empty links
            [ -z "$url" ] && continue
            [[ "$url" == \#* ]] && continue

            ((TOTAL_LINKS++))
            ((file_links++))

            if [[ "$url" =~ ^https?:// ]]; then
                ((EXTERNAL_LINKS++))

                status=$(check_external_url "$url")

                if [ "$status" == "FAIL" ]; then
                    echo "EXTERNAL|BROKEN|$file|$url" >> "$BROKEN_LOG"
                    ((BROKEN_LINKS++))
                    ((file_broken++))
                elif [ "$status" == "OK" ]; then
                    ((VALID_LINKS++))
                else
                    ((SKIPPED_LINKS++))
                fi
            else
                ((INTERNAL_LINKS++))

                status=$(check_internal_file "$file" "$url")

                if [ "$status" == "FAIL" ]; then
                    echo "INTERNAL|BROKEN|$file|$url" >> "$BROKEN_LOG"
                    ((BROKEN_LINKS++))
                    ((file_broken++))
                else
                    ((VALID_LINKS++))
                fi
            fi
        fi
    done < "$file"

    if [ $file_broken -gt 0 ]; then
        echo -e "${RED}BROKEN ($file_broken/$file_links)${NC}"
    else
        echo -e "${GREEN}OK ($file_links links)${NC}"
    fi
}

# Find all markdown files
MD_FILES=$(find . -type f \( -name "*.md" -o -name "*.markdown" \) \
    ! -path "./node_modules/*" \
    ! -path "./.git/*" \
    ! -path "./vendor/*")

TOTAL_FILES=$(echo "$MD_FILES" | wc -l)

echo "Found $TOTAL_FILES markdown files to check"
echo ""

# Check links in each file
for file in $MD_FILES; do
    check_links_in_file "$file"
done

echo ""
echo "=== Link Check Summary ==="
echo -e "Total files checked:     $TOTAL_FILES"
echo -e "Total links found:       $TOTAL_LINKS"
echo -e "  Internal links:        $INTERNAL_LINKS"
echo -e "  External links:        $EXTERNAL_LINKS"
echo -e "${GREEN}Valid links:             $VALID_LINKS${NC}"
echo -e "${RED}Broken links:            $BROKEN_LINKS${NC}"
echo -e "${YELLOW}Skipped links:           $SKIPPED_LINKS${NC}"

if [ $BROKEN_LINKS -gt 0 ]; then
    echo ""
    echo "=== Broken Links ==="

    # Show broken internal links first
    if grep -q "^INTERNAL|BROKEN" "$BROKEN_LOG" 2>/dev/null; then
        echo ""
        echo -e "${RED}Broken Internal Links:${NC}"
        grep "^INTERNAL|BROKEN" "$BROKEN_LOG" | while IFS='|' read -r type status file url; do
            echo -e "  ${RED}✗${NC} $file"
            echo -e "    → $url"
        done
    fi

    # Show broken external links
    if grep -q "^EXTERNAL|BROKEN" "$BROKEN_LOG" 2>/dev/null; then
        echo ""
        echo -e "${RED}Broken External Links:${NC}"
        grep "^EXTERNAL|BROKEN" "$BROKEN_LOG" | while IFS='|' read -r type status file url; do
            echo -e "  ${RED}✗${NC} $file"
            echo -e "    → $url"
        done
    fi

    echo ""
    echo "=== Recommendations ==="
    echo "1. Update or remove broken internal file references"
    echo "2. Verify external URLs are still valid"
    echo "3. Consider using archive.org for deprecated external links"
    echo "4. Update relative paths if files were moved"
fi

rm "$BROKEN_LOG"
rm "$CHECKED_URLS"

# Exit with error if broken links found
if [ $BROKEN_LINKS -gt 0 ]; then
    echo ""
    echo -e "${RED}❌ Link check failed with $BROKEN_LINKS broken links${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ All links are valid!${NC}"
    if [ $SKIPPED_LINKS -gt 0 ]; then
        echo -e "${YELLOW}⚠️  $SKIPPED_LINKS links were skipped (social media sites)${NC}"
    fi
    exit 0
fi
