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

# Initialize Go workspace using dynamic discovery
if [ -x "$SCRIPT_DIR/setup-workspace.sh" ]; then
    "$SCRIPT_DIR/setup-workspace.sh"
else
    echo "❌ Missing setup-workspace.sh; cannot configure go.work automatically"
    exit 1
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
