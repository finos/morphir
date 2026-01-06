#!/usr/bin/env bash
# Morphir Release Automation Script
# Handles the complete release process with pre-flight checks and post-release verification

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if version is provided
if [ $# -eq 0 ]; then
    log_error "Usage: $0 <version>"
    log_info "Example: $0 v0.3.2"
    exit 1
fi

VERSION=$1

# Remove 'v' prefix if present for display
VERSION_NUMBER=${VERSION#v}

log_info "Starting release process for version ${VERSION}"
echo ""

#
# Phase 1: Pre-Flight Checks
#
log_info "Phase 1: Running pre-flight checks..."
echo ""

# Check 1: Verify on main branch
log_info "Checking git branch..."
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    log_error "Must be on main branch (current: $CURRENT_BRANCH)"
    log_info "Run: git checkout main && git pull origin main"
    exit 1
fi
log_success "On main branch"

# Check 2: Verify main is up to date
log_info "Checking if main is up to date..."
git fetch origin main --quiet
LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse @{u})
if [ "$LOCAL" != "$REMOTE" ]; then
    log_error "Main branch is not up to date with origin"
    log_info "Run: git pull origin main"
    exit 1
fi
log_success "Main is up to date"

# Check 3: Verify no uncommitted changes (excluding go.work files which are git-ignored)
log_info "Checking for uncommitted changes..."
UNCOMMITTED=$(git status --porcelain | grep -v "go.work" || true)
if [ -n "$UNCOMMITTED" ]; then
    log_error "Uncommitted changes detected:"
    echo "$UNCOMMITTED"
    log_info "Commit or stash changes before releasing"
    exit 1
fi
log_success "No uncommitted changes"

# Check 4: Verify no replace directives
log_info "Checking for replace directives..."
if grep -r "^replace " --include="go.mod" . > /dev/null 2>&1; then
    log_error "Replace directives found in go.mod files!"
    grep -r "^replace " --include="go.mod" .
    log_info "Remove them with: bash ./scripts/remove-replace-directives.sh"
    exit 1
fi
log_success "No replace directives found"

# Check 5: Verify all modules build
log_info "Verifying all modules build..."
if ! mise run verify > /dev/null 2>&1; then
    log_error "Build failed!"
    log_info "Run: mise run verify"
    exit 1
fi
log_success "All modules build successfully"

# Check 6: Run tests
log_info "Running tests..."
if ! mise run test > /dev/null 2>&1; then
    log_error "Tests failed!"
    log_info "Run: mise run test"
    exit 1
fi
log_success "All tests pass"

# Check 7: Verify CI passed on main
log_info "Checking CI status on main..."
CI_STATUS=$(gh run list --branch=main --limit=1 --json conclusion,status -q '.[0]')
CI_CONCLUSION=$(echo "$CI_STATUS" | jq -r '.conclusion')
CI_RUN_STATUS=$(echo "$CI_STATUS" | jq -r '.status')

if [ "$CI_RUN_STATUS" = "in_progress" ] || [ "$CI_RUN_STATUS" = "queued" ]; then
    log_warning "CI is currently $CI_RUN_STATUS on main"
    log_info "Waiting for CI to complete (timeout: 10 minutes)..."

    TIMEOUT=600  # 10 minutes
    ELAPSED=0
    POLL_INTERVAL=30

    while [ $ELAPSED -lt $TIMEOUT ]; do
        sleep $POLL_INTERVAL
        ELAPSED=$((ELAPSED + POLL_INTERVAL))

        CI_STATUS=$(gh run list --branch=main --limit=1 --json conclusion,status -q '.[0]')
        CI_CONCLUSION=$(echo "$CI_STATUS" | jq -r '.conclusion')
        CI_RUN_STATUS=$(echo "$CI_STATUS" | jq -r '.status')

        if [ "$CI_RUN_STATUS" != "in_progress" ] && [ "$CI_RUN_STATUS" != "queued" ]; then
            break
        fi

        log_info "Still waiting... ($ELAPSED/${TIMEOUT}s elapsed)"
    done

    if [ $ELAPSED -ge $TIMEOUT ]; then
        log_error "CI did not complete within timeout"
        log_info "Check: gh run list --branch=main --limit=5"
        exit 1
    fi
fi

if [ "$CI_CONCLUSION" != "success" ]; then
    log_warning "Latest CI run on main: $CI_CONCLUSION"
    log_info "Check: gh run list --branch=main --limit=5"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    log_success "CI passed on main"
fi

echo ""
log_success "All pre-flight checks passed!"
echo ""

#
# Phase 2: Create and Push Tags
#
log_info "Phase 2: Creating and pushing tags..."
echo ""

# Check if tags already exist
log_info "Checking for existing tags..."
if git tag -l "$VERSION" | grep -q "$VERSION"; then
    log_warning "Tag $VERSION already exists locally"
    read -p "Delete and recreate? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deleting local tags..."
        git tag -d "$VERSION" 2>/dev/null || true
        for module in pkg/bindings/wasm-componentmodel pkg/config pkg/docling-doc pkg/models pkg/pipeline pkg/sdk pkg/tooling cmd/morphir; do
            git tag -d "$module/$VERSION" 2>/dev/null || true
        done

        log_info "Deleting remote tags..."
        git push origin ":refs/tags/$VERSION" 2>/dev/null || true
        for module in pkg/bindings/wasm-componentmodel pkg/config pkg/docling-doc pkg/models pkg/pipeline pkg/sdk pkg/tooling cmd/morphir; do
            git push origin ":refs/tags/$module/$VERSION" 2>/dev/null || true
        done
    else
        log_info "Skipping tag creation"
        exit 0
    fi
fi

# Create tags
log_info "Creating release tags for $VERSION..."
bash "$SCRIPT_DIR/release-prep.sh" "$VERSION"

# Verify tags
log_info "Verifying tags point to current commit..."
CURRENT_COMMIT=$(git rev-parse HEAD)
TAG_COMMIT=$(git rev-parse "$VERSION^{commit}")
if [ "$CURRENT_COMMIT" != "$TAG_COMMIT" ]; then
    log_error "Tag $VERSION does not point to current commit!"
    log_info "Current: $CURRENT_COMMIT"
    log_info "Tag:     $TAG_COMMIT"
    exit 1
fi
log_success "Tags point to correct commit"

# Push tags
log_info "Pushing tags to origin..."
if ! git push --no-verify origin --tags; then
    log_error "Failed to push tags!"
    exit 1
fi
log_success "Tags pushed to origin"

echo ""
log_success "Tags created and pushed successfully!"
echo ""

#
# Phase 3: Trigger Release Workflow
#
log_info "Phase 3: Triggering release workflow..."
echo ""

# Manually trigger workflow (automatic trigger often doesn't work for re-pushed tags)
log_info "Manually triggering release workflow..."
if ! gh workflow run release.yml --ref "$VERSION" -f tag="$VERSION"; then
    log_error "Failed to trigger workflow!"
    log_info "Trigger manually: gh workflow run release.yml --ref $VERSION -f tag=$VERSION"
    exit 1
fi
log_success "Release workflow triggered"

# Wait for workflow to start
log_info "Waiting for workflow to start..."
sleep 10

# Get latest workflow run
WORKFLOW_ID=$(gh run list --workflow=release.yml --limit=1 --json databaseId -q '.[0].databaseId')
if [ -z "$WORKFLOW_ID" ]; then
    log_error "Could not find workflow run!"
    log_info "Check: gh run list --workflow=release.yml --limit=5"
    exit 1
fi

log_info "Monitoring workflow run $WORKFLOW_ID..."
log_info "View in browser: gh run view $WORKFLOW_ID --web"
echo ""

# Watch workflow (this will stream output)
if gh run watch "$WORKFLOW_ID" --exit-status; then
    log_success "Release workflow completed successfully!"
else
    log_error "Release workflow failed!"
    log_info "View logs: gh run view $WORKFLOW_ID --log-failed"
    exit 1
fi

echo ""
log_success "Release workflow completed!"
echo ""

#
# Phase 4: Post-Release Verification
#
log_info "Phase 4: Running post-release verification..."
echo ""

# Wait for Go module proxy to update
log_info "Waiting for Go module proxy to update (30 seconds)..."
sleep 30

# Verify GitHub release
log_info "Verifying GitHub release..."
if ! gh release view "$VERSION" > /dev/null 2>&1; then
    log_error "GitHub release $VERSION not found!"
    log_info "Check: gh release list"
    exit 1
fi
log_success "GitHub release exists"

# Verify binaries
log_info "Verifying release binaries..."
ASSET_COUNT=$(gh release view "$VERSION" --json assets -q '.assets | length')
if [ "$ASSET_COUNT" -lt 5 ]; then
    log_warning "Expected at least 5 assets, found $ASSET_COUNT"
    gh release view "$VERSION" --json assets -q '.assets[].name'
else
    log_success "Found $ASSET_COUNT release assets"
fi

# Verify modules are published
log_info "Verifying Go modules are published..."
MODULES=(
    "github.com/finos/morphir/pkg/bindings/wasm-componentmodel"
    "github.com/finos/morphir/pkg/config"
    "github.com/finos/morphir/pkg/docling-doc"
    "github.com/finos/morphir/pkg/models"
    "github.com/finos/morphir/pkg/pipeline"
    "github.com/finos/morphir/pkg/sdk"
    "github.com/finos/morphir/pkg/tooling"
    "github.com/finos/morphir/cmd/morphir"
)

MODULE_ERRORS=0
for module in "${MODULES[@]}"; do
    if go list -m "$module@$VERSION" > /dev/null 2>&1; then
        log_success "$module@$VERSION"
    else
        log_error "$module@$VERSION not found"
        MODULE_ERRORS=$((MODULE_ERRORS + 1))
    fi
done

if [ $MODULE_ERRORS -gt 0 ]; then
    log_warning "$MODULE_ERRORS modules not yet available"
    log_info "Modules may take a few minutes to appear in the Go module proxy"
    log_info "Retry: go list -m github.com/finos/morphir/cmd/morphir@$VERSION"
fi

# Test go install
log_info "Testing go install..."
if go install "github.com/finos/morphir/cmd/morphir@$VERSION" 2>&1 | grep -q "replace directives"; then
    log_error "go install failed with replace directive error!"
    log_info "This should NOT happen in v0.3.2+. Please investigate!"
    exit 1
elif go install "github.com/finos/morphir/cmd/morphir@$VERSION"; then
    log_success "go install succeeded"

    # Verify installed version
    if command -v morphir > /dev/null 2>&1; then
        INSTALLED_VERSION=$(morphir --version 2>&1 | grep -o 'v[0-9.]*' | head -1)
        if [ "$INSTALLED_VERSION" = "v$VERSION_NUMBER" ] || [ "$INSTALLED_VERSION" = "$VERSION" ]; then
            log_success "Verified installed version: $INSTALLED_VERSION"
        else
            log_warning "Installed version mismatch: expected $VERSION, got $INSTALLED_VERSION"
        fi
    fi
else
    log_warning "go install failed (modules may not be available yet)"
    log_info "Retry in a few minutes: go install github.com/finos/morphir/cmd/morphir@$VERSION"
fi

echo ""
log_success "======================================"
log_success "  Release $VERSION Complete!"
log_success "======================================"
echo ""
log_info "Release URL: https://github.com/finos/morphir/releases/tag/$VERSION"
log_info "Install: go install github.com/finos/morphir/cmd/morphir@$VERSION"
echo ""

# Summary
log_info "Summary:"
echo "  • Release: $VERSION"
echo "  • Commit: $CURRENT_COMMIT"
echo "  • Assets: $ASSET_COUNT binaries"
echo "  • Modules: $((6 - MODULE_ERRORS))/6 published"
echo ""

if [ $MODULE_ERRORS -gt 0 ]; then
    log_warning "Some modules not yet available. They should appear within 5-10 minutes."
    log_info "Monitor: https://pkg.go.dev/github.com/finos/morphir"
fi

log_success "All done! 🎉"
