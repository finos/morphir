#!/usr/bin/env bash
# Remove Replace Directives Script
# Safeguard to ensure replace directives are removed before releases
# This is called by GoReleaser as a pre-build hook

set -e

# Find project root (this script is in .config/mise/scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "Checking for replace directives in go.mod files..."

cd "$PROJECT_ROOT"

# Find all go.mod files
GO_MOD_FILES=$(find . -name "go.mod" -type f | grep -v node_modules | grep -v vendor)

FOUND_REPLACE=false

for gomod in $GO_MOD_FILES; do
    if grep -q "^replace " "$gomod"; then
        echo "Warning: Found replace directives in: $gomod"
        FOUND_REPLACE=true

        # Remove replace directives for morphir modules
        MODULE_DIR=$(dirname "$gomod")
        cd "$MODULE_DIR"

        # Remove all morphir-related replace directives
        go mod edit \
            -dropreplace=github.com/finos/morphir/pkg/config \
            -dropreplace=github.com/finos/morphir/pkg/models \
            -dropreplace=github.com/finos/morphir/pkg/pipeline \
            -dropreplace=github.com/finos/morphir/pkg/sdk \
            -dropreplace=github.com/finos/morphir/pkg/tooling \
            -dropreplace=github.com/finos/morphir/tests/bdd 2>/dev/null || true

        echo "  Removed replace directives from $gomod"
        cd "$PROJECT_ROOT"
    fi
done

if [ "$FOUND_REPLACE" = true ]; then
    echo ""
    echo "Replace directives have been removed"
    echo "This is a safeguard to ensure go install compatibility"
else
    echo "No replace directives found - repository is ready for release"
fi

echo ""
