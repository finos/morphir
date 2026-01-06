#!/usr/bin/env bash
set -euo pipefail

echo "Testing release process..."
if command -v goreleaser > /dev/null; then
    goreleaser release --skip=publish --clean
else
    echo "goreleaser not found. Install with: go install github.com/goreleaser/goreleaser@latest"
    exit 1
fi
