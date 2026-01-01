#!/usr/bin/env bash
# CI check script - runs all checks that should pass in CI

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT" || exit 1

echo "Running CI checks..."

# Format check
echo "Checking code formatting..."
if ! go fmt ./... | grep -q .; then
    echo "✓ Code is properly formatted"
else
    echo "✗ Code formatting issues found. Run 'just fmt' to fix."
    exit 1
fi

# Build verification
echo "Verifying all modules build..."
"$SCRIPT_DIR/verify.sh"

# Run tests
echo "Running tests..."
for dir in cmd/morphir pkg/models pkg/tooling pkg/sdk pkg/pipeline; do
    if [ -d "$dir" ]; then
        echo "Testing $dir..."
        (cd "$dir" && go test ./...)
    fi
done

# Lint check (if available)
if command -v golangci-lint > /dev/null; then
    echo "Running linters..."
    golangci-lint run
    echo "✓ Linting passed"
else
    echo "⚠ golangci-lint not found, skipping lint check"
fi

echo "✓ All CI checks passed!"
