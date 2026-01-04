# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Layered Configuration System**: Complete configuration management with multiple sources
  - TOML file support (`morphir.toml`, `.morphir/morphir.toml`)
  - XDG-compliant path resolution for global config (`~/.config/morphir/`)
  - System-wide configuration (`/etc/morphir/morphir.toml`)
  - User override file (`.morphir/morphir.user.toml`, gitignored)
  - Environment variable overrides with `MORPHIR_*` prefix
  - Priority-based merging (env > user > project > global > system > defaults)
- **Workspace Management**: Discovery and initialization of Morphir workspaces
  - `morphir workspace init` command with `--hidden` and `--name` flags
  - Automatic workspace discovery walking up directory tree
  - Standard directory structure (`.morphir/out/`, `.morphir/cache/`)
- **Configuration CLI Commands**:
  - `morphir config show` - Display resolved configuration
  - `morphir config path` - Show configuration file locations and status
  - `--json` flag on all commands for programmatic access
- **Schema Validation**: Configuration validation with errors and warnings
  - Validates log levels, formats, paths, numeric ranges
  - Distinguishes fatal errors from non-fatal warnings
- **New Packages**:
  - `pkg/config` - Public configuration API with immutable types
  - `pkg/tooling/workspace` - Workspace discovery and initialization
- **Documentation**:
  - Comprehensive configuration guide (`docs/configuration.md`)
  - Package documentation (`doc.go` files)
  - Example configurations (`examples/morphir.toml`, `examples/morphir.minimal.toml`)
  - Updated README with Configuration section
- GoReleaser configuration for automated releases
- GitHub Actions CI workflow for format, lint, test, and build checks
- GitHub Actions release workflow for automated releases on tags
- Version information in CLI (`morphir --version`)
- Cross-platform support: Linux, macOS, Windows (amd64, arm64)
- Changelog management following Keep a Changelog format

### Changed
- `morphir workspace init` now fully functional (was stubbed)
- Migrated morphir-go codebase into main morphir repository
- Updated module paths from `github.com/finos/morphir-go` to `github.com/finos/morphir`

## [0.1.0] - 2026-01-01

### Added
- Initial Go monorepo structure with `go.work` workspace
- CLI application built with Cobra and Bubbletea
- Root command that launches interactive TUI
- `workspace init` command (stubbed implementation)
- `validate` command for validating Morphir IR (stubbed implementation)
- Library modules: `models`, `tooling`, `sdk`, `pipeline`
- Build orchestration with Justfile
- Cross-platform scripts directory with bash and PowerShell versions
- OS detection infrastructure for Windows, Linux, macOS support
- Development build targets (`build-dev`, `install-dev`)
- CI check script for running all validation tasks
- AGENTS.md with development guidelines and project principles
- CLI development guidelines for stdout/stderr separation and JSON output support
- Functional programming principles and TDD/BDD practices documentation

### Changed
- Updated to Go 1.25.5
- Refactored Justfile with proper OS detection and readable formatting
- Improved command registration consistency

### Fixed
- Duplicate help command registration in CLI

[Unreleased]: https://github.com/finos/morphir/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/finos/morphir/releases/tag/v0.1.0
