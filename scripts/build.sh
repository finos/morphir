#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/sync-changelog.sh"

echo "Checking workspace..."
"$SCRIPT_DIR/workspace-doctor.sh" --fix=replace

mkdir -p bin
go build -o bin/morphir ./cmd/morphir
