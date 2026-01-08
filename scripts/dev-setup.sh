#!/usr/bin/env bash
# Development Environment Setup Script
# This script configures your local Go workspace for development

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -x "$SCRIPT_DIR/link-skills.sh" ]; then
    "$SCRIPT_DIR/link-skills.sh" || true
fi

echo "Setting up Go workspace for local development..."

cd "$PROJECT_ROOT"

# Initialize Go workspace
if [ -f "go.work" ]; then
    echo "✓ go.work already exists"
else
    echo "Creating go.work..."
    go work init \
        ./cmd/morphir \
        ./pkg/bindings/wasm-componentmodel \
        ./pkg/config \
        ./pkg/models \
        ./pkg/pipeline \
        ./pkg/sdk \
        ./pkg/tooling \
        ./tests/bdd
    echo "✓ Created go.work"
fi

# Sync workspace (ignore errors if modules aren't tagged yet)
echo "Syncing workspace..."
if go work sync 2>/dev/null; then
    echo "✓ Workspace synced successfully"
else
    echo "⚠ Workspace sync failed (this is normal if modules aren't tagged yet)"
    echo "  The workspace will work for local development anyway"
fi

echo ""
echo "✅ Development environment ready!"
echo ""
echo "The go.work file enables you to make changes across modules locally"
echo "without needing replace directives or version tags."
echo ""
echo "Note: If you see 'unknown revision' errors, that's expected until"
echo "      modules are tagged. Local development will still work."
echo ""
echo "To verify your setup, run:"
echo "  mise run verify"
echo ""
