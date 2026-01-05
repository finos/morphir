# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-01-04

### Added
- **Interactive TUI Framework**: Full-featured terminal UI with vim-style navigation
  - Modern terminal interface using Bubbletea and Lipgloss
  - Vim-style keybindings (h/j/k/l navigation, gg/G, Ctrl+d/u)
  - Three-panel layout: sidebar, content viewer, and status bar
  - Markdown rendering support with syntax highlighting
  - Collapsible sections and tree navigation
  - Demo application showcasing TUI capabilities
- **Markdown Rendering**: Rich markdown support in terminal
  - Headings, lists, code blocks with syntax highlighting
  - Links, emphasis (bold, italic), blockquotes
  - Horizontal rules and inline code
  - Configurable color themes
- **Enhanced Validation**: Improved `morphir validate` command
  - Better error reporting and diagnostics
  - JSON output support for programmatic use
  - Validation of Morphir IR structure
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
  - `pkg/tooling/markdown` - Markdown rendering for terminal output
  - `cmd/morphir/internal/tui` - Reusable TUI framework components
- **Documentation**:
  - Comprehensive configuration guide (`docs/configuration.md`)
  - TUI framework documentation and examples
  - Package documentation (`doc.go` files)
  - Example configurations (`examples/morphir.toml`, `examples/morphir.minimal.toml`)
  - Updated README with Configuration section
  - New DEVELOPING.md and INSTALLING.md guides
- **Release Infrastructure**:
  - GoReleaser configuration for automated releases
  - GitHub Actions CI workflow for format, lint, test, and build checks
  - GitHub Actions release workflow for automated releases on tags
  - Release preparation scripts with multi-module tagging support
  - `go install` support with proper module structure
- **Development Tools**:
  - Installation scripts for Linux/macOS and Windows (PowerShell)
  - Development setup scripts
  - Changelog suggestion script
  - Enhanced Justfile with new development targets

### Changed
- `morphir workspace init` now fully functional (was stubbed)
- Migrated morphir-go codebase into main morphir repository
- Updated module paths from `github.com/finos/morphir-go` to `github.com/finos/morphir`
- Enhanced build system with workspace-based development support
- Improved CLI architecture for better extensibility

### Fixed
- Module path resolution for `go install` compatibility
- Replace directives handling in multi-module workspace

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

[Unreleased]: https://github.com/finos/morphir/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/finos/morphir/compare/v0.2.1...v0.3.0
[0.1.0]: https://github.com/finos/morphir/releases/tag/v0.1.0
