#!/usr/bin/env bash
# Verify all modules build successfully

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/sync-changelog.sh"

if [ ! -f "$SCRIPT_DIR/../go.work" ]; then
    "$SCRIPT_DIR/setup-workspace.sh"
fi

echo "Verifying all modules build..."

cd "$(dirname "$0")/.." || exit 1

modules=(
    "cmd/morphir"
    "pkg/models"
    "pkg/nbformat"
    "pkg/tooling"
    "pkg/sdk"
    "pkg/pipeline"
)

for module in "${modules[@]}"; do
    echo "Building $module..."
    (cd "$module" && go build ./...)
done

echo "All modules build successfully!"
