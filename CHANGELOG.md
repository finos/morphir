# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0-alpha.2] - 2026-01-13

### Added
- **Decoration System**: New decoration infrastructure for metadata enrichment
  - `morphir decorate` CLI command for applying decorations
  - Type registry for decoration types with validation
  - BDD tests for decoration workflows
- **Toolchain Integration Phase 2**: Major expansion of toolchain adapters
  - **Go Toolchain Adapter**: Complete Go code generation support (#529)
    - `morphir golang make` command to generate Go modules from IR
    - `morphir golang build` command for full IR→Go pipeline
    - IR to Go module/workspace generator (#515)
    - Comprehensive tests and fixtures (#524)
  - **WIT Toolchain Adapter**: WebAssembly Interface Types Phase 2 (#526)
  - **morphir-elm Integration**: NPX backend for morphir-elm tooling (#530)
    - Integration tests validating morphir-elm interoperability (#534)
  - **Toolchain Enablement Design**: Framework for toolchain discovery and enablement (#538)
- **Workflow Planning System**: New workflow orchestration capabilities (#533)
  - Workflow plans with dependency resolution
  - Workspace doctor command for environment validation (#531)
- **Website Improvements**:
  - Upgrade Docusaurus from 2.4.3 to 3.9.2 (#523)
  - Contributing companies panel (#514)
  - Restructured documentation hierarchy for newcomers (#379)

### Fixed
- Decorations CI issues (#541)
- Docusaurus config for morphir.finos.org deployment (#517)

### Changed
- Updated lipgloss dependency to v2 (#512)
- Updated npm to v19 (#444)
- Updated TypeScript to ~5.9.0 (#525)
- Updated doublestar to v4.9.2 (#490)

### Infrastructure
- Added golangci-lint to mise tools
- Comprehensive documentation improvements and tooling (#527)
- Security dependency updates for website

## [0.4.0-alpha.1] - 2026-01-08

### Added
- **WIT Pipeline** (CLI Preview): WebAssembly Interface Types support for Morphir
  - `morphir wit make` command to compile WIT files to Morphir IR
  - `morphir wit gen` command to generate WIT from Morphir IR
  - `morphir wit build` command for full WIT→IR→WIT pipeline
  - JSONL batch processing mode for streaming/CI workflows (`--jsonl` flag)
  - Type mapping infrastructure with diagnostics for lossy transformations
  - WIT parser adapter and emitter with round-trip support
  - BDD tests with scenario outlines for comprehensive coverage
- **Virtual File System (VFS)**: New `pkg/vfs` module for filesystem abstraction
  - Core VFS implementation with virtual paths (`VPath`)
  - Traversal helpers for entry tree manipulation
  - Shadowing support for overlaying file systems
  - Sandbox policy hooks for write operations
  - Path manipulation helpers
- **Task Execution Engine**: New `pkg/task` module for build orchestration
  - Task/target execution with dependency tracking
  - Pipeline integration for task configuration
  - `morphir task list` command to display configured tasks
- **Pipeline Enhancements**: Major improvements to `pkg/pipeline`
  - Core pipeline types and composition framework
  - Validation step with improved diagnostics
  - Comprehensive unit tests for composition and error handling
- **Document Processing**: New `pkg/docling-doc` module
  - Functional document processing with efficient builder pattern
  - BDD tests integrated into release process
- **Jupyter Notebook Support**: New `pkg/nbformat` module
  - Support for reading and processing `.ipynb` files
- **IR Visitor Framework**: New visitor pattern for Morphir IR
  - Type and Pattern traversal helpers
  - Extensible visitor infrastructure
- **Type Mapping Infrastructure**: New `pkg/bindings/typemap` module
  - Registry for bidirectional type mappings
  - Support for multiple binding targets (WIT, Protocol Buffers, etc.)

### Changed
- Migrated task runner from Justfile to `mise` tasks across scripts, docs, and CI
- Removed outdated morphir-elm subtree and related Elm code
- Upgraded Docusaurus from 2.0.0-beta.15 to stable 2.4.3
- Updated lipgloss dependency to v2

### Documentation
- Added CLI Preview documentation for v0.4.0-alpha.1
- Improved code coverage documentation and module tracking
- Added module and package documentation for `pkg/models`

### Infrastructure
- Comprehensive code coverage and test reporting in CI/CD
- Node.js 24 configured for Docusaurus website builds
- Updated GitHub Actions (checkout v6, artifact actions, create-issue-from-file v6)
- Security dependency updates for website

## [0.3.3] - 2026-01-05

### Added
- **`morphir about` command**: Display version, platform information, and embedded changelog
  - Shows version, git commit, build date, Go version, and platform details
  - `--changelog` flag displays full embedded CHANGELOG.md with colorful markdown rendering by default
  - `--no-color` flag and `NO_COLOR` environment variable support for plain text output
  - `--json` flag for programmatic access to version information
  - Embedded CHANGELOG synced automatically during build process
  - Glamour-powered markdown rendering with automatic dark/light theme detection
- **Install script enhancements**: Support for installing specific versions
  - `install.sh <version>` and `install.ps1 <version>` now accept version argument
  - Still defaults to latest release if no version specified
  - Downloads pre-built binaries from GitHub releases (no Go required)

### Fixed
- **Release script CI wait logic**: Improved automation and reliability
  - Now actively polls and waits for CI to complete (10 minute timeout)
  - Shows progress indicators during wait
  - Prevents releases when CI is still running or failed
  - Reduces manual intervention needed for releases

### Changed
- **Build process**: CHANGELOG.md now automatically synced to cmd directory
  - Added `sync-changelog` mise task with dependency tracking
  - GoReleaser hooks updated to include changelog sync
  - `.gitignore` updated to exclude generated `cmd/morphir/cmd/CHANGELOG.md`

## [0.3.2] - 2026-01-05

### Fixed
- **CRITICAL**: Remove replace directives from source code for go install compatibility
  - Removed all `replace` directives from cmd/morphir/go.mod
  - Removed all `replace` directives from pkg/tooling/go.mod
  - Removed all `replace` directives from tests/bdd/go.mod
  - `go install github.com/finos/morphir/cmd/morphir@v0.3.2` now works correctly
- Documented workflow trigger limitations for re-pushed tags

### Added
- **morphir-developer skill**: Comprehensive development workflow assistant
  - go.work management and verification
  - Branch/worktree setup with issue tracking
  - Pre-commit checks and best practices
  - Integration with beads and GitHub issues
  - TDD/BDD workflow guidance
- **Release automation script**: `scripts/release.sh` for automated releases
  - Complete pre-flight checks
  - Automated tag creation and pushing
  - Workflow triggering and monitoring
  - Post-release verification
  - go install compatibility testing
- **Workspace setup scripts**: Dynamic go.work configuration
  - `scripts/setup-workspace.sh` for Linux/macOS
  - `scripts/setup-workspace.ps1` for Windows
  - Automatically discovers all Go modules
  - Used by CI and local development
- **CI enhancements**: go.work setup for all build/test jobs
  - All CI jobs now use go.work for local module resolution
  - External consumption test for release PRs
  - Verifies module versions are correct before release

### Changed
- Development workflow: Use `go work` for local development instead of replace directives
- Release process: Source code in tags no longer contains replace directives
- Release process: Automated with `scripts/release.sh` for consistency
- CI workflow: All jobs now set up go.work automatically
  - Ensures consistent behavior between local dev and CI
  - Release PRs get additional external consumption test

## [0.3.1] - 2026-01-05

### Fixed
- Complete module version references for all internal dependencies
  - Updated pkg/tooling/go.mod to reference v0.3.0 for pkg/config and pkg/models
  - Updated tests/bdd/go.mod to reference v0.3.0 for pkg/models
  - Fixed release workflow to handle existing tags with `-f` flag
- Release workflow now supports manual re-triggering for failed releases

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

[Unreleased]: https://github.com/finos/morphir/compare/v0.4.0-alpha.2...HEAD
[0.4.0-alpha.2]: https://github.com/finos/morphir/compare/v0.4.0-alpha.1...v0.4.0-alpha.2
[0.4.0-alpha.1]: https://github.com/finos/morphir/compare/v0.3.3...v0.4.0-alpha.1
[0.3.3]: https://github.com/finos/morphir/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/finos/morphir/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/finos/morphir/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/finos/morphir/compare/v0.2.1...v0.3.0
[0.1.0]: https://github.com/finos/morphir/releases/tag/v0.1.0
