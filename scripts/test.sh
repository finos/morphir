#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/sync-changelog.sh"

echo "Checking workspace..."
"$SCRIPT_DIR/workspace-doctor.sh" --fix=replace

echo "Running tests..."
for dir in cmd/morphir pkg/bindings/wasm-componentmodel pkg/models pkg/tooling pkg/sdk pkg/pipeline; do
    if [ -d "$dir" ]; then
        echo "Testing $dir..."
        (cd "$dir" && go test ./...)
    fi
done
