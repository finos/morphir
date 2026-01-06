#!/usr/bin/env bash
set -euo pipefail

echo "Downloading dependencies..."
go work sync
go mod download ./...
