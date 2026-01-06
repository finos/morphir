#!/usr/bin/env bash
set -euo pipefail

echo "Formatting Go code..."
go fmt ./...
