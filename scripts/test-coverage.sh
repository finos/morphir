#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/sync-changelog.sh"

echo "Running tests with coverage..."

REPO_ROOT=$(pwd)
mkdir -p "$REPO_ROOT/coverage"

for dir in cmd/morphir pkg/bindings/wasm-componentmodel pkg/models pkg/tooling pkg/sdk pkg/pipeline; do
    if [ -d "$dir" ]; then
        echo "Testing $dir with coverage..."
        MODULE_NAME=$(basename "$dir")
        (cd "$dir" && go test -coverprofile="$REPO_ROOT/coverage/${MODULE_NAME}.out" -covermode=atomic ./...)
    fi
done

echo "Merging coverage profiles..."
echo "mode: atomic" > coverage.out
grep -h -v "^mode:" coverage/*.out >> coverage.out || true

echo ""
echo "Coverage Summary:"
go tool cover -func=coverage.out | tail -1

echo ""
echo "Coverage report generated: coverage.out"
echo "View HTML report: go tool cover -html=coverage.out"
