---
order: 5
---
# Quick Start Guide

Get up and running with Morphir Moonbit development in minutes.

## Prerequisites

- **Operating System**: Linux, macOS, or Windows (with WSL recommended)
- **Git**: For cloning the repository

## Setup Steps

### 1. Install mise

Choose your platform:

#### Linux / macOS

```bash
curl https://mise.run | sh
```

Or using a package manager:

```bash
# macOS (Homebrew)
brew install mise

# Linux (cargo)
cargo install mise
```

#### Windows

```powershell
# Using Scoop
scoop install mise

# Using Chocolatey  
choco install mise
```

### 2. Clone the Repository

```bash
git clone https://github.com/finos/morphir-moonbit.git
cd morphir-moonbit
```

### 3. Install Development Tools

mise will automatically install all required tools:

```bash
mise install
```

This installs:
- Moonbit toolchain (latest)
- Bun 1.3.7
- yamllint
- uv (Python package manager)

**Note**: Git hooks are automatically installed when you enter the directory (via mise hooks).

### 4. Verify Installation

```bash
mise doctor
```

Check tool versions:

```bash
moon version
bun --version
yamllint --version
```

## Your First Build

### Format the Code

```bash
mise run format
```

### Run Linting

```bash
mise run lint
```

### Run Tests

```bash
mise run test
```

### Build All Packages

```bash
mise run build
```

This builds for both targets:
- WASI (server/CLI)
- Browser (WASM-GC)

## Common Commands

### Development Workflow

```bash
# Make your changes...

# Format code
mise run format

# Check everything
mise run check

# Run tests
mise run test
```

### Build Specific Targets

```bash
# Build for WASI only
mise run build:wasi

# Build for browser only
mise run build:browser
```

### Clean Build Artifacts

```bash
mise run clean
```

### List All Available Tasks

```bash
mise tasks
```

## Directory Structure

```
morphir-moonbit/
├── pkgs/                      # All packages live here
│   ├── morphir-sdk/          # Standard library
│   ├── morphir-core/         # Core types
│   └── morphir-moonbit-bindings/  # FFI bindings
├── .config/mise/             # Development tooling
└── docs/                     # Documentation
```

## Making Changes

### 1. Create a Branch

```bash
git checkout -b feature/my-feature
```

### 2. Edit Code

All package code is in `pkgs/`:

```bash
# Edit a file
vim pkgs/morphir-sdk/sdk.mbt

# Add tests
vim pkgs/morphir-sdk/sdk_test.mbt
```

### 3. Test Your Changes

```bash
# Format
mise run format

# Check
mise run check

# Run a specific module's tests
moon -C pkgs/morphir-sdk test
```

### 4. Commit and Push

```bash
git add .
git commit -m "Add feature"
git push origin feature/my-feature
```

## Troubleshooting

### mise not found

Ensure mise is in your PATH. Add to your shell config:

```bash
# For bash/zsh
echo 'eval "$(mise activate bash)"' >> ~/.bashrc
# or for zsh
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
```

### Tools not installing

Try:

```bash
mise cache clear
mise install --force
```

### Build errors

Clean and rebuild:

```bash
mise run clean
mise run build
```

### Moonbit version issues

Check you're using the latest:

```bash
moon version
moon upgrade
```

## Next Steps

- Read [CONTRIBUTING_DEV.md](../CONTRIBUTING_DEV.md) for detailed contribution guidelines
- Check [ARCHITECTURE.md](../docs/ARCHITECTURE.md) to understand the project structure
- Review [MISE_TASKS.md](../docs/MISE_TASKS.md) for all available tasks

## Getting Help

- **Issues**: https://github.com/finos/morphir-moonbit/issues
- **Email**: morphir@finos.org
- **Discussions**: GitHub Discussions

## Quick Reference

| Command | Description |
|---------|-------------|
| `mise install` | Install all tools |
| `mise tasks` | List all available tasks |
| `mise run lint` | Run all linting |
| `mise run format` | Format all code |
| `mise run test` | Run all tests |
| `mise run build` | Build all packages |
| `mise run validate` | Run all validations |
| `mise run check` | Run all checks |
| `mise run clean` | Clean build artifacts |

Happy coding! 🚀
