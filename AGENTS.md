# AGENTS.md - Agentic Hints for Morphir Go

This document provides guidance for AI assistants and developers working on the Morphir Go project.

## Project Overview

This is a **Go port of the Morphir tooling ecosystem**. Morphir is a technology-agnostic intermediate representation (IR) for business logic and data models, enabling code generation, documentation, and analysis across multiple target platforms.

### Reference Implementations

When implementing features, refer to these existing Morphir implementations for consistency:

- **finos/morphir** - Core Morphir project and IR specification
- **finos/morphir-elm** - Reference implementation in Elm (most mature)
- **finos/morphir-jvm** - JVM-based implementation
- **finos/morphir-scala** - Scala implementation
- **finos/morphir-dotnet** - .NET implementation (contains IR spec and JSON schemas in documentation)
- **finos/morphir-rust** - Early-stage Rust tooling

### Morphir IR Specification

The Morphir IR specification and JSON schemas are available in the morphir-dotnet documentation. Always maintain alignment with the official IR specification when implementing features.

## Architecture Decision Records (ADRs)

This repo uses ADRs to document important architectural decisions and trade-offs.

- ADRs live in [docs/adr](docs/adr).
- When making a significant design change (IR modeling, codec/versioning strategy, CLI UX/behavior), add or update an ADR.
- For discriminated union / sum type representation in Go, start with `ADR-0001`.

## Core Morphir Design Principles

### Functional Programming and Functional Domain Practices

**Functional programming is fundamental to this codebase.** All code should follow functional programming principles:

- **Immutable data structures** - Prefer immutable types and avoid mutating state
- **Pure functions** - Functions should have no side effects when possible
- **Separation of concerns** - Clearly define I/O boundaries
- **Functional composition** - Build complex behavior from simple, composable functions
- **Domain-driven design alignment** - Model the domain using functional patterns

### Code Organization Principles

When writing code:

1. **Prefer pure functions over impure ones**
   - Pure functions are easier to test, reason about, and compose
   - Isolate side effects to I/O boundaries

2. **Return values and errors instead of mutating state**
   - Functions should return new values rather than modifying inputs
   - Use error returns instead of panics where possible

3. **Use immutable data structures**
   - Prefer structs with value semantics
   - Avoid global mutable state
   - Use functional update patterns (return new instances)

4. **Separate I/O from business logic**
   - Keep business logic pure and testable
   - Isolate file system, network, and user interaction to boundaries

5. **Functional composition over imperative flow**
   - Compose small functions into larger behaviors
   - Use higher-order functions where appropriate

## Development Practices

### Test-Driven Development (TDD)

**Write tests before implementation.** Follow the TDD cycle:

1. Write a failing test
2. Write minimal code to make it pass
3. Refactor while keeping tests green

Tests should be:
- Fast
- Independent
- Repeatable
- Self-validating
- Timely

### Behavior-Driven Development (BDD)

**Specify behavior before implementation.** Use BDD for feature specifications:

- Write feature specifications in clear, domain language
- Define scenarios with Given-When-Then structure
- Ensure tests reflect business requirements

### Functional Domain Modeling

**Model the domain using functional patterns:**

- Use algebraic data types where appropriate
- Model domain concepts as immutable types
- Separate domain logic from infrastructure concerns
- Use functional composition to build domain workflows

### Clean, Well-Organized Code

- Write self-documenting code with clear names
- Keep functions small and focused
- Follow Go conventions and idioms
- Organize code by feature/domain, not by technical layer

## CLI Development Guidelines

### Output Format and Streams

**Separation of Output Streams:**
- **stdout** - Use for actual command output (data, results, structured output)
- **stderr** - Use for logging, diagnostics, progress messages, and error messages

This separation allows users to pipe command output while still seeing diagnostic information, and enables proper shell redirection patterns.

```go
// Good: Output to stdout, diagnostics to stderr
func runCommand(cmd *cobra.Command, args []string) error {
    fmt.Fprintf(os.Stderr, "Processing...\n") // Diagnostic message
    result := processData(args)
    fmt.Fprintf(os.Stdout, "%s\n", result) // Actual output
    return nil
}

// Avoid: Mixing output streams
func runCommand(cmd *cobra.Command, args []string) error {
    fmt.Println("Processing...") // Goes to stdout - wrong!
    fmt.Println(result) // Actual output
    return nil
}
```

### JSON Output Support

**All non-interactive commands should support a `--json` flag** to output results in JSON format. This enables:
- Machine-readable output for scripting and automation
- Integration with other tools and pipelines
- Consistent structured output across commands

**Implementation Pattern:**
```go
var jsonOutput bool

func init() {
    validateCmd.Flags().BoolVar(&jsonOutput, "json", false, "Output results as JSON")
}

func runValidate(cmd *cobra.Command, args []string) error {
    result := validateIR(args)
    
    if jsonOutput {
        // Output JSON to stdout
        encoder := json.NewEncoder(os.Stdout)
        encoder.SetIndent("", "  ")
        return encoder.Encode(result)
    }
    
    // Output human-readable format to stdout
    fmt.Fprintf(os.Stdout, "%s\n", formatHumanReadable(result))
    return nil
}
```

**Guidelines:**
- JSON output should be written to **stdout** (not stderr)
- Logging and diagnostics should still go to **stderr** even when `--json` is used
- JSON output should be well-structured and follow consistent schemas
- When `--json` is used, avoid mixing JSON with human-readable text
- Use proper JSON encoding with indentation for readability (when appropriate)

**Interactive Commands:**
- Commands that launch interactive UIs (like the root TUI) do not need `--json` support
- Commands that can be both interactive and non-interactive should support `--json` for non-interactive mode

## When Contributing

### Code Style

1. **Follow functional programming patterns**
   - Avoid mutable state
   - Prefer pure functions
   - Use functional composition

2. **Write tests first (TDD)**
   - Start with failing tests
   - Implement to make tests pass
   - Refactor with confidence

3. **Use BDD for feature specifications**
   - Define behavior clearly
   - Write scenarios that reflect requirements

4. **Reference other Morphir implementations**
   - Check how similar features are implemented in other languages
   - Maintain consistency with Morphir IR specification
   - Learn from reference implementations (especially morphir-elm)

5. **Maintain alignment with Morphir IR specification**
   - Ensure compatibility with the official IR
   - Validate against JSON schemas when available
   - Test interoperability with other Morphir tools

6. **Follow CLI development guidelines**
   - Separate stdout (output) from stderr (logging/diagnostics)
   - Add `--json` flag support to all non-interactive commands
   - Ensure JSON output is well-structured and consistent

### Commit Authorship for AI Assistants

**IMPORTANT: When AI assistants (like Claude) create commits, DO NOT include Claude as a co-author.**

This project is part of the FINOS foundation and uses EasyCLA for Contributor License Agreement management. Adding AI assistants as co-authors breaks the CLA verification process.

**Correct approach:**
```bash
git commit -m "feat: add new feature

This implements the new feature as requested."
```

**INCORRECT approach (will break EasyCLA):**
```bash
git commit -m "feat: add new feature

This implements the new feature as requested.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

**For AI assistants generating commits:**
- Only include the actual human contributor as the author
- Do not add yourself as a co-author in the commit message
- Do not add footer notes like "Generated with Claude Code"
- Keep commit messages focused on the technical changes

### Example: Functional Pattern

```go
// Good: Pure function, immutable data
func ProcessModel(model Model) (ProcessedModel, error) {
    // Process without mutating input
    processed := transform(model)
    return processed, nil
}

// Avoid: Mutating input
func ProcessModel(model *Model) error {
    // Mutating model - not functional
    model.Field = newValue
    return nil
}
```

### Example: Functional Update Pattern

```go
// Good: Return new instance
func UpdateState(state State, value int) State {
    return State{
        Count: state.Count + value,
        // Copy other fields
    }
}

// Avoid: Mutating state
func UpdateState(state *State, value int) {
    state.Count += value
}
```

## Project Structure

- `cmd/morphir/` - CLI application (Cobra + Bubbletea)
- `pkg/models/` - Morphir IR model types
- `pkg/tooling/` - Utilities and tools
- `pkg/sdk/` - SDK for building Morphir applications
- `pkg/pipeline/` - Processing pipelines for IR transformations

Each package is a separate Go module, managed via `go.work` for development.

## Build and Development

- Use `just` for build orchestration (see `Justfile`)
- Run `just build` to build the CLI
- Run `just test` to run all tests
- Run `just fmt` to format code
- Run `just lint` to run linters

### Scripts Directory

The `scripts/` directory contains reusable shell scripts used in build, CI, and development workflows. These scripts are referenced from the `Justfile` for longer task definitions and can also be used directly.

**Available Scripts:**
- `scripts/mod-tidy.sh` / `scripts/mod-tidy.ps1` - Runs `go mod tidy` for all modules in the monorepo
- `scripts/install-dev.sh` / `scripts/install-dev.ps1` - Installs the `morphir-dev` binary to the Go bin directory
- `scripts/verify.sh` / `scripts/verify.ps1` - Verifies all modules build successfully

**Cross-Platform Support:**
- All scripts have both bash (`.sh`) and PowerShell (`.ps1`) versions for cross-platform support
- The `Justfile` uses `scripts/detect-os.sh` for proper OS detection (windows, linux, darwin)
- OS detection is done via helper recipes (`_os`, `_bin-ext`, `_script-ext`, `_powershell`)
- Windows: Uses PowerShell scripts (`.ps1`) and adds `.exe` extension to binaries
- Unix-like (Linux, macOS): Uses bash scripts (`.sh`) and no extension for binaries
- The Justfile automatically selects the correct scripts and binary extensions based on detected OS

**Guidelines for Scripts:**
- Scripts should be executable (`chmod +x` for `.sh` files)
- Bash scripts: Use `#!/usr/bin/env bash` shebang and `set -e` to exit on errors
- PowerShell scripts: Use `$ErrorActionPreference = "Stop"` for error handling
- Scripts should be idempotent when possible
- Keep scripts focused on a single task
- Use scripts in `Justfile` for complex or multi-step operations
- Scripts can be used directly or via `just` commands
- When adding new scripts, create both `.sh` and `.ps1` versions for cross-platform support

**Adding New Scripts:**
- Place new scripts in the `scripts/` directory
- Create both `.sh` (bash) and `.ps1` (PowerShell) versions
- Make bash scripts executable: `chmod +x scripts/your-script.sh`
- Reference them in the `Justfile` with platform detection
- Document their purpose in comments at the top of the script

## Release Process

### Versioning Strategy

**This project follows [Semantic Versioning](https://semver.org/) (SemVer):**

- **MAJOR.MINOR.PATCH** (e.g., `1.2.3`)
  - **MAJOR**: Breaking changes to public APIs or behavior
  - **MINOR**: New features, backward compatible
  - **PATCH**: Bug fixes, backward compatible

**Pre-release versions** can be tagged with suffixes:
- `v1.0.0-alpha.1` - Alpha release
- `v1.0.0-beta.1` - Beta release
- `v1.0.0-rc.1` - Release candidate

### Changelog Management

**All notable changes must be documented in `CHANGELOG.md` following [Keep a Changelog](https://keepachangelog.com/) format:**

- Changes are grouped under: **Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**
- Keep an **[Unreleased]** section at the top for ongoing work
- When releasing, convert **[Unreleased]** to **[VERSION] - YYYY-MM-DD**
- Add a new **[Unreleased]** section for future changes

**Hybrid Approach:**
- Manually maintain `CHANGELOG.md` for notable changes
- GoReleaser auto-generates release notes from git commits
- Use conventional commit format for better auto-generated notes

### Conventional Commits

**Use [Conventional Commits](https://www.conventionalcommits.org/) for better changelog generation:**

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat:` - New feature (triggers MINOR version bump)
- `fix:` - Bug fix (triggers PATCH version bump)
- `docs:` - Documentation only
- `style:` - Code style/formatting (no logic change)
- `refactor:` - Code refactoring (no behavior change)
- `perf:` - Performance improvement
- `test:` - Adding or updating tests
- `chore:` - Maintenance tasks, dependencies
- `ci:` - CI/CD changes

**Breaking changes:**
- Add `!` after type: `feat!:` or `fix!:`
- Or add `BREAKING CHANGE:` in footer (triggers MAJOR version bump)

**Examples:**
```bash
git commit -m "feat(cli): add validate command for Morphir IR"
git commit -m "fix(models): correct package name parsing"
git commit -m "feat!: change IR structure to match spec v2"
```

### Release Workflow

**Releases are automated via GitHub Actions:**

1. **Update CHANGELOG.md**
   - Move changes from `[Unreleased]` to new version section
   - Add release date: `## [X.Y.Z] - YYYY-MM-DD`
   - Add new `[Unreleased]` section at top
   - Update version comparison links at bottom

2. **Commit changelog**
   ```bash
   git add CHANGELOG.md
   git commit -m "chore: prepare release vX.Y.Z"
   ```

3. **Create and push tag**
   ```bash
   git tag -a vX.Y.Z -m "Release X.Y.Z"
   git push origin main
   git push origin vX.Y.Z
   ```

4. **GitHub Actions automatically:**
   - Runs CI checks (format, lint, test, build)
   - Builds binaries for all platforms (Linux, macOS, Windows)
   - Builds for all architectures (amd64, arm64)
   - Generates checksums
   - Creates GitHub Release with artifacts
   - Generates release notes from git history

5. **Manual release trigger (optional):**
   - Go to GitHub Actions → Release workflow
   - Click "Run workflow"
   - Enter tag name (e.g., `v0.1.0`)

### Local Release Testing

**Before creating a release tag, test locally:**

```bash
# Validate GoReleaser configuration
just goreleaser-check

# Build a snapshot (local test, no publish)
just release-snapshot

# Full dry-run (validates everything without publishing)
just release-test
```

### Release Artifacts

**Each release includes:**
- Cross-platform binaries: Linux, macOS, Windows
- Multi-architecture: amd64, arm64
- Compressed archives (`.tar.gz` for Unix, `.zip` for Windows)
- SHA256 checksums (`checksums.txt`)
- Auto-generated changelog from commits
- Manual changelog from `CHANGELOG.md`

### Installation Methods

**Users can install via:**

1. **Binary download** - Download from GitHub Releases
2. **Go install** - `go install github.com/finos/morphir-go/cmd/morphir@vX.Y.Z`
3. **Homebrew** - (future) `brew install finos/tap/morphir`

### Version Information

**The CLI embeds version information at build time:**

```bash
morphir --version
# Output: morphir version 0.1.0 (commit: a1b2c3d, built: 2026-01-01T12:00:00Z)
```

**Version variables** (set via ldflags):
- `Version` - SemVer version (e.g., `0.1.0`)
- `GitCommit` - Short commit hash
- `BuildDate` - ISO 8601 timestamp

### CI/CD Workflows

**Two main workflows:**

1. **CI Workflow** (`.github/workflows/ci.yml`)
   - Triggers: Push to `main`, all PRs
   - Jobs: format check, lint, test, build matrix
   - Ensures code quality before merge

2. **Release Workflow** (`.github/workflows/release.yml`)
   - Triggers: Tag push (`v*`), manual dispatch
   - Uses GoReleaser for automated releases
   - Creates GitHub Release with all artifacts

## Questions?

When in doubt:
1. Check reference implementations (especially morphir-elm)
2. Consult Morphir IR specification
3. Follow functional programming principles
4. Write tests first
5. Keep code simple and composable

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

<!-- bv-agent-instructions-v1 -->

---

## Beads Workflow Integration

This project uses [beads_viewer](https://github.com/Dicklesworthstone/beads_viewer) for issue tracking. Issues are stored in `.beads/` and tracked in git.

### Essential Commands

```bash
# View issues (launches TUI - avoid in automated sessions)
bv

# CLI commands for agents (use these instead)
bd ready              # Show issues ready to work (no blockers)
bd list --status=open # All open issues
bd show <id>          # Full issue details with dependencies
bd create --title="..." --type=task --priority=2
bd update <id> --status=in_progress
bd close <id> --reason="Completed"
bd close <id1> <id2>  # Close multiple issues at once
bd sync               # Commit and push changes
```

### Workflow Pattern

1. **Start**: Run `bd ready` to find actionable work
2. **Claim**: Use `bd update <id> --status=in_progress`
3. **Work**: Implement the task
4. **Complete**: Use `bd close <id>`
5. **Sync**: Always run `bd sync` at session end

### Key Concepts

- **Dependencies**: Issues can block other issues. `bd ready` shows only unblocked work.
- **Priority**: P0=critical, P1=high, P2=medium, P3=low, P4=backlog (use numbers, not words)
- **Types**: task, bug, feature, epic, question, docs
- **Blocking**: `bd dep add <issue> <depends-on>` to add dependencies

### Session Protocol

**Before ending any session, run this checklist:**

```bash
git status              # Check what changed
git add <files>         # Stage code changes
bd sync                 # Commit beads changes
git commit -m "..."     # Commit code
bd sync                 # Commit any new beads changes
git push                # Push to remote
```

### Best Practices

- Check `bd ready` at session start to find available work
- Update status as you work (in_progress → closed)
- Create new issues with `bd create` when you discover tasks
- Use descriptive titles and set appropriate priority/type
- Always `bd sync` before ending session

<!-- end-bv-agent-instructions -->
