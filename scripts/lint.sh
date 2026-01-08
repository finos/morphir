#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/sync-changelog.sh"

echo "Running linters..."
if ! command -v golangci-lint > /dev/null; then
    echo "golangci-lint not found. Install with: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"
    exit 1
fi
for dir in cmd/morphir pkg/bindings/wit pkg/config pkg/docling-doc pkg/models pkg/nbformat pkg/pipeline pkg/task pkg/tooling pkg/sdk pkg/vfs; do
    echo "Linting $dir..."
    (cd "$dir" && golangci-lint run --timeout=5m)
done
