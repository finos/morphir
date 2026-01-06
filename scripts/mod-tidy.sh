#!/usr/bin/env bash
# Run go mod tidy for all modules in the monorepo

set -e

echo "Running go mod tidy for all modules..."

cd "$(dirname "$0")/.." || exit 1

modules=(
    "cmd/morphir"
    "pkg/bindings/wasm-componentmodel"
    "pkg/models"
    "pkg/nbformat"
    "pkg/tooling"
    "pkg/sdk"
    "pkg/pipeline"
)

for module in "${modules[@]}"; do
    echo "Running go mod tidy in $module..."
    (cd "$module" && go mod tidy)
done

echo "All modules tidied successfully!"
