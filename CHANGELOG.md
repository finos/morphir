# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- GoReleaser configuration for automated releases
- GitHub Actions CI workflow for format, lint, test, and build checks
- GitHub Actions release workflow for automated releases on tags
- Version information in CLI (`morphir --version`)
- Cross-platform support: Linux, macOS, Windows (amd64, arm64)
- Changelog management following Keep a Changelog format

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

[Unreleased]: https://github.com/finos/morphir-go/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/finos/morphir-go/releases/tag/v0.1.0
