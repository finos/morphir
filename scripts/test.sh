#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/sync-changelog.sh"

echo "Running tests..."
for dir in cmd/morphir pkg/bindings/typemap pkg/bindings/wit pkg/config pkg/docling-doc pkg/models pkg/nbformat pkg/pipeline pkg/sdk pkg/task pkg/tooling pkg/vfs; do
    if [ -d "$dir" ]; then
        echo "Testing $dir..."
        (cd "$dir" && go test ./...)
    fi
done
