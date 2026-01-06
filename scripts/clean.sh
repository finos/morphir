#!/usr/bin/env bash
set -euo pipefail

echo "Cleaning build artifacts..."
if [ -d bin ]; then
    rm -rf bin
fi

go clean ./...
