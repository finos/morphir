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
    @echo "Building morphir CLI..."
    @OS=`./scripts/detect-os.sh`; \
    EXT=""; \
    if [ "$$OS" = "windows" ]; then \
        EXT=".exe"; \
    fi; \
    go build -o bin/morphir$$EXT ./cmd/morphir

# Build the development version of the CLI (morphir-dev)
build-dev:
    @echo "Building morphir-dev CLI..."
    @OS=`./scripts/detect-os.sh`; \
    EXT=""; \
    if [ "$$OS" = "windows" ]; then \
        EXT=".exe"; \
    fi; \
    go build -o bin/morphir-dev$$EXT ./cmd/morphir

# Run tests across all modules
test:
    @echo "Running tests..."
    @for dir in cmd/morphir pkg/models pkg/tooling pkg/sdk pkg/pipeline; do \
        if [ -d "$$dir" ]; then \
            echo "Testing $$dir..."; \
            (cd "$$dir" && go test ./...); \
        fi \
    done

# Format all Go code
fmt:
    @echo "Formatting Go code..."
    go fmt ./...

# Run linters (requires golangci-lint)
lint:
    @echo "Running linters..."
    @if command -v golangci-lint > /dev/null; then \
        golangci-lint run; \
    else \
        echo "golangci-lint not found. Install with: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"; \
    fi

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
    @OS=`./scripts/detect-os.sh`; \
    if [ "$$OS" = "windows" ]; then \
        if command -v pwsh >/dev/null 2>&1; then \
            PS="pwsh"; \
        else \
            PS="powershell"; \
        fi; \
        $$PS -ExecutionPolicy Bypass -File scripts/mod-tidy.ps1; \
    else \
        ./scripts/mod-tidy.sh; \
    fi

# Install the CLI using go install (installs to $GOPATH/bin or $GOBIN)
install:
    @echo "Installing morphir CLI..."
    go install ./cmd/morphir
    @echo "Installed successfully!"

# Install the development version as morphir-dev
install-dev: build-dev
    @OS=`./scripts/detect-os.sh`; \
    if [ "$$OS" = "windows" ]; then \
        if command -v pwsh >/dev/null 2>&1; then \
            PS="pwsh"; \
        else \
            PS="powershell"; \
        fi; \
        $$PS -ExecutionPolicy Bypass -File scripts/install-dev.ps1; \
    else \
        ./scripts/install-dev.sh; \
    fi

# Run the CLI application
run: build
    @OS=`./scripts/detect-os.sh`; \
    EXT=""; \
    if [ "$$OS" = "windows" ]; then \
        EXT=".exe"; \
    fi; \
    ./bin/morphir$$EXT

# Run the development version of the CLI
run-dev: build-dev
    @OS=`./scripts/detect-os.sh`; \
    EXT=""; \
    if [ "$$OS" = "windows" ]; then \
        EXT=".exe"; \
    fi; \
    ./bin/morphir-dev$$EXT

# Verify all modules build successfully
verify:
    @OS=`./scripts/detect-os.sh`; \
    if [ "$$OS" = "windows" ]; then \
        if command -v pwsh >/dev/null 2>&1; then \
            PS="pwsh"; \
        else \
            PS="powershell"; \
        fi; \
        $$PS -ExecutionPolicy Bypass -File scripts/verify.ps1; \
    else \
        ./scripts/verify.sh; \
    fi

# Set up development environment (install dependencies, git hooks, etc.)
setup:
    @echo "Setting up development environment..."
    @echo "1. Syncing Go modules..."
    @go work sync
    @echo "2. Installing npm dependencies (for git hooks)..."
    @if command -v npm > /dev/null; then \
        npm install; \
    else \
        echo "Warning: npm not found. Git hooks will not be installed."; \
        echo "Install Node.js from https://nodejs.org/ to enable git hooks."; \
    fi
    @echo "3. Verifying git hooks are installed..."
    @if [ -f ".husky/pre-push" ]; then \
        echo "   ✓ Git hooks installed successfully"; \
    else \
        echo "   ⚠ Git hooks not installed (npm install may have failed)"; \
    fi
    @echo ""
    @echo "Development environment setup complete!"
    @echo "Run 'just build-dev' to build the development version."

# Run CI checks (format, build, test, lint)
ci-check:
    @OS=`./scripts/detect-os.sh`; \
    if [ "$$OS" = "windows" ]; then \
        if command -v pwsh >/dev/null 2>&1; then \
            PS="pwsh"; \
        else \
            PS="powershell"; \
        fi; \
        $$PS -ExecutionPolicy Bypass -File scripts/ci-check.ps1; \
    else \
        ./scripts/ci-check.sh; \
    fi

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

# Note: Actual releases are handled by GitHub Actions on tag push
# To release: git tag -a vX.Y.Z -m "Release X.Y.Z" && git push origin vX.Y.Z
