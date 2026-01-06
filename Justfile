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

# Sync CHANGELOG.md to cmd directory for embedding
sync-changelog:
    @echo "Syncing CHANGELOG.md to cmd directory..."
    @cp CHANGELOG.md cmd/morphir/cmd/CHANGELOG.md

# Build the CLI application
build: sync-changelog
    @echo "Building morphir CLI..."
    {{if os() == "windows" { "powershell -c \"if (-not (Test-Path bin)) { New-Item -ItemType Directory -Path bin }\"" } else { "mkdir -p bin" } }}
    {{if os() == "windows" { "go build -o bin/morphir.exe ./cmd/morphir" } else { "go build -o bin/morphir ./cmd/morphir" } }}

# Build the development version of the CLI (morphir-dev)
build-dev: sync-changelog
    @echo "Building morphir-dev CLI..."
    {{if os() == "windows" { "powershell -c \"if (-not (Test-Path bin)) { New-Item -ItemType Directory -Path bin }\"" } else { "mkdir -p bin" } }}
    {{if os() == "windows" { "go build -o bin/morphir-dev.exe ./cmd/morphir" } else { "go build -o bin/morphir-dev ./cmd/morphir" } }}

# Run tests across all modules
test: sync-changelog
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Running tests..."
    for dir in cmd/morphir pkg/models pkg/tooling pkg/sdk pkg/pipeline; do
        if [ -d "$dir" ]; then
            echo "Testing $dir..."
            (cd "$dir" && go test ./...)
        fi
    done

# Run tests with coverage report
test-coverage: sync-changelog
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Running tests with coverage..."

    # Get absolute path to repo root
    REPO_ROOT=$(pwd)

    # Create coverage directory
    mkdir -p "$REPO_ROOT/coverage"

    # Run tests with coverage for each module
    for dir in cmd/morphir pkg/models pkg/tooling pkg/sdk pkg/pipeline; do
        if [ -d "$dir" ]; then
            echo "Testing $dir with coverage..."
            MODULE_NAME=$(basename "$dir")
            (cd "$dir" && go test -coverprofile="$REPO_ROOT/coverage/${MODULE_NAME}.out" -covermode=atomic ./...)
        fi
    done

    # Merge coverage profiles
    echo "Merging coverage profiles..."
    echo "mode: atomic" > coverage.out
    grep -h -v "^mode:" coverage/*.out >> coverage.out || true

    # Display coverage summary
    echo ""
    echo "Coverage Summary:"
    go tool cover -func=coverage.out | tail -1

    echo ""
    echo "Coverage report generated: coverage.out"
    echo "View HTML report: go tool cover -html=coverage.out"

# Run tests with JUnit XML output for CI
test-junit: sync-changelog
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Running tests with JUnit XML output..."

    # Check if gotestsum is installed
    if ! command -v gotestsum >/dev/null 2>&1; then
        echo "Installing gotestsum..."
        go install gotest.tools/gotestsum@latest
    fi

    # Get absolute path to repo root
    REPO_ROOT=$(pwd)

    # Create directories for test results and coverage
    mkdir -p "$REPO_ROOT/test-results" "$REPO_ROOT/coverage"

    # Run tests with JUnit output for each module
    for dir in cmd/morphir pkg/models pkg/tooling pkg/sdk pkg/pipeline; do
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

    # Merge coverage profiles
    echo ""
    echo "Merging coverage profiles..."
    echo "mode: atomic" > coverage.out
    grep -h -v "^mode:" coverage/*.out >> coverage.out || true

    echo ""
    echo "Test results generated in test-results/"
    echo "Coverage profiles generated in coverage/"
    echo "Merged coverage: coverage.out"

# Format all Go code
fmt:
    @echo "Formatting Go code..."
    go fmt ./...

# Check code formatting without modifying files
fmt-check: sync-changelog
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
lint: sync-changelog
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
    {{if os() == "windows" { "powershell -ExecutionPolicy Bypass -File scripts/mod-tidy.ps1" } else { "./scripts/mod-tidy.sh" } }}

# Install the CLI using go install (installs to $GOPATH/bin or $GOBIN)
install:
    @echo "Installing morphir CLI..."
    go install ./cmd/morphir
    @echo "Installed successfully!"

# Install the development version as morphir-dev
install-dev: build-dev
    {{if os() == "windows" { "powershell -ExecutionPolicy Bypass -File scripts/install-dev.ps1" } else { "./scripts/install-dev.sh" } }}

# Run the CLI application
run: build
    {{if os() == "windows" { "./bin/morphir.exe" } else { "./bin/morphir" } }}

# Run the development version of the CLI
run-dev: build-dev
    {{if os() == "windows" { "./bin/morphir-dev.exe" } else { "./bin/morphir-dev" } }}

# Verify all modules build successfully
verify: sync-changelog
    {{if os() == "windows" { "powershell -ExecutionPolicy Bypass -File scripts/verify.ps1" } else { "./scripts/verify.sh" } }}

# Test external consumption (building without go.work)
test-external: sync-changelog
    @echo "Testing external consumption (no go.work)..."
    @echo "This verifies that module versions in go.mod are correct."
    @cd cmd/morphir && go mod download && go build .
    @echo "✅ cmd/morphir builds successfully as external consumer would use it"

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

# Suggest changelog entries from git commits
changelog-suggest:
    @echo "Analyzing commits for changelog..."
    @./scripts/changelog-suggest.sh

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
