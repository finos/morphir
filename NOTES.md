[![Latest Release](https://img.shields.io/github/v/release/finos/morphir)](https://github.com/finos/morphir/releases/latest)
[![CI](https://github.com/finos/morphir/actions/workflows/ci.yml/badge.svg)](https://github.com/finos/morphir/actions/workflows/ci.yml)
[![Go Report Card](https://goreportcard.com/badge/github.com/finos/morphir)](https://goreportcard.com/report/github.com/finos/morphir)

# Morphir Go

A Go implementation of the Morphir tooling ecosystem. Morphir is a technology-agnostic intermediate representation (IR) for business logic and data models, enabling code generation, documentation, and analysis across multiple target platforms.

This project provides a CLI application built with [Cobra](https://github.com/spf13/cobra) and [Bubbletea](https://github.com/charmbracelet/bubbletea), along with library modules for working with Morphir IR.

## Installation

### Option 1: Download Binary (Recommended)

Download the latest release for your platform from [GitHub Releases](https://github.com/finos/morphir/releases/latest):

- **Linux (amd64/arm64)**: `morphir_X.Y.Z_Linux_{x86_64,arm64}.tar.gz`
- **macOS (amd64/arm64)**: `morphir_X.Y.Z_Darwin_{x86_64,arm64}.tar.gz`  
- **Windows (amd64)**: `morphir_X.Y.Z_Windows_x86_64.zip`

Extract and move to your PATH:

```sh
# Linux/macOS
tar -xzf morphir_*.tar.gz
sudo mv morphir /usr/local/bin/

# Windows (PowerShell)
Expand-Archive morphir_*.zip
Move-Item morphir.exe $env:USERPROFILE\bin\
```

### Option 2: Install via Go

```sh
go install github.com/finos/morphir/cmd/morphir@latest
```

### Option 3: Build from Source

**Prerequisites:**
- **Go 1.25.5** or later ([download](https://golang.org/dl/))
- **mise** - A task runner for build orchestration ([install](https://mise.jdx.dev))
- **PowerShell** (Windows only) - For running build scripts on Windows ([install](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell))

**Build steps:**

```sh
# Clone the repository
git clone https://github.com/finos/morphir.git
cd morphir

# Build the CLI application
mise run build

# The binary will be in bin/morphir
```

**Install to system:**

```sh
# Build and install to $GOPATH/bin or $GOBIN
mise run install
```

### Verify Installation

```sh
morphir --version
```

## Usage

### Running the CLI

```sh
# Launch the interactive TUI
morphir

# Get help
morphir help

# Get help for a specific command
morphir help workspace

# Initialize a new workspace
morphir workspace init [path]

# View configuration
morphir config show

# Show configuration file locations
morphir config path
```

## Configuration

Morphir uses a layered configuration system. Configuration is loaded from multiple sources in priority order, with higher-priority sources overriding lower ones.

### Quick Start

```sh
# Initialize a workspace (creates morphir.toml)
morphir workspace init

# View the resolved configuration
morphir config show

# See which config files are loaded
morphir config path
```

### Configuration Sources

| Priority | Source | Description |
|----------|--------|-------------|
| 6 (highest) | Environment | `MORPHIR_*` variables |
| 5 | User override | `.morphir/morphir.user.toml` (gitignored) |
| 4 | Project | `morphir.toml` or `.morphir/morphir.toml` |
| 3 | Global | `~/.config/morphir/morphir.toml` |
| 2 | System | `/etc/morphir/morphir.toml` |
| 1 (lowest) | Defaults | Built-in defaults |

### Example Configuration

```toml
[morphir]
version = "^3.0.0"

[codegen]
targets = ["go", "typescript"]

[logging]
level = "info"
format = "text"
```

### Environment Variables

Override any setting with `MORPHIR_` prefix:

```sh
export MORPHIR_LOGGING_LEVEL=debug
export MORPHIR_CACHE_ENABLED=false
```

For complete documentation, see [docs/configuration.md](docs/configuration.md).

## Module Structure

This is a Go monorepo with multiple modules:

- **`cmd/morphir/`** - CLI application (Cobra + Bubbletea)
- **`pkg/config/`** - Layered configuration system
- **`pkg/models/`** - Morphir IR model types and data structures
- **`pkg/tooling/`** - Utilities and tools for working with Morphir IR
  - **`pkg/tooling/workspace/`** - Workspace discovery and initialization
- **`pkg/sdk/`** - SDK for building applications that work with Morphir IR
- **`pkg/pipeline/`** - Processing pipelines for Morphir IR transformations

Each package is a separate Go module, managed via `go.work` for seamless development.

## Development Workflow

### Build Orchestration with Mise

We use [`mise`](https://mise.jdx.dev) for build orchestration. Common commands:

```sh
# List all available commands
mise tasks

# Set up development environment (first time setup)
mise run setup

# Build the CLI application
mise run build

# Run tests across all modules
mise run test

# Format all Go code
mise run fmt

# Run linters (requires golangci-lint)
mise run lint

# Download dependencies for all modules
mise run deps

# Run go mod tidy for all modules
mise run mod-tidy

# Clean build artifacts
mise run clean

# Verify all modules build successfully
mise run verify

# Run CI checks (format, build, test, lint)
mise run ci-check
```

### Local Development and Testing

For local development, we recommend using `morphir-dev` to distinguish your development version from any installed `morphir` CLI:

```sh
# Build the development version
mise run build-dev

# The binary will be in bin/morphir-dev

# Run the development version directly
mise run run-dev

# Or run it manually
./bin/morphir-dev

# Test specific commands
./bin/morphir-dev help
./bin/morphir-dev workspace init

# Launch the TUI
./bin/morphir-dev

# Install morphir-dev to your system (makes it available in PATH)
mise run install-dev

# After installation, you can use morphir-dev from anywhere
morphir-dev help
```

**Why use `morphir-dev`?**
- Keeps your development version separate from any installed `morphir` CLI
- Allows you to test changes without affecting your installed version
- Makes it clear which version you're running during development
- Enables side-by-side comparison with the installed version
- Can be installed system-wide for easy access during development

### Development Setup

1. **Clone the repository**
   ```sh
   git clone https://github.com/finos/morphir.git
   cd morphir
   ```

2. **Set up the development environment**
   ```sh
   mise run setup
   ```

   This command will:
   - Sync Go workspace modules
   - Install npm dependencies (for git hooks)
   - Set up pre-push hooks that run formatting, linting, and tests

   **Prerequisites for `mise run setup`:**
   - [Node.js](https://nodejs.org/) (v16+) - for git hooks via Husky
   - [npm](https://www.npmjs.com/) - comes with Node.js

3. **Build the project**
   ```sh
   # For development, use build-dev
   mise run build-dev

   # Or for standard build
   mise run build
   ```

4. **Run tests**
   ```sh
   mise run test
   ```

5. **Test your changes**
   ```sh
   # Build and run the development version
   mise run run-dev

   # Or test specific commands
   ./bin/morphir-dev help
   ```

### Git Hooks

This project uses [Husky](https://typicode.github.io/husky/) for git hooks. After running `mise run setup`, the following hooks are installed:

- **pre-push**: Runs before each push to verify:
  - Go code formatting (`gofmt`)
  - Linting (`golangci-lint` if installed)
  - `go vet` checks
  - All tests pass

If any check fails, the push is aborted. This ensures code quality is maintained before changes reach the remote repository.

**Note:** If you don't have Node.js installed, git hooks won't be enabled, but you can still contribute - CI will catch any issues.

### Go Workspace

This project uses Go workspaces (`go.work`) to manage the multi-module monorepo. The workspace file includes all modules, allowing seamless cross-module development without requiring local replacements.

### Scripts Directory

The `scripts/` directory contains reusable scripts used in build, CI, and development workflows. These scripts are referenced from `mise` tasks and can also be used directly:

- `scripts/mod-tidy.sh` / `scripts/mod-tidy.ps1` - Runs `go mod tidy` for all modules
- `scripts/install-dev.sh` / `scripts/install-dev.ps1` - Installs `morphir-dev` to Go bin directory
- `scripts/verify.sh` / `scripts/verify.ps1` - Verifies all modules build successfully

Task entry points live in `.mise/tasks` and call into these scripts.

**Cross-Platform Support:**
- All scripts have both bash (`.sh`) and PowerShell (`.ps1`) versions
- `mise` automatically detects the platform and uses the appropriate script
- On Windows, PowerShell scripts are used when PowerShell is available
- On Unix-like systems (Linux, macOS), bash scripts are used

Scripts are used in `mise` tasks for complex operations and can be invoked directly when needed.

## Development Principles

This project follows functional programming principles and practices. For detailed guidance on:

- Functional programming patterns
- Test-driven development (TDD)
- Behavior-driven development (BDD)
- Code organization principles
- Morphir design principles

See **[AGENTS.md](AGENTS.md)** for comprehensive development guidelines.

## Roadmap

- [x] Initial monorepo structure
- [x] CLI application with Cobra and Bubbletea
- [x] Basic command structure (help, workspace)
- [x] Cross-platform support (Linux, macOS, Windows)
- [x] Automated releases with GoReleaser
- [ ] Workspace initialization implementation
- [ ] Morphir IR model support
- [ ] Tooling utilities
- [ ] SDK implementation
- [ ] Pipeline processing

## Releasing (for Maintainers)

This project uses [GoReleaser](https://goreleaser.com/) with GitHub Actions for automated releases.

### Release Process

1. **Update CHANGELOG.md**
   ```sh
   # Move [Unreleased] changes to new version section
   # Add release date: ## [X.Y.Z] - YYYY-MM-DD
   # Create new [Unreleased] section
   ```

2. **Commit and tag**
   ```sh
   git add CHANGELOG.md
   git commit -m "chore: prepare release vX.Y.Z"
   git tag -a vX.Y.Z -m "Release X.Y.Z"
   git push origin main
   git push origin vX.Y.Z
   ```

3. **GitHub Actions will automatically:**
   - Build binaries for all platforms (Linux, macOS, Windows)
   - Build for all architectures (amd64, arm64)
   - Generate checksums
   - Create GitHub Release with artifacts
   - Generate release notes from commits

### Local Testing

Before creating a release, test locally:

```sh
# Validate GoReleaser config
mise run goreleaser-check

# Build snapshot (no publish)
mise run release-snapshot

# Full dry-run
mise run release-test
```

### Versioning

This project follows [Semantic Versioning](https://semver.org/):
- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

Use [Conventional Commits](https://www.conventionalcommits.org/) for better changelogs:
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation
- `chore:` - Maintenance
- `feat!:` or `fix!:` - Breaking change

See [AGENTS.md](AGENTS.md#release-process) for detailed release documentation.

## Contributing
For any questions, bugs or feature requests please open an [issue](https://github.com/finos/morphir/issues).

To submit a contribution:
1. Fork it (<https://github.com/finos/morphir/fork>)
2. Create your feature branch (`git checkout -b feature/fooBar`)
3. Read our [contribution guidelines](.github/CONTRIBUTING.md) and [Community Code of Conduct](https://www.finos.org/code-of-conduct)
4. Commit your changes (`git commit -am 'Add some fooBar'`)
5. Push to the branch (`git push origin feature/fooBar`)
6. Create a new Pull Request

_NOTE:_ Commits and pull requests to FINOS repositories will only be accepted from those contributors with an active, executed Individual Contributor License Agreement (ICLA) with FINOS OR who are covered under an existing and active Corporate Contribution License Agreement (CCLA) executed with FINOS. Commits from individuals not covered under an ICLA or CCLA will be flagged and blocked by the FINOS Clabot tool (or [EasyCLA](https://community.finos.org/docs/governance/Software-Projects/easycla)). Please note that some CCLAs require individuals/employees to be explicitly named on the CCLA.

*Need an ICLA? Unsure if you are covered under an existing CCLA? Email [help@finos.org](mailto:help@finos.org)*

## License

Copyright 2022 FINOS

Distributed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0).

SPDX-License-Identifier: [Apache-2.0](https://spdx.org/licenses/Apache-2.0)
