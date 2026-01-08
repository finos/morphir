#!/bin/bash
# release-verify.sh - Verify a Morphir release
#
# This script verifies that a release was successful by checking:
# - GitHub release exists with all assets
# - Tags are accessible on remote
# - go install works (with GONOSUMDB for new releases)
#
# Usage: ./scripts/release-verify.sh [OPTIONS] <version>
#
# Options:
#   --json           Output results as JSON
#   --skip-install   Skip go install test (faster)
#   --wait           Wait for sum.golang.org indexing (up to 5 min)
#   -h, --help       Show this help message
#
# Examples:
#   ./scripts/release-verify.sh v0.4.0-alpha.1
#   ./scripts/release-verify.sh --json v0.4.0
#   ./scripts/release-verify.sh --skip-install v0.4.0

set -e

# Default options
JSON_OUTPUT=false
SKIP_INSTALL=false
WAIT_FOR_INDEX=false
VERSION=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --skip-install)
            SKIP_INSTALL=true
            shift
            ;;
        --wait)
            WAIT_FOR_INDEX=true
            shift
            ;;
        -h|--help)
            grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            VERSION="$1"
            shift
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo "Usage: $0 [OPTIONS] <version>"
    echo "Example: $0 v0.4.0-alpha.1"
    exit 1
fi

# Colors (disabled for JSON)
if [ "$JSON_OUTPUT" = true ]; then
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
fi

ERRORS=0
WARNINGS=0
declare -a JSON_CHECKS=()

add_check() {
    local name="$1"
    local status="$2"
    local message="$3"
    local details="${4:-}"

    if [ "$JSON_OUTPUT" = true ]; then
        local json_details=""
        if [ -n "$details" ]; then
            json_details=", \"details\": \"$(echo "$details" | sed 's/"/\\"/g' | tr '\n' ' ')\""
        fi
        JSON_CHECKS+=("{\"name\": \"$name\", \"status\": \"$status\", \"message\": \"$message\"$json_details}")
    fi
}

error() {
    local name="$1"
    local message="$2"
    local details="${3:-}"
    add_check "$name" "error" "$message" "$details"
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${RED}✗${NC} $message"
        [ -n "$details" ] && echo "  $details"
    fi
    ((ERRORS++))
}

warn() {
    local name="$1"
    local message="$2"
    local details="${3:-}"
    add_check "$name" "warning" "$message" "$details"
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${YELLOW}!${NC} $message"
        [ -n "$details" ] && echo "  $details"
    fi
    ((WARNINGS++))
}

success() {
    local name="$1"
    local message="$2"
    local details="${3:-}"
    add_check "$name" "success" "$message" "$details"
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${GREEN}✓${NC} $message"
    fi
}

info() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${BLUE}→${NC} $1"
    fi
}

header() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " $1"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
}

output_json() {
    local status="success"
    [ $ERRORS -gt 0 ] && status="error"
    [ $ERRORS -eq 0 ] && [ $WARNINGS -gt 0 ] && status="warning"

    CHECKS_JSON=$(IFS=,; echo "${JSON_CHECKS[*]}")

    cat <<EOF
{
  "version": "$VERSION",
  "status": "$status",
  "errors": $ERRORS,
  "warnings": $WARNINGS,
  "release_url": "https://github.com/finos/morphir/releases/tag/$VERSION",
  "checks": [$CHECKS_JSON]
}
EOF
}

# Start verification
if [ "$JSON_OUTPUT" = false ]; then
    echo ""
    echo "Verifying Morphir Release $VERSION"
    echo "==================================="
fi

# 1. Check GitHub release exists
header "Checking GitHub Release"

if command -v gh >/dev/null 2>&1; then
    if gh release view "$VERSION" >/dev/null 2>&1; then
        success "github_release" "GitHub release $VERSION exists"

        # Check release assets
        EXPECTED_ASSETS=(
            "morphir_${VERSION#v}_Darwin_arm64.tar.gz"
            "morphir_${VERSION#v}_Darwin_x86_64.tar.gz"
            "morphir_${VERSION#v}_Linux_arm64.tar.gz"
            "morphir_${VERSION#v}_Linux_x86_64.tar.gz"
            "morphir_${VERSION#v}_Windows_x86_64.tar.gz"
            "checksums.txt"
        )

        ASSETS=$(gh release view "$VERSION" --json assets -q '.assets[].name' 2>/dev/null || echo "")
        MISSING_ASSETS=""
        for asset in "${EXPECTED_ASSETS[@]}"; do
            if echo "$ASSETS" | grep -q "^${asset}$"; then
                success "asset_$asset" "Asset found: $asset"
            else
                MISSING_ASSETS="$MISSING_ASSETS $asset"
            fi
        done

        if [ -n "$MISSING_ASSETS" ]; then
            error "release_assets" "Missing release assets:$MISSING_ASSETS"
        fi
    else
        error "github_release" "GitHub release $VERSION not found"
    fi
else
    warn "github_release" "gh CLI not installed, skipping GitHub release check"
fi

# 2. Check tags exist on remote
header "Checking Remote Tags"

MODULES=(
    "pkg/bindings/typemap"
    "pkg/bindings/wit"
    "pkg/config"
    "pkg/docling-doc"
    "pkg/models"
    "pkg/nbformat"
    "pkg/pipeline"
    "pkg/sdk"
    "pkg/task"
    "pkg/tooling"
    "pkg/vfs"
    "cmd/morphir"
)

REMOTE_TAGS=$(git ls-remote --tags origin 2>/dev/null || echo "")
MISSING_TAGS=0

# Check main tag
if echo "$REMOTE_TAGS" | grep -q "refs/tags/${VERSION}$"; then
    success "tag_main" "Tag exists: $VERSION"
else
    error "tag_main" "Tag missing: $VERSION"
    ((MISSING_TAGS++))
fi

# Check module tags
for module in "${MODULES[@]}"; do
    tag="${module}/${VERSION}"
    if echo "$REMOTE_TAGS" | grep -q "refs/tags/${tag}$"; then
        success "tag_$module" "Tag exists: $tag"
    else
        error "tag_$module" "Tag missing: $tag"
        ((MISSING_TAGS++))
    fi
done

# 3. Check Go module availability
if [ "$SKIP_INSTALL" = false ]; then
    header "Checking Go Module Availability"

    info "Testing go install (this may take a moment)..."

    # Create temp directory for test
    TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT

    cd "$TMPDIR"

    # Try with GONOSUMDB first (for fresh releases)
    INSTALL_OUTPUT=$(GONOSUMDB=github.com/finos/morphir/* go install "github.com/finos/morphir/cmd/morphir@${VERSION}" 2>&1) || true

    if [ $? -eq 0 ] && [ -z "$INSTALL_OUTPUT" ]; then
        success "go_install_gonosumdb" "go install works (with GONOSUMDB)"

        # Test the binary
        MORPHIR_PATH=$(go env GOPATH)/bin/morphir
        if [ -x "$MORPHIR_PATH" ]; then
            INSTALLED_VERSION=$("$MORPHIR_PATH" about --json 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
            success "binary_installed" "morphir binary installed, version: $INSTALLED_VERSION"
        else
            warn "binary_installed" "morphir binary not found after install"
        fi
    else
        error "go_install_gonosumdb" "go install failed even with GONOSUMDB" "$INSTALL_OUTPUT"
    fi

    # Try without GONOSUMDB (to check if sum.golang.org has indexed)
    info "Checking if sum.golang.org has indexed the release..."

    if [ "$WAIT_FOR_INDEX" = true ]; then
        info "Waiting for sum.golang.org indexing (max 5 minutes)..."
        for i in {1..10}; do
            if go install "github.com/finos/morphir/cmd/morphir@${VERSION}" 2>/dev/null; then
                success "go_install_direct" "go install works without GONOSUMDB (sum.golang.org indexed)"
                break
            fi
            if [ $i -lt 10 ]; then
                info "  Attempt $i/10 failed, waiting 30 seconds..."
                sleep 30
            fi
        done
    else
        if go install "github.com/finos/morphir/cmd/morphir@${VERSION}" 2>/dev/null; then
            success "go_install_direct" "go install works without GONOSUMDB (sum.golang.org indexed)"
        else
            warn "go_install_direct" "sum.golang.org has not yet indexed this release" "Users should use: GONOSUMDB=github.com/finos/morphir/* go install ..."
        fi
    fi

    cd - >/dev/null
else
    if [ "$JSON_OUTPUT" = false ]; then
        info "Skipping go install test (--skip-install)"
    fi
    add_check "go_install" "skipped" "go install test skipped"
fi

# 4. Check proxy.golang.org
header "Checking Go Module Proxy"

PROXY_URL="https://proxy.golang.org/github.com/finos/morphir/cmd/morphir/@v/${VERSION}.info"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PROXY_URL" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    success "proxy_golang" "Module available on proxy.golang.org"
else
    warn "proxy_golang" "Module may not be fully indexed on proxy.golang.org yet (HTTP $HTTP_CODE)" "This can take up to 24 hours after release"
fi

# Output
if [ "$JSON_OUTPUT" = true ]; then
    output_json
else
    header "Verification Summary"
    echo ""

    if [ $ERRORS -gt 0 ]; then
        echo -e "${RED}VERIFICATION FAILED${NC}: $ERRORS error(s), $WARNINGS warning(s)"
        echo ""
        echo "Please investigate the errors above."
        exit 1
    elif [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}VERIFICATION PASSED WITH WARNINGS${NC}: $WARNINGS warning(s)"
        echo ""
        echo "Release is successful. Warnings may resolve themselves over time."
        echo ""
        echo "Release URL: https://github.com/finos/morphir/releases/tag/$VERSION"
        exit 0
    else
        echo -e "${GREEN}VERIFICATION PASSED${NC}: All checks successful"
        echo ""
        echo "Release URL: https://github.com/finos/morphir/releases/tag/$VERSION"
        exit 0
    fi
fi
