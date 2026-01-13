#!/bin/bash
# release-tags.sh - Manage release tags for Morphir multi-module repo
#
# This script creates, deletes, or recreates all module tags for a release.
#
# Usage:
#   ./scripts/release-tags.sh [OPTIONS] <action> <version> [commit]
#
# Actions:
#   create    Create all module tags locally
#   delete    Delete all module tags (local and remote)
#   recreate  Delete and recreate all module tags
#   list      List all tags for a version
#   push      Push all module tags to remote
#
# Options:
#   --dry-run    Show what would be done without making changes
#   --json       Output results as JSON
#   --no-verify  Skip pre-push hooks when pushing
#   -h, --help   Show this help message
#
# Arguments:
#   version    Version to tag (e.g., v0.4.0-alpha.1)
#   commit     Optional commit to tag (defaults to HEAD)
#
# Examples:
#   ./scripts/release-tags.sh create v0.4.0-alpha.1
#   ./scripts/release-tags.sh --dry-run create v0.4.0-alpha.1
#   ./scripts/release-tags.sh --json list v0.4.0-alpha.1
#   ./scripts/release-tags.sh recreate v0.4.0-alpha.1 abc123

set -e

# Default options
DRY_RUN=false
JSON_OUTPUT=false
NO_VERIFY=true  # Default to --no-verify for release pushes

# Module paths (must match actual modules in repo)
MODULES=(
    "pkg/bindings/golang"
    "pkg/bindings/morphir-elm"
    "pkg/bindings/typemap"
    "pkg/bindings/wit"
    "pkg/config"
    "pkg/docling-doc"
    "pkg/models"
    "pkg/nbformat"
    "pkg/pipeline"
    "pkg/sdk"
    "pkg/task"
    "pkg/toolchain"
    "pkg/tooling"
    "pkg/vfs"
    "cmd/morphir"
)

# Colors (disabled for JSON output)
setup_colors() {
    if [ "$JSON_OUTPUT" = true ]; then
        RED='' GREEN='' YELLOW='' BLUE='' NC=''
    else
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        NC='\033[0m'
    fi
}

# Parse arguments
ACTION=""
VERSION=""
COMMIT="HEAD"

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --no-verify)
            NO_VERIFY=true
            shift
            ;;
        --verify)
            NO_VERIFY=false
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
            if [ -z "$ACTION" ]; then
                ACTION="$1"
            elif [ -z "$VERSION" ]; then
                VERSION="$1"
            else
                COMMIT="$1"
            fi
            shift
            ;;
    esac
done

setup_colors

# Validate arguments
usage() {
    echo "Usage: $0 [OPTIONS] <action> <version> [commit]"
    echo ""
    echo "Actions: create, delete, recreate, list, push"
    echo "Options: --dry-run, --json, --no-verify, -h/--help"
    echo ""
    echo "Example: $0 create v0.4.0-alpha.1"
    exit 1
}

if [ -z "$ACTION" ] || [ -z "$VERSION" ]; then
    usage
fi

# Validate version format
if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo -e "${RED}ERROR:${NC} Invalid version format: $VERSION"
    echo "Expected format: v1.2.3 or v1.2.3-alpha.1"
    exit 1
fi

# Resolve commit
ORIGINAL_COMMIT="$COMMIT"
if [ "$COMMIT" = "HEAD" ]; then
    COMMIT=$(git rev-parse HEAD)
fi
COMMIT_SHORT=$(git rev-parse --short "$COMMIT" 2>/dev/null || echo "$COMMIT")

# JSON output helpers
declare -a JSON_RESULTS=()

add_result() {
    local tag="$1"
    local action="$2"
    local status="$3"
    local message="${4:-}"

    if [ "$JSON_OUTPUT" = true ]; then
        JSON_RESULTS+=("{\"tag\": \"$tag\", \"action\": \"$action\", \"status\": \"$status\", \"message\": \"$message\"}")
    fi
}

output_json() {
    local overall_status="$1"
    local action="$2"

    RESULTS_JSON=$(IFS=,; echo "${JSON_RESULTS[*]}")

    cat <<EOF
{
  "version": "$VERSION",
  "commit": "$COMMIT_SHORT",
  "action": "$action",
  "dry_run": $DRY_RUN,
  "status": "$overall_status",
  "total_tags": $((${#MODULES[@]} + 1)),
  "results": [$RESULTS_JSON]
}
EOF
}

# Helper functions for non-JSON output
info() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${BLUE}→${NC} $1"
    fi
}

success() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${GREEN}✓${NC} $1"
    fi
}

error() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${RED}✗${NC} $1"
    fi
}

dry_run_prefix() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] "
    fi
}

# Get all tag names
get_all_tags() {
    echo "$VERSION"
    for module in "${MODULES[@]}"; do
        echo "${module}/${VERSION}"
    done
}

# Create tags
create_tags() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "$(dry_run_prefix)Creating tags for $VERSION on commit $COMMIT_SHORT"
        echo ""
    fi

    local created=0
    local failed=0

    # Main version tag
    info "$(dry_run_prefix)Creating tag: $VERSION"
    if [ "$DRY_RUN" = true ]; then
        success "Would create: $VERSION"
        add_result "$VERSION" "create" "dry_run" "would create"
    else
        if git tag -a "$VERSION" -m "Release $VERSION" "$COMMIT" 2>/dev/null; then
            success "Created: $VERSION"
            add_result "$VERSION" "create" "success" "created"
            created=$((created + 1))
        else
            error "Failed to create: $VERSION (may already exist)"
            add_result "$VERSION" "create" "failed" "may already exist"
            failed=$((failed + 1))
        fi
    fi

    # Module tags
    for module in "${MODULES[@]}"; do
        local tag="${module}/${VERSION}"
        info "$(dry_run_prefix)Creating tag: $tag"
        if [ "$DRY_RUN" = true ]; then
            success "Would create: $tag"
            add_result "$tag" "create" "dry_run" "would create"
        else
            if git tag -a "$tag" -m "Release ${module} $VERSION" "$COMMIT" 2>/dev/null; then
                success "Created: $tag"
                add_result "$tag" "create" "success" "created"
                created=$((created + 1))
            else
                error "Failed to create: $tag (may already exist)"
                add_result "$tag" "create" "failed" "may already exist"
                failed=$((failed + 1))
            fi
        fi
    done

    if [ "$JSON_OUTPUT" = true ]; then
        local status="success"
        [ $failed -gt 0 ] && status="partial"
        output_json "$status" "create"
    else
        echo ""
        if [ "$DRY_RUN" = true ]; then
            echo "Would create $((${#MODULES[@]} + 1)) tags on commit $COMMIT_SHORT"
        else
            echo "Created $created tags on commit $COMMIT_SHORT"
        fi
    fi
}

# Delete tags
delete_tags() {
    local delete_remote="${1:-true}"

    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "$(dry_run_prefix)Deleting tags for $VERSION"
        echo ""
    fi

    # Collect all tags
    local tags=("$VERSION")
    for module in "${MODULES[@]}"; do
        tags+=("${module}/${VERSION}")
    done

    # Delete local tags
    info "$(dry_run_prefix)Deleting local tags..."
    for tag in "${tags[@]}"; do
        if [ "$DRY_RUN" = true ]; then
            if git rev-parse "$tag" >/dev/null 2>&1; then
                success "Would delete local: $tag"
                add_result "$tag" "delete_local" "dry_run" "would delete"
            fi
        else
            if git tag -d "$tag" 2>/dev/null; then
                success "Deleted local: $tag"
                add_result "$tag" "delete_local" "success" "deleted"
            fi
        fi
    done

    # Delete remote tags
    if [ "$delete_remote" = "true" ]; then
        info "$(dry_run_prefix)Deleting remote tags..."
        local remote_refs=()
        for tag in "${tags[@]}"; do
            remote_refs+=(":refs/tags/$tag")
        done

        if [ "$DRY_RUN" = true ]; then
            success "Would delete ${#tags[@]} remote tags"
            for tag in "${tags[@]}"; do
                add_result "$tag" "delete_remote" "dry_run" "would delete"
            done
        else
            local verify_flag=""
            [ "$NO_VERIFY" = true ] && verify_flag="--no-verify"
            if git push origin "${remote_refs[@]}" $verify_flag 2>/dev/null; then
                success "Deleted ${#tags[@]} remote tags"
                for tag in "${tags[@]}"; do
                    add_result "$tag" "delete_remote" "success" "deleted"
                done
            else
                error "Some remote tags may not have existed"
                for tag in "${tags[@]}"; do
                    add_result "$tag" "delete_remote" "warning" "may not have existed"
                done
            fi
        fi
    fi

    if [ "$JSON_OUTPUT" = true ]; then
        output_json "success" "delete"
    else
        echo ""
        if [ "$DRY_RUN" = true ]; then
            echo "Would delete $((${#MODULES[@]} + 1)) tags"
        else
            echo "Deleted $((${#MODULES[@]} + 1)) tags"
        fi
    fi
}

# Recreate tags
recreate_tags() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "$(dry_run_prefix)Recreating tags for $VERSION on commit $COMMIT_SHORT"
    fi

    delete_tags "true"

    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
    fi

    # Reset JSON results for create phase
    JSON_RESULTS=()

    create_tags
}

# List tags
list_tags() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "Tags for $VERSION:"
        echo ""
    fi

    local found=0
    local missing=0

    # Check main tag
    if git rev-parse "$VERSION" >/dev/null 2>&1; then
        local commit=$(git rev-parse "$VERSION")
        if [ "$JSON_OUTPUT" = false ]; then
            echo -e "  ${GREEN}✓${NC} $VERSION -> ${commit:0:8}"
        fi
        add_result "$VERSION" "list" "found" "${commit:0:8}"
        ((found++))
    else
        if [ "$JSON_OUTPUT" = false ]; then
            echo -e "  ${RED}✗${NC} $VERSION (not found)"
        fi
        add_result "$VERSION" "list" "missing" "not found"
        ((missing++))
    fi

    # Check module tags
    for module in "${MODULES[@]}"; do
        local tag="${module}/${VERSION}"
        if git rev-parse "$tag" >/dev/null 2>&1; then
            local commit=$(git rev-parse "$tag")
            if [ "$JSON_OUTPUT" = false ]; then
                echo -e "  ${GREEN}✓${NC} $tag -> ${commit:0:8}"
            fi
            add_result "$tag" "list" "found" "${commit:0:8}"
            ((found++))
        else
            if [ "$JSON_OUTPUT" = false ]; then
                echo -e "  ${RED}✗${NC} $tag (not found)"
            fi
            add_result "$tag" "list" "missing" "not found"
            ((missing++))
        fi
    done

    if [ "$JSON_OUTPUT" = true ]; then
        local status="success"
        [ $missing -gt 0 ] && status="partial"
        [ $found -eq 0 ] && status="not_found"
        output_json "$status" "list"
    else
        echo ""
        echo "Found: $found, Missing: $missing"
    fi
}

# Push tags
push_tags() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "$(dry_run_prefix)Pushing tags for $VERSION"
        echo ""
    fi

    # Check which tags exist locally
    local existing_tags=()
    local missing_tags=()

    if git rev-parse "$VERSION" >/dev/null 2>&1; then
        existing_tags+=("$VERSION")
    else
        missing_tags+=("$VERSION")
    fi

    for module in "${MODULES[@]}"; do
        local tag="${module}/${VERSION}"
        if git rev-parse "$tag" >/dev/null 2>&1; then
            existing_tags+=("$tag")
        else
            missing_tags+=("$tag")
        fi
    done

    # Report missing tags
    for tag in "${missing_tags[@]}"; do
        if [ "$JSON_OUTPUT" = false ]; then
            echo -e "${YELLOW}WARN:${NC} Tag $tag does not exist locally, skipping"
        fi
        add_result "$tag" "push" "skipped" "not found locally"
    done

    if [ ${#existing_tags[@]} -eq 0 ]; then
        if [ "$JSON_OUTPUT" = true ]; then
            output_json "error" "push"
        else
            error "No tags found to push"
        fi
        exit 1
    fi

    # Push all existing tags
    info "$(dry_run_prefix)Pushing ${#existing_tags[@]} tags to origin..."

    if [ "$DRY_RUN" = true ]; then
        success "Would push ${#existing_tags[@]} tags"
        for tag in "${existing_tags[@]}"; do
            add_result "$tag" "push" "dry_run" "would push"
        done
    else
        local verify_flag=""
        [ "$NO_VERIFY" = true ] && verify_flag="--no-verify"
        if git push origin --tags $verify_flag 2>&1; then
            success "Pushed ${#existing_tags[@]} tags"
            for tag in "${existing_tags[@]}"; do
                add_result "$tag" "push" "success" "pushed"
            done
        else
            error "Failed to push some tags"
            for tag in "${existing_tags[@]}"; do
                add_result "$tag" "push" "failed" "push failed"
            done
        fi
    fi

    if [ "$JSON_OUTPUT" = true ]; then
        local status="success"
        [ ${#missing_tags[@]} -gt 0 ] && status="partial"
        output_json "$status" "push"
    else
        echo ""
        if [ "$DRY_RUN" = false ]; then
            echo "To trigger the release workflow:"
            echo "  gh workflow run release.yml --field tag=$VERSION"
        fi
    fi
}

# Main
case "$ACTION" in
    create)
        create_tags
        if [ "$JSON_OUTPUT" = false ] && [ "$DRY_RUN" = false ]; then
            echo ""
            echo "Next steps:"
            echo "  1. Push tags: $0 push $VERSION"
            echo "  2. Trigger release: gh workflow run release.yml --field tag=$VERSION"
        fi
        ;;
    delete)
        delete_tags "true"
        ;;
    recreate)
        recreate_tags
        if [ "$JSON_OUTPUT" = false ] && [ "$DRY_RUN" = false ]; then
            echo ""
            echo "Next steps:"
            echo "  1. Push tags: $0 push $VERSION"
            echo "  2. Trigger release: gh workflow run release.yml --field tag=$VERSION"
        fi
        ;;
    list)
        list_tags
        ;;
    push)
        push_tags
        ;;
    *)
        echo -e "${RED}ERROR:${NC} Unknown action: $ACTION"
        usage
        ;;
esac
