---
id: morphir-go-preview
title: Morphir Go (Preview)
sidebar_label: Morphir Go Preview
---

# Morphir Go - Developer Preview

:::caution Insider Feature
Morphir Go is currently in **developer preview**. For production use, please use the stable [morphir-elm](installation.md) tools.
:::

Morphir Go is a next-generation implementation of Morphir written in Go, providing a modern CLI and SDK for working with Morphir IR. This preview release allows early adopters to explore the new tooling and provide feedback.

## Why Morphir Go?

- **Single Binary**: No npm or Node.js required - just download and run
- **Fast Performance**: Native binary with minimal startup time
- **Cross-Platform**: Pre-built binaries for Linux, macOS, and Windows
- **Modern CLI**: Interactive TUI, rich formatting, and structured JSON output
- **Developer-Friendly**: Strong typing, comprehensive configuration system

## Installation (Preview)

:::info
These installation methods are for preview/testing purposes. Production workflows should continue using morphir-elm.
:::

### Quick Install Script

The fastest way to try Morphir Go:

#### Linux & macOS

```bash
# Install latest preview version
curl -fsSL https://raw.githubusercontent.com/finos/morphir/main/scripts/install.sh | bash

# Or install a specific version
curl -fsSL https://raw.githubusercontent.com/finos/morphir/main/scripts/install.sh | bash -s v0.3.3
```

#### Windows (PowerShell)

```powershell
# Install latest preview version
iwr https://raw.githubusercontent.com/finos/morphir/main/scripts/install.ps1 -useb | iex

# Or download and run with version
iwr https://raw.githubusercontent.com/finos/morphir/main/scripts/install.ps1 -useb -outfile install.ps1
.\install.ps1 v0.3.3
```

### Using `go install` (For Go Developers)

If you have Go 1.21+ installed:

```bash
go install github.com/finos/morphir/cmd/morphir@latest
```

### Download from GitHub Releases

Download pre-built binaries from [GitHub Releases](https://github.com/finos/morphir/releases).

## Preview Features

### About Command

Get detailed information about your Morphir installation:

```bash
# Version and platform info
morphir about

# View embedded changelog
morphir about --changelog

# JSON output for automation
morphir about --json
```

Example output:

```
Morphir - Functional Data Modeling
═══════════════════════════════════

Version:      0.3.3
Git Commit:   abc123...
Build Date:   2026-01-05
Go Version:   go1.21.5
Platform:     linux/amd64

For more information:
  Website:    https://morphir.finos.org
  Repository: https://github.com/finos/morphir
  Changelog:  morphir about --changelog
```

### Configuration System

TOML-based configuration with multiple source support:

```bash
# Show current configuration
morphir config show

# Show configuration file locations
morphir config path

# JSON output
morphir config show --json
```

Create a `morphir.toml`:

```toml
[workspace]
name = "MyProject"
format = "json"

[project]
source_directory = "./src"

[logging]
level = "info"
format = "text"
```

### Interactive TUI

Modern terminal UI with vim-style navigation (in development):

- Three-panel layout
- Markdown rendering with syntax highlighting
- Keyboard shortcuts (h/j/k/l, gg/G, Ctrl+d/u)

### Validation

```bash
morphir validate path/to/morphir-ir.json

# JSON output for CI/CD
morphir validate path/to/morphir-ir.json --json
```

## Current Status

### ✅ Available Features

- CLI framework and command structure
- Configuration management system
- Workspace initialization and discovery
- IR validation
- About/version commands with rich output
- Cross-platform binary distribution

### 🚧 In Development

- IR parsing and manipulation
- Code generation backends
- Testing framework integration
- Full Morphir SDK implementation

### 📋 Planned

- Full feature parity with morphir-elm
- Additional backends (Go, Rust, etc.)
- Enhanced visualization tools
- Performance optimizations

## Feedback & Contributing

We welcome feedback and contributions!

- **Report Issues**: [GitHub Issues](https://github.com/finos/morphir/issues)
- **Contribute**: See [Contributing Guide](contributing.md)
- **Discussions**: [GitHub Discussions](https://github.com/finos/morphir/discussions)

## Migration Path

:::note Future Plans
When Morphir Go reaches stable 1.0, we plan to provide:
- Migration guides from morphir-elm
- Side-by-side compatibility
- Gradual adoption path
:::

For now, both implementations can coexist:

- **morphir-elm**: Stable, production-ready
- **morphir-go**: Preview, for testing and feedback

## Version History

Preview releases follow semantic versioning:

- **v0.3.x**: Initial preview releases
- **v0.4.x**: Feature additions
- **v1.0.0**: Planned stable release (TBD)

See the [CHANGELOG](https://github.com/finos/morphir/blob/main/CHANGELOG.md) for detailed release notes.

## Troubleshooting

### Installation Issues

If the install script fails:

1. Check your platform is supported (Linux, macOS, Windows on x86_64 or arm64)
2. Verify you have internet connectivity
3. Try downloading the binary manually from [releases](https://github.com/finos/morphir/releases)

### Command Not Found

After installation, you may need to:

**Linux/macOS:**
```bash
export PATH="$PATH:/usr/local/bin"
```

**Windows:**
Restart your terminal for PATH changes to take effect.

### Build from Source

For the latest development version:

```bash
git clone https://github.com/finos/morphir.git
cd morphir
mise run setup
mise run build
```

The binary will be in `./bin/morphir`.

## Testing and Code Coverage

The Morphir Go project includes comprehensive testing infrastructure with code coverage reporting.

### Running Tests Locally

```bash
# Run all tests
mise run test

# Run tests with coverage report
mise run test-coverage

# Run tests with JUnit XML output (for CI integration)
mise run test-junit
```

### Coverage Reports

The `test-coverage` recipe generates:
- **coverage.out**: Combined coverage profile for all modules
- **coverage/**: Individual coverage files per module
- **Coverage summary**: Displayed in terminal after test run

View detailed HTML coverage report:

```bash
go tool cover -html=coverage.out
```

### CI/CD Integration

Pull requests automatically include:
- **Test Results Summary**: GitHub Actions test summary showing pass/fail status for all tests
- **Coverage Report Comment**: Automated PR comment showing coverage changes with emoji indicators:
  - 🌟 Significant improvement (>20%)
  - 🎉 Good improvement (≤20%)
  - 👍 Minor improvement (≤10%)
  - 👎 Minor decrease (≤10%)
  - 💀 Significant decrease (>10%)
- **Codecov Integration**: Historical coverage tracking at [codecov.io](https://codecov.io)

### Writing Tests

Follow Go's standard testing conventions:

```go
// pkg/example/example_test.go
package example

import "testing"

func TestSomething(t *testing.T) {
    result := Something()
    if result != expected {
        t.Errorf("got %v, want %v", result, expected)
    }
}
```

For more on Go testing, see the [official Go testing documentation](https://golang.org/pkg/testing/).

## For Production Use

:::caution Recommended Approach
For production deployments, please continue using the stable [morphir-elm](installation.md) tooling until Morphir Go reaches 1.0 stable release.
:::

Install morphir-elm:

```bash
npm install -g morphir-elm
```

See the [Installation Guide](installation.md) for complete instructions.

## License

Copyright © FINOS - The Fintech Open Source Foundation

Distributed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0).
