#!/usr/bin/env bash
# Verify all modules build successfully

set -e

echo "Verifying all modules build..."

cd "$(dirname "$0")/.." || exit 1

modules=(
    "cmd/morphir"
    "pkg/models"
    "pkg/tooling"
    "pkg/sdk"
    "pkg/pipeline"
)

for module in "${modules[@]}"; do
    echo "Building $module..."
    go build "./$module"
done

echo "All modules build successfully!"
