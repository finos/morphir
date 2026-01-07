#!/usr/bin/env bash
# Release Preparation Script
# This script prepares the repository for a new release

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION="$1"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 v0.3.0"
    exit 1
fi

# Remove 'v' prefix if present for module versions
MODULE_VERSION="${VERSION#v}"

echo "Preparing release $VERSION..."
echo ""

cd "$PROJECT_ROOT"

# Verify no uncommitted changes (excluding go.work files which are git-ignored)
UNCOMMITTED=$(git status --porcelain | grep -v "go.work" || true)
if [ -n "$UNCOMMITTED" ]; then
    echo "❌ Error: You have uncommitted changes. Please commit or stash them first."
    echo "$UNCOMMITTED"
    exit 1
fi

# Verify on main branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "⚠️  Warning: You are not on the main branch (currently on: $CURRENT_BRANCH)"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Verifying all modules..."
mise run verify

echo ""
echo "Creating release tags for all modules..."
echo ""

# Tag all modules with subdirectory prefixes
MODULES=(
    "pkg/config"
    "pkg/models"
    "pkg/nbformat"
    "pkg/pipeline"
    "pkg/sdk"
    "pkg/tooling"
    "cmd/morphir"
)

for module in "${MODULES[@]}"; do
    tag="$module/$VERSION"
    echo "  Creating tag: $tag"
    git tag -a "$tag" -m "Release $VERSION - $module"
done

# Also create a main version tag for the repository
echo "  Creating tag: $VERSION"
git tag -a "$VERSION" -m "Release $VERSION"

echo ""
echo "✅ Release tags created successfully!"
echo ""
echo "To push the tags and trigger the release, run:"
echo "  git push origin --tags"
echo ""
echo "This will:"
echo "  1. Push all module tags ($VERSION for each module)"
echo "  2. Trigger the GoReleaser workflow"
echo "  3. Create GitHub release with binaries"
echo "  4. Enable 'go install github.com/finos/morphir/cmd/morphir@$VERSION'"
echo ""
