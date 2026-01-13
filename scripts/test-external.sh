#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/sync-changelog.sh"

echo "Testing external consumption..."
echo "This verifies that cmd/morphir builds correctly with all internal modules."

cd "$REPO_ROOT"

# Remove any existing go.work to start clean
rm -f go.work go.work.sum

# Use setup-workspace to create go.work with all modules and handle unpublished ones
echo ""
echo "Setting up workspace with all modules..."
"$SCRIPT_DIR/setup-workspace.sh"

echo ""
echo "Building cmd/morphir..."
cd "$REPO_ROOT/cmd/morphir"
go build .

# Clean up go.work
cd "$REPO_ROOT"
rm -f go.work go.work.sum

echo ""
echo "✅ cmd/morphir builds successfully"
