#!/usr/bin/env bash
set -euo pipefail

echo "Building release snapshot..."
if command -v goreleaser > /dev/null; then
    goreleaser release --snapshot --clean --skip=publish
else
    echo "goreleaser not found. Install with: go install github.com/goreleaser/goreleaser@latest"
    exit 1
fi
