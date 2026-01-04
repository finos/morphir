# Morphir Go - Build Orchestration with Just

# Default recipe
default:
    @just --list

# Internal: Detect OS and return normalized value (windows, linux, darwin, unknown)
_os:
    @./scripts/detect-os.sh

# Internal: Get binary extension based on OS
_bin-ext:
    @OS=`./scripts/detect-os.sh`; \
    if [ "$$OS" = "windows" ]; then \
        echo ".exe"; \
    else \
        echo ""; \
    fi

# Internal: Get script extension based on OS  
_script-ext:
    @OS=`./scripts/detect-os.sh`; \
    if [ "$$OS" = "windows" ]; then \
        echo ".ps1"; \
    else \
        echo ".sh"; \
    fi

# Internal: Get PowerShell command (pwsh or powershell)
_powershell:
    @sh -c ' \
        if command -v pwsh >/dev/null 2>&1; then \
            echo "pwsh"; \
        elif command -v powershell >/dev/null 2>&1; then \
            echo "powershell"; \
        else \
            echo ""; \
        fi'

# Build the CLI application
build:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building morphir CLI..."
    # Determine binary extension based on GOOS (for cross-compilation) or current OS
    EXT=""
    if [ "${GOOS:-}" = "windows" ]; then
        EXT=".exe"
    elif [ "${GOOS:-}" = "" ]; then
        # GOOS not set, detect current OS
        OS=$(./scripts/detect-os.sh)
        if [ "$OS" = "windows" ]; then
            EXT=".exe"
        fi
    fi
    # Create bin directory if it doesn't exist
    mkdir -p bin
    # Build the binary
    go build -o "bin/morphir${EXT}" ./cmd/morphir

# Build the development version of the CLI (morphir-dev)
build-dev:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building morphir-dev CLI..."
    # Determine binary extension based on GOOS or current OS
    EXT=""
    if [ "${GOOS:-}" = "windows" ]; then
        EXT=".exe"
    elif [ "${GOOS:-}" = "" ]; then
        OS=$(./scripts/detect-os.sh)
        if [ "$OS" = "windows" ]; then
            EXT=".exe"
        fi
    fi
    mkdir -p bin
    go build -o "bin/morphir-dev${EXT}" ./cmd/morphir

# Run tests across all modules
test:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Running tests..."
    for dir in cmd/morphir pkg/models pkg/tooling pkg/sdk pkg/pipeline; do
        if [ -d "$dir" ]; then
            echo "Testing $dir..."
            (cd "$dir" && go test ./...)
        fi
    done

# Format all Go code
fmt:
    @echo "Formatting Go code..."
    go fmt ./...

# Check code formatting without modifying files
fmt-check:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Checking code formatting..."
    UNFORMATTED=$(gofmt -s -l .)
    if [ -n "$UNFORMATTED" ]; then
        echo "The following files are not formatted:"
        echo "$UNFORMATTED"
        echo ""
        echo "Run 'just fmt' to fix formatting issues."
        exit 1
    else
        echo "✓ All files are properly formatted"
    fi

# Run linters (requires golangci-lint)
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Running linters..."
    if ! command -v golangci-lint > /dev/null; then
        echo "golangci-lint not found. Install with: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"
        exit 1
    fi
    for dir in cmd/morphir pkg/models pkg/tooling pkg/sdk pkg/pipeline; do
        echo "Linting $dir..."
        (cd "$dir" && golangci-lint run --timeout=5m)
    done

# Clean build artifacts
clean:
    @echo "Cleaning build artifacts..."
    @if [ -d bin ]; then rm -rf bin; fi
    go clean ./...

# Download dependencies for all modules
deps:
    @echo "Downloading dependencies..."
    go work sync
    go mod download ./...

# Run go mod tidy for all modules
mod-tidy:
    #!/usr/bin/env bash
    set -euo pipefail
    OS=$(./scripts/detect-os.sh)
    if [ "$OS" = "windows" ]; then
        if command -v pwsh >/dev/null 2>&1; then
            PS="pwsh"
        else
            PS="powershell"
        fi
        "$PS" -ExecutionPolicy Bypass -File scripts/mod-tidy.ps1
    else
        ./scripts/mod-tidy.sh
    fi

# Install the CLI using go install (installs to $GOPATH/bin or $GOBIN)
install:
    @echo "Installing morphir CLI..."
    go install ./cmd/morphir
    @echo "Installed successfully!"

# Install the development version as morphir-dev
install-dev: build-dev
    #!/usr/bin/env bash
    set -euo pipefail
    OS=$(./scripts/detect-os.sh)
    if [ "$OS" = "windows" ]; then
        if command -v pwsh >/dev/null 2>&1; then
            PS="pwsh"
        else
            PS="powershell"
        fi
        "$PS" -ExecutionPolicy Bypass -File scripts/install-dev.ps1
    else
        ./scripts/install-dev.sh
    fi

# Run the CLI application
run: build
    #!/usr/bin/env bash
    set -euo pipefail
    EXT=""
    OS=$(./scripts/detect-os.sh)
    if [ "$OS" = "windows" ]; then
        EXT=".exe"
    fi
    "./bin/morphir${EXT}"

# Run the development version of the CLI
run-dev: build-dev
    #!/usr/bin/env bash
    set -euo pipefail
    EXT=""
    OS=$(./scripts/detect-os.sh)
    if [ "$OS" = "windows" ]; then
        EXT=".exe"
    fi
    "./bin/morphir-dev${EXT}"

# Verify all modules build successfully
verify:
    #!/usr/bin/env bash
    set -euo pipefail
    OS=$(./scripts/detect-os.sh)
    if [ "$OS" = "windows" ]; then
        if command -v pwsh >/dev/null 2>&1; then
            PS="pwsh"
        else
            PS="powershell"
        fi
        "$PS" -ExecutionPolicy Bypass -File scripts/verify.ps1
    else
        ./scripts/verify.sh
    fi

# Configure Go workspace for local development
dev-setup:
    @echo "Configuring Go workspace..."
    @./scripts/dev-setup.sh

# Set up development environment (install dependencies, git hooks, workspace, etc.)
setup: dev-setup
    @echo "Setting up development environment..."
    @echo "1. Installing npm dependencies (for git hooks)..."
    @if command -v npm > /dev/null; then \
        npm install; \
    else \
        echo "Warning: npm not found. Git hooks will not be installed."; \
        echo "Install Node.js from https://nodejs.org/ to enable git hooks."; \
    fi
    @echo "2. Verifying git hooks are installed..."
    @if [ -f ".husky/pre-push" ]; then \
        echo "   ✓ Git hooks installed successfully"; \
    else \
        echo "   ⚠ Git hooks not installed (npm install may have failed)"; \
    fi
    @echo ""
    @echo "Development environment setup complete!"
    @echo "Run 'just build-dev' to build the development version."

# Run CI checks (format, build, test, lint)
ci-check: fmt-check verify test lint
    @echo "✓ All CI checks passed!"

# Validate GoReleaser configuration
goreleaser-check:
    @echo "Validating GoReleaser configuration..."
    @if command -v goreleaser > /dev/null; then \
        goreleaser check; \
    else \
        echo "goreleaser not found. Install with: go install github.com/goreleaser/goreleaser@latest"; \
        exit 1; \
    fi

# Test release build locally (creates snapshot without publishing)
release-snapshot:
    @echo "Building release snapshot..."
    @if command -v goreleaser > /dev/null; then \
        goreleaser release --snapshot --clean --skip=publish; \
    else \
        echo "goreleaser not found. Install with: go install github.com/goreleaser/goreleaser@latest"; \
        exit 1; \
    fi

# Full dry-run of release (validates everything without publishing)
release-test:
    @echo "Testing release process..."
    @if command -v goreleaser > /dev/null; then \
        goreleaser release --skip=publish --clean; \
    else \
        echo "goreleaser not found. Install with: go install github.com/goreleaser/goreleaser@latest"; \
        exit 1; \
    fi

# Prepare a new release (creates tags for all modules)
# Usage: just release-prepare v0.3.0
release-prepare VERSION:
    @echo "Preparing release {{VERSION}}..."
    @./scripts/release-prep.sh {{VERSION}}

# Complete release process (prepare + push tags)
# Usage: just release v0.3.0
release VERSION:
    @echo "Starting release process for {{VERSION}}..."
    @echo ""
    @echo "This will:"
    @echo "  1. Run all verifications"
    @echo "  2. Create tags for all modules"
    @echo "  3. Push tags to trigger GitHub Actions release"
    @echo ""
    @read -p "Continue? (y/N) " -n 1 -r && echo; \
    if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
        ./scripts/release-prep.sh {{VERSION}} && \
        git push origin --tags && \
        echo "" && \
        echo "✅ Release {{VERSION}} triggered!" && \
        echo "" && \
        echo "Monitor progress at:" && \
        echo "  https://github.com/finos/morphir/actions"; \
    else \
        echo "Release cancelled."; \
    fi

# Note: Actual releases are handled by GitHub Actions on tag push
# To release: git tag -a vX.Y.Z -m "Release X.Y.Z" && git push origin vX.Y.Z
