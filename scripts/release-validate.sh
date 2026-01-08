#!/bin/bash
# release-validate.sh - Pre-release validation for Morphir
#
# This script validates that the repository is ready for release.
# Run this BEFORE creating tags or triggering the release workflow.
#
# Usage: ./scripts/release-validate.sh [OPTIONS] [VERSION]
#
# Options:
#   --json       Output results as JSON (for automation)
#   --quiet      Suppress non-essential output
#   -h, --help   Show this help message
#
# Arguments:
#   VERSION      Optional version to validate (e.g., v0.4.0-alpha.1)
#
# Exit codes:
#   0 - All validations passed
#   1 - Validation failed (check output for details)
#
# Examples:
#   ./scripts/release-validate.sh v0.4.0-alpha.1
#   ./scripts/release-validate.sh --json v0.4.0
#   ./scripts/release-validate.sh --json | jq '.checks[] | select(.status == "error")'

set -e

# Default options
JSON_OUTPUT=false
QUIET=false
VERSION=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --quiet|-q)
            QUIET=true
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

# Colors for output (disabled for JSON)
if [ "$JSON_OUTPUT" = true ]; then
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

# Counters and results
ERRORS=0
WARNINGS=0
declare -a JSON_CHECKS=()

# Helper functions
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
        echo -e "${RED}ERROR:${NC} $message"
        if [ -n "$details" ]; then
            echo "  $details"
        fi
    fi
    ((ERRORS++))
}

warn() {
    local name="$1"
    local message="$2"
    local details="${3:-}"
    add_check "$name" "warning" "$message" "$details"
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${YELLOW}WARNING:${NC} $message"
        if [ -n "$details" ]; then
            echo "  $details"
        fi
    fi
    ((WARNINGS++))
}

success() {
    local name="$1"
    local message="$2"
    add_check "$name" "success" "$message"
    if [ "$JSON_OUTPUT" = false ] && [ "$QUIET" = false ]; then
        echo -e "${GREEN}✓${NC} $message"
    fi
}

header() {
    if [ "$JSON_OUTPUT" = false ] && [ "$QUIET" = false ]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " $1"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
}

# Header
if [ "$JSON_OUTPUT" = false ] && [ "$QUIET" = false ]; then
    echo ""
    echo "Morphir Release Validation"
    echo "=========================="
    echo ""
    if [ -n "$VERSION" ]; then
        echo "Validating for version: $VERSION"
    fi
fi

# 1. Check for replace directives
header "Checking for replace directives"

REPLACE_FILES=""
while IFS= read -r -d '' gomod; do
    if grep -q "^replace " "$gomod" 2>/dev/null; then
        REPLACE_FILES="$REPLACE_FILES $gomod"
    fi
done < <(find . -name "go.mod" -type f -print0)

if [ -n "$REPLACE_FILES" ]; then
    error "replace_directives" "Replace directives found in go.mod files" "$REPLACE_FILES"
else
    success "replace_directives" "No replace directives found"
fi

# 2. Check for pseudo-versions
header "Checking for pseudo-versions"

PSEUDO_FILES=""
while IFS= read -r -d '' gomod; do
    if grep -qE "github\.com/finos/morphir.*v[0-9]+\.[0-9]+\.[0-9]+-[0-9]{14}-[a-f0-9]+" "$gomod" 2>/dev/null; then
        PSEUDO_FILES="$PSEUDO_FILES $gomod"
    fi
done < <(find . -name "go.mod" -type f -print0)

if [ -n "$PSEUDO_FILES" ]; then
    error "pseudo_versions" "Pseudo-versions found in go.mod files" "$PSEUDO_FILES"
else
    success "pseudo_versions" "No pseudo-versions found"
fi

# 3. Check CHANGELOG.md is committed
header "Checking CHANGELOG.md for go:embed"

if [ -f "cmd/morphir/cmd/CHANGELOG.md" ]; then
    if git ls-files --error-unmatch cmd/morphir/cmd/CHANGELOG.md >/dev/null 2>&1; then
        success "changelog_embed" "cmd/morphir/cmd/CHANGELOG.md is tracked by git"
    else
        error "changelog_embed" "cmd/morphir/cmd/CHANGELOG.md exists but is not tracked by git" "Run: git add cmd/morphir/cmd/CHANGELOG.md"
    fi
else
    error "changelog_embed" "cmd/morphir/cmd/CHANGELOG.md does not exist" "Run: cp CHANGELOG.md cmd/morphir/cmd/CHANGELOG.md"
fi

# 4. Check go.work is not staged
header "Checking go.work is not staged"

if git diff --cached --name-only | grep -q "go.work"; then
    error "go_work_staged" "go.work is staged for commit" "Run: git reset go.work go.work.sum"
else
    success "go_work_staged" "go.work is not staged"
fi

# 5. Validate goreleaser config
header "Validating GoReleaser configuration"

if command -v goreleaser >/dev/null 2>&1; then
    if goreleaser check 2>/dev/null; then
        success "goreleaser_config" "GoReleaser configuration is valid"
    else
        error "goreleaser_config" "GoReleaser configuration is invalid"
    fi
else
    warn "goreleaser_config" "goreleaser not installed, skipping validation" "Install: go install github.com/goreleaser/goreleaser/v2@latest"
fi

# 6. Check goreleaser has GONOSUMDB
header "Checking GoReleaser GONOSUMDB configuration"

if grep -q "GONOSUMDB=github.com/finos/morphir" .goreleaser.yaml 2>/dev/null; then
    success "gonosumdb" "GONOSUMDB is configured in .goreleaser.yaml"
else
    error "gonosumdb" "GONOSUMDB not configured in .goreleaser.yaml" "Add to env: - GONOSUMDB=github.com/finos/morphir/*"
fi

# 7. Check goreleaser has dir: cmd/morphir
header "Checking GoReleaser build directory"

if grep -q "dir: cmd/morphir" .goreleaser.yaml 2>/dev/null; then
    success "build_dir" "Build directory is configured correctly"
else
    error "build_dir" "Build directory not configured in .goreleaser.yaml" "Add to builds: dir: cmd/morphir"
fi

# 8. Check no go work sync in hooks
header "Checking GoReleaser hooks"

if grep -q "go work sync" .goreleaser.yaml 2>/dev/null; then
    error "go_work_sync" "go work sync found in goreleaser hooks" "Remove from before.hooks"
else
    success "go_work_sync" "No problematic hooks found"
fi

# 9. Check git status is clean
header "Checking git status"

DIRTY_FILES=$(git status --porcelain 2>/dev/null | wc -l)
if [ "$DIRTY_FILES" -gt 0 ]; then
    warn "git_clean" "Working directory has $DIRTY_FILES uncommitted changes"
else
    success "git_clean" "Working directory is clean"
fi

# 10. Check CHANGELOG has version section
header "Checking CHANGELOG.md"

if [ -n "$VERSION" ]; then
    VERSION_NO_V="${VERSION#v}"
    if grep -qE "## \[?${VERSION_NO_V}\]?" CHANGELOG.md 2>/dev/null; then
        success "changelog_version" "CHANGELOG.md has section for $VERSION"
    else
        warn "changelog_version" "CHANGELOG.md may not have section for $VERSION" "Ensure CHANGELOG.md is updated before release"
    fi
else
    if grep -q "## \[Unreleased\]" CHANGELOG.md 2>/dev/null; then
        success "changelog_version" "CHANGELOG.md has Unreleased section"
    else
        warn "changelog_version" "CHANGELOG.md has no Unreleased section"
    fi
fi

# 11. Check module list in release-tags.sh matches actual modules
header "Checking release-tags.sh module list"

if [ -f "scripts/release-tags.sh" ]; then
    SCRIPT_MODULES=$(grep -E '^\s+"(pkg|cmd)/' scripts/release-tags.sh 2>/dev/null | tr -d ' "' | sort || echo "")
    ACTUAL_MODULES=$(find . -name "go.mod" -type f | xargs -I{} dirname {} | sed 's|^\./||' | grep -E "^(pkg|cmd)/" | sort)

    MISSING=""
    for mod in $ACTUAL_MODULES; do
        if ! echo "$SCRIPT_MODULES" | grep -q "^${mod}$"; then
            MISSING="$MISSING $mod"
        fi
    done

    if [ -n "$MISSING" ]; then
        warn "module_list" "Modules in repo but not in release-tags.sh:$MISSING"
    else
        success "module_list" "All modules are listed in release-tags.sh"
    fi
else
    warn "module_list" "scripts/release-tags.sh not found"
fi

# Output JSON or summary
if [ "$JSON_OUTPUT" = true ]; then
    # Build JSON output
    STATUS="success"
    if [ $ERRORS -gt 0 ]; then
        STATUS="error"
    elif [ $WARNINGS -gt 0 ]; then
        STATUS="warning"
    fi

    CHECKS_JSON=$(IFS=,; echo "${JSON_CHECKS[*]}")

    cat <<EOF
{
  "version": "${VERSION:-null}",
  "status": "$STATUS",
  "errors": $ERRORS,
  "warnings": $WARNINGS,
  "checks": [$CHECKS_JSON]
}
EOF
else
    # Summary
    header "Validation Summary"
    echo ""

    if [ $ERRORS -gt 0 ]; then
        echo -e "${RED}FAILED${NC}: $ERRORS error(s), $WARNINGS warning(s)"
        echo ""
        echo "Please fix the errors above before proceeding with release."
        exit 1
    elif [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}PASSED WITH WARNINGS${NC}: $WARNINGS warning(s)"
        echo ""
        echo "Review warnings above. You may proceed with release if they are acceptable."
        exit 0
    else
        echo -e "${GREEN}PASSED${NC}: All validations successful"
        echo ""
        echo "Repository is ready for release."
        exit 0
    fi
fi
