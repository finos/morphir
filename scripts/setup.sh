#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -x "$SCRIPT_DIR/dev-setup.sh" ]; then
    "$SCRIPT_DIR/dev-setup.sh"
fi

echo "Setting up development environment..."
echo "1. Installing npm dependencies (for git hooks)..."
if command -v npm > /dev/null; then
    npm install
else
    echo "Warning: npm not found. Git hooks will not be installed."
    echo "Install Node.js from https://nodejs.org/ to enable git hooks."
fi

echo "2. Verifying git hooks are installed..."
if [ -f ".husky/pre-push" ]; then
    echo "   ✓ Git hooks installed successfully"
else
    echo "   ⚠ Git hooks not installed (npm install may have failed)"
fi

echo ""
echo "Development environment setup complete!"
echo "Run 'mise run build-dev' to build the development version."
