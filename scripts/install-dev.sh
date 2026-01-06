#!/usr/bin/env bash
# Install morphir-dev to the Go bin directory

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -x "$SCRIPT_DIR/build-dev.sh" ]; then
    "$SCRIPT_DIR/build-dev.sh"
fi

# Check for binary with or without .exe extension
if [ -f "$REPO_ROOT/bin/morphir-dev.exe" ]; then
    BINARY="$REPO_ROOT/bin/morphir-dev.exe"
    TARGET_NAME="morphir-dev.exe"
elif [ -f "$REPO_ROOT/bin/morphir-dev" ]; then
    BINARY="$REPO_ROOT/bin/morphir-dev"
    TARGET_NAME="morphir-dev"
else
    echo "Error: morphir-dev binary not found"
    echo "Please run 'mise run build-dev' first"
    exit 1
fi

# Get Go environment variables
GOPATH=$(go env GOPATH)
GOBIN=$(go env GOBIN)

# Determine target directory
if [ -n "$GOBIN" ] && [ "$GOBIN" != "" ]; then
    TARGET_DIR="$GOBIN"
else
    TARGET_DIR="$GOPATH/bin"
fi

# Create target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Copy binary
cp "$BINARY" "$TARGET_DIR/$TARGET_NAME"
chmod +x "$TARGET_DIR/$TARGET_NAME"

echo "Installed to $TARGET_DIR/$TARGET_NAME"
