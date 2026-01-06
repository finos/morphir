#!/usr/bin/env bash
set -euo pipefail

echo "Validating GoReleaser configuration..."
if command -v goreleaser > /dev/null; then
    goreleaser check
else
    echo "goreleaser not found. Install with: go install github.com/goreleaser/goreleaser@latest"
    exit 1
fi
