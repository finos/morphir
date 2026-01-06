#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/sync-changelog.sh"

echo "Testing external consumption (no go.work)..."
echo "This verifies that module versions in go.mod are correct."

cd cmd/morphir

go mod download
go build .

echo "✅ cmd/morphir builds successfully as external consumer would use it"
