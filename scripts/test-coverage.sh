#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/sync-changelog.sh"

echo "Running tests with coverage..."

mkdir -p "$REPO_ROOT/coverage"

# Dynamically discover all Go modules with tests
discover_testable_modules() {
    find "$REPO_ROOT" -name "go.mod" -type f \
        ! -path "*/vendor/*" \
        ! -path "*/.git/*" \
        ! -path "*/testdata/*" \
        -exec dirname {} \; | \
        while read -r dir; do
            # Check if module has test files
            if find "$dir" -name "*_test.go" -type f | head -1 | grep -q .; then
                echo "${dir#$REPO_ROOT/}"
            fi
        done | sort
}

echo "Discovering Go modules with tests..."
MODULES=($(discover_testable_modules))
echo "Found ${#MODULES[@]} testable modules"
echo ""

for dir in "${MODULES[@]}"; do
    if [ -d "$REPO_ROOT/$dir" ]; then
        echo "Testing $dir with coverage..."
        MODULE_NAME=$(basename "$dir")
        (cd "$REPO_ROOT/$dir" && go test -coverprofile="$REPO_ROOT/coverage/${MODULE_NAME}.out" -covermode=atomic ./...)
    fi
done

echo ""
echo "Merging coverage profiles..."
echo "mode: atomic" > "$REPO_ROOT/coverage.out"
grep -h -v "^mode:" "$REPO_ROOT/coverage/"*.out >> "$REPO_ROOT/coverage.out" 2>/dev/null || true

echo ""
echo "Coverage Summary:"
go tool cover -func="$REPO_ROOT/coverage.out" | tail -1

echo ""
echo "Coverage report generated: coverage.out"
echo "View HTML report: go tool cover -html=coverage.out"
