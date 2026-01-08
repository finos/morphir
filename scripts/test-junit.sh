#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/sync-changelog.sh"

echo "Running tests with JUnit XML output..."

if ! command -v gotestsum >/dev/null 2>&1; then
    echo "Installing gotestsum..."
    go install gotest.tools/gotestsum@latest
fi

REPO_ROOT=$(pwd)

mkdir -p "$REPO_ROOT/test-results" "$REPO_ROOT/coverage"

for dir in cmd/morphir pkg/bindings/wasm-componentmodel pkg/models pkg/tooling pkg/sdk pkg/pipeline; do
    if [ -d "$dir" ]; then
        echo "Testing $dir..."
        MODULE_NAME=$(basename "$dir")
        (cd "$dir" && gotestsum \
            --junitfile="$REPO_ROOT/test-results/${MODULE_NAME}.xml" \
            --format=testname \
            -- \
            -coverprofile="$REPO_ROOT/coverage/${MODULE_NAME}.out" \
            -covermode=atomic \
            ./...)
    fi
done

echo ""
echo "Merging coverage profiles..."
echo "mode: atomic" > coverage.out
grep -h -v "^mode:" coverage/*.out >> coverage.out || true

echo ""
echo "Test results generated in test-results/"
echo "Coverage profiles generated in coverage/"
echo "Merged coverage: coverage.out"
