#!/usr/bin/env bash
#
# check_links.sh - Check for broken links in Morphir documentation
#
# This script leverages Docusaurus's built-in link checking by running
# a production build with strict link checking enabled.
#
# Usage:
#   ./check_links.sh [--fix] [--markdown-only]
#
# Options:
#   --fix            Attempt to suggest fixes for broken links
#   --markdown-only  Only check markdown links (faster)
#
# Exit codes:
#   0 - No broken links found
#   1 - Broken links detected
#   2 - Build/setup error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve repository root robustly (repo layouts can vary).
# Prefer git, then fall back to a relative path that matches this monorepo layout.
if PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
    true
else
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
fi
WEBSITE_DIR="$PROJECT_ROOT/website"
DOCS_DIR="$PROJECT_ROOT/docs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

FIX_MODE=false
MARKDOWN_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --fix)
            FIX_MODE=true
            shift
            ;;
        --markdown-only)
            MARKDOWN_ONLY=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 2
            ;;
    esac
done

echo -e "${BLUE}=== Morphir Documentation Link Checker ===${NC}"
echo ""

# Check if we're in the right directory
if [[ ! -d "$WEBSITE_DIR" ]]; then
    echo -e "${RED}Error: website directory not found at $WEBSITE_DIR${NC}"
    exit 2
fi

if [[ ! -d "$DOCS_DIR" ]]; then
    echo -e "${RED}Error: docs directory not found at $DOCS_DIR${NC}"
    exit 2
fi

# Function to check markdown links manually
check_markdown_links() {
    echo -e "${BLUE}Checking markdown links in docs/...${NC}"
    echo ""

    local broken_count=0
    local checked_count=0

    # Find all markdown files
    while IFS= read -r -d '' file; do
        # Use pre-increment to avoid `set -e` exiting on a 0-valued arithmetic result.
        ((++checked_count))

        # Extract markdown links [text](link)
        while IFS= read -r link; do
            # Skip links we can't reliably validate offline:
            # - external URLs (http/https)
            # - mailto links
            # - page anchors
            # - absolute site routes (Docusaurus routes like /docs/... or /schemas/...)
            # - empty links
            if [[ "$link" =~ ^https?:// ]] || [[ "$link" =~ ^mailto: ]] || [[ "$link" =~ ^# ]] || [[ "$link" =~ ^/ ]] || [[ -z "$link" ]]; then
                continue
            fi

            # Remove anchor from link
            local clean_link="${link%%#*}"

            # Skip empty after anchor removal
            if [[ -z "$clean_link" ]]; then
                continue
            fi

            # Resolve the link relative to the file
            local file_dir=$(dirname "$file")
            local target_path

            # Relative path only (absolute routes are skipped above)
            target_path="$file_dir/$clean_link"

            # Normalize path
            target_path=$(realpath -m "$target_path" 2>/dev/null || echo "$target_path")

            # Check if target exists (with or without .md extension)
            if [[ ! -e "$target_path" ]] && [[ ! -e "${target_path}.md" ]] && [[ ! -d "$target_path" ]]; then
                echo -e "${RED}BROKEN:${NC} $file"
                echo -e "  Link: $link"
                echo -e "  Expected: $target_path"
                ((++broken_count))

                if $FIX_MODE; then
                    # Try to find a similar file
                    local basename=$(basename "$clean_link" .md)
                    local suggestions=$(find "$DOCS_DIR" -iname "*${basename}*" -type f 2>/dev/null | head -3)
                    if [[ -n "$suggestions" ]]; then
                        echo -e "${YELLOW}  Suggestions:${NC}"
                        echo "$suggestions" | while read -r sug; do
                            echo "    - ${sug#$DOCS_DIR/}"
                        done
                    fi
                fi
                echo ""
            fi
        done < <(grep -oP '\]\(\K[^)]+' "$file" 2>/dev/null || true)

    done < <(find "$DOCS_DIR" -name "*.md" -type f -print0)

    echo -e "${BLUE}Checked $checked_count files${NC}"

    if [[ $broken_count -eq 0 ]]; then
        echo -e "${GREEN}No broken markdown links found!${NC}"
        return 0
    else
        echo -e "${RED}Found $broken_count broken links${NC}"
        return 1
    fi
}

# Function to run docusaurus build with strict link checking
run_docusaurus_build() {
    echo -e "${BLUE}Running Docusaurus build with link checking...${NC}"
    echo ""

    cd "$WEBSITE_DIR"

    # Check if node_modules exists
    if [[ ! -d "node_modules" ]]; then
        echo -e "${YELLOW}Installing dependencies...${NC}"
        npm install
    fi

    # Create a temporary config with strict link checking
    local temp_config=$(mktemp)
    cat > "$temp_config" << 'EOF'
const originalConfig = require('./docusaurus.config.js');

module.exports = {
    ...originalConfig,
    onBrokenLinks: 'throw',
    onBrokenMarkdownLinks: 'throw',
};
EOF

    # Run the build and capture output
    local build_output
    local build_status=0

    echo -e "${BLUE}Building documentation (this may take a minute)...${NC}"

    if build_output=$(npm run build 2>&1); then
        echo -e "${GREEN}Build successful - no broken links detected!${NC}"
        rm -f "$temp_config"
        return 0
    else
        build_status=1
        echo -e "${RED}Build failed - checking for broken links...${NC}"
        echo ""

        # Extract broken link errors from output
        echo "$build_output" | grep -E "(broken|Broken|error|Error)" | head -20

        rm -f "$temp_config"
        return 1
    fi
}

# Main execution
if $MARKDOWN_ONLY; then
    check_markdown_links
    exit $?
else
    # Run both checks
    md_status=0
    build_status=0

    check_markdown_links || md_status=$?
    echo ""

    # Optionally run full docusaurus build
    if [[ -f "$WEBSITE_DIR/package.json" ]]; then
        echo -e "${YELLOW}Tip: Run 'npm run build' in website/ for complete link validation${NC}"
    fi

    if [[ $md_status -ne 0 ]]; then
        exit 1
    fi
    exit 0
fi
