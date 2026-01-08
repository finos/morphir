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

### Testing Libraries

- Use `github.com/stretchr/testify` (`require`/`assert`) for unit test assertions.

### Behavior-Driven Development (BDD)

**Specify behavior before implementation.** Use BDD for feature specifications:

- Write feature specifications in clear, domain language
- Define scenarios with Given-When-Then structure
- Ensure tests reflect business requirements

### Adding Self-Describing Example Tests

The `examples/` directory contains self-describing example projects that serve as both documentation and integration tests. Each example includes a `test.yaml` file that declares expected behavior.

**To add a new example project:**

1. **Create the example directory:**
   ```bash
   mkdir -p examples/my-example
   ```

2. **Add the project configuration** (`morphir.toml` or `morphir.json`):
   ```toml
   # examples/my-example/morphir.toml
   [project]
   name = "MyExample"
   version = "1.0.0"
   source_directory = "src"
   exposed_modules = ["Main"]
   ```

3. **Create the `test.yaml` file with expectations:**
   ```yaml
   # examples/my-example/test.yaml
   description: Description of what this example demonstrates

   workspace:
     loads: true
     has_root_project: true
     member_count: 0
     root_project:
       name: MyExample
       version: "1.0.0"
       source_directory: src
       exposed_modules:
         - Main
       config_format: toml
   ```

4. **The example is automatically discovered and tested!**
   - The discovery-based scenario finds all `examples/*/test.yaml` files
   - No need to modify any feature files
   - Run tests with `go test ./tests/bdd/...`

**Available test.yaml fields:**

| Field | Description |
|-------|-------------|
| `description` | Human-readable description of the example |
| `workspace.loads` | Whether the workspace should load successfully |
| `workspace.has_root_project` | Whether the workspace has a root project |
| `workspace.member_count` | Number of workspace members expected |
| `workspace.root_project` | Expectations for the root project |
| `workspace.members` | Array of expectations for member projects |

**Project expectations:**

| Field | Description |
|-------|-------------|
| `name` | Project name |
| `version` | Project version (optional) |
| `source_directory` | Source directory path |
| `module_prefix` | Module prefix (optional) |
| `exposed_modules` | List of exposed module names |
| `config_format` | Configuration format (`toml` or `json`) |

**Testing specific examples:**

You can also test specific examples using the Scenario Outline pattern in feature files:

```gherkin
Scenario Outline: Load <example> workspace and verify expectations
  Given the example project "<example>"
  When I load the example workspace
  Then all workspace expectations should pass

  Examples:
    | example     |
    | my-example  |
```

**Granular assertions:**

For more specific testing, use individual assertion steps:

```gherkin
Scenario: Verify my example workspace details
  Given the example project "my-example"
  When I load the example workspace
  Then the workspace loading expectation should pass
  And the root project expectations should pass
```

### Functional Domain Modeling

**Model the domain using functional patterns:**

- Use algebraic data types where appropriate
- Model domain concepts as immutable types
- Separate domain logic from infrastructure concerns
- Use functional composition to build domain workflows

### Making Illegal States Unrepresentable

**This is a core design principle.** Use the typestate pattern and sum types to encode invariants in the type system, making invalid states impossible to construct.

**Reference:** See [Typestate-Oriented Programming](https://www.cs.cmu.edu/~aldrich/papers/onward2009-state.pdf) for the theoretical foundation.

**Preferred approach in Go - Sealed Interface Pattern:**

```go
// GOOD: Typestate pattern - kind is encoded in the type
type Task interface {
    DependsOn() []string
    isTask() // unexported method seals the interface
}

type IntrinsicTask struct {
    // fields specific to intrinsic tasks
    action string
}
func (IntrinsicTask) isTask() {}

type CommandTask struct {
    // fields specific to command tasks
    cmd []string
}
func (CommandTask) isTask() {}

// Usage: type switch for exhaustive handling
switch t := task.(type) {
case IntrinsicTask:
    // handle intrinsic
case CommandTask:
    // handle command
}
```

```go
// AVOID: Tagged struct with kind field
type Task struct {
    Kind   TaskKind
    Action string   // only valid when Kind == Intrinsic
    Cmd    []string // only valid when Kind == Command
}
// Problem: Can construct Task{Kind: Intrinsic, Cmd: []string{"echo"}}
// which is an invalid state
```

**Key benefits:**
- Compiler enforces valid states - invalid combinations cannot be constructed
- Type switch provides exhaustive pattern matching
- Adding new variants requires updating all switch statements (caught at compile time)
- Self-documenting - the types themselves express what's valid

**When to use this pattern:**
- When a type has mutually exclusive variants (sum types)
- When certain fields are only valid for specific variants
- When you find yourself writing comments like "only meaningful when X is Y"
- When modeling domain concepts with distinct states or modes

**Implementation guidelines:**
1. Define a sealed interface with an unexported method
2. Create concrete types for each variant
3. Use embedded structs for shared fields
4. Provide constructor functions that enforce valid construction
5. Use functional options for optional configuration

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

### ⚠️ CRITICAL: Commit Authorship for AI Assistants

**ABSOLUTELY DO NOT include AI assistants (like Claude) as co-authors in commits.**

This is not optional. This project is part of the FINOS foundation and uses **EasyCLA (Easy Contributor License Agreement)** for compliance.

**Why this matters:**
- ✅ EasyCLA validates that all commit authors/co-authors have signed the CLA
- ❌ AI assistants cannot sign CLAs
- ❌ Adding AI co-authors **breaks the CLA check**
- ❌ This **blocks pull requests** from being merged
- ❌ This **violates FINOS contribution requirements**

**Correct approach:**
```bash
git commit -m "feat: add new feature

This implements the new feature as requested."
```

**INCORRECT approach (WILL BREAK EasyCLA):**
```bash
git commit -m "feat: add new feature

This implements the new feature as requested.

Co-Authored-By: Claude <noreply@anthropic.com>"

# Also NEVER include:
# 🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

**For AI assistants generating commits:**
- ❌ NEVER add yourself as a co-author in the commit message
- ❌ NEVER add footer notes like "Generated with Claude Code" or emojis
- ✅ Only include the actual human contributor as the author
- ✅ Keep commit messages focused on the technical changes
- ✅ The human developer takes full responsibility for the commit

**If you accidentally added AI co-authors:**
Use `git filter-branch` or `git rebase -i` to rewrite commit history and remove the co-author lines before pushing.

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

- Use `mise` task runner (`mise run <task>`) for build orchestration
- Run `mise run build` to build the CLI
- Run `mise run test` to run all tests
- Run `mise run fmt` to format code
- Run `mise run lint` to run linters

### Scripts Directory

The `scripts/` directory contains reusable shell scripts used in build, CI, and development workflows. These scripts are referenced from `mise` tasks for longer task definitions and can also be used directly.

**Available Scripts:**
- `scripts/mod-tidy.sh` / `scripts/mod-tidy.ps1` - Runs `go mod tidy` for all modules in the monorepo
- `scripts/install-dev.sh` / `scripts/install-dev.ps1` - Installs the `morphir-dev` binary to the Go bin directory
- `scripts/verify.sh` / `scripts/verify.ps1` - Verifies all modules build successfully

`mise` task entry points live in `.mise/tasks` and delegate to the scripts above.

**Cross-Platform Support:**
- All scripts have both bash (`.sh`) and PowerShell (`.ps1`) versions for cross-platform support
- `mise` automatically selects the correct `.sh` or `.ps1` script based on OS
- Windows: Uses PowerShell scripts (`.ps1`) and adds `.exe` extension to binaries
- Unix-like (Linux, macOS): Uses bash scripts (`.sh`) and no extension for binaries

**Guidelines for Scripts:**
- Scripts should be executable (`chmod +x` for `.sh` files)
- Bash scripts: Use `#!/usr/bin/env bash` shebang and `set -e` to exit on errors
- PowerShell scripts: Use `$ErrorActionPreference = "Stop"` for error handling
- Scripts should be idempotent when possible
- Keep scripts focused on a single task
- Use scripts in `mise` tasks for complex or multi-step operations
- Scripts can be used directly or via `mise run` commands
- When adding new scripts, create both `.sh` and `.ps1` versions for cross-platform support

**Adding New Scripts:**
- Place new scripts in the `scripts/` directory
- Create both `.sh` (bash) and `.ps1` (PowerShell) versions
- Make bash scripts executable: `chmod +x scripts/your-script.sh`
- Reference them in `mise.toml` with task definitions
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

**This project uses a multi-module Go workspace. The release process is designed to support `go install` compatibility.**

#### Understanding Go Module Tagging

Since Morphir uses multiple Go modules in a monorepo, each module can be versioned independently using subdirectory prefixes in tags:

```
pkg/config/v0.3.0       # Tag for pkg/config module
pkg/models/v0.3.0       # Tag for pkg/models module
cmd/morphir/v0.3.0      # Tag for cmd/morphir module
v0.3.0                  # Main repository tag
```

**For synchronized releases** (recommended), all modules share the same version number.

#### Automated Release Process

Use the provided automation script for releases:

```bash
# 1. Ensure you're on main and up to date
git checkout main
git pull origin main

# 2. Update CHANGELOG.md
#    - Move changes from [Unreleased] to new version section
#    - Add release date: ## [X.Y.Z] - YYYY-MM-DD
#    - Add new [Unreleased] section at top

# 3. Commit changelog
git add CHANGELOG.md
git commit -m "chore: prepare release vX.Y.Z"
git push origin main

# 4. Run release preparation script
./scripts/release-prep.sh vX.Y.Z

# This script will:
#   - Verify no uncommitted changes
#   - Run all verifications (tests, lint, build)
#   - Create tags for all modules:
#     - pkg/config/vX.Y.Z
#     - pkg/models/vX.Y.Z
#     - pkg/pipeline/vX.Y.Z
#     - pkg/sdk/vX.Y.Z
#     - pkg/tooling/vX.Y.Z
#     - cmd/morphir/vX.Y.Z
#     - vX.Y.Z (main tag)

# 5. Push tags to trigger release
git push origin --tags
```

#### What Happens Next

When tags are pushed, **GitHub Actions automatically:**
1. Runs CI checks (format, lint, test, build)
2. **Runs safeguard script** to ensure no replace directives exist
3. Builds binaries for all platforms (Linux, macOS, Windows)
4. Builds for all architectures (amd64, arm64)
5. Generates checksums
6. Creates GitHub Release with artifacts
7. Generates release notes from git history
8. **Enables `go install github.com/finos/morphir/cmd/morphir@vX.Y.Z`**

#### Manual Release (Advanced)

If you need to create a release manually:

```bash
# 1. Update CHANGELOG.md and commit
git add CHANGELOG.md
git commit -m "chore: prepare release vX.Y.Z"

# 2. Manually create all tags
git tag -a pkg/config/vX.Y.Z -m "Release vX.Y.Z - pkg/config"
git tag -a pkg/models/vX.Y.Z -m "Release vX.Y.Z - pkg/models"
git tag -a pkg/pipeline/vX.Y.Z -m "Release vX.Y.Z - pkg/pipeline"
git tag -a pkg/sdk/vX.Y.Z -m "Release vX.Y.Z - pkg/sdk"
git tag -a pkg/tooling/vX.Y.Z -m "Release vX.Y.Z - pkg/tooling"
git tag -a cmd/morphir/vX.Y.Z -m "Release vX.Y.Z - cmd/morphir"
git tag -a vX.Y.Z -m "Release vX.Y.Z"

# 3. Push tags
git push origin main
git push origin --tags
```

#### Manual GitHub Actions Trigger

You can also manually trigger a release:

1. Go to GitHub Actions → Release workflow
2. Click "Run workflow"
3. Enter tag name (e.g., `v0.3.0`)

#### Important: Replace Directives and go install

**This repository does NOT use replace directives in go.mod files.** This is intentional to ensure `go install` compatibility.

- ✅ **For releases**: No replace directives = `go install` works
- ✅ **For local development**: Use `go.work` (run `./scripts/dev-setup.sh`)
- ⚠️ **Safeguard**: GoReleaser runs `./scripts/remove-replace-directives.sh` to catch any accidental additions

**Never commit replace directives to go.mod files.** If you need to work across modules locally, use the Go workspace (`go.work`).

### Local Release Testing

**Before creating a release tag, test locally:**

```bash
# Validate GoReleaser configuration
mise run goreleaser-check

# Build a snapshot (local test, no publish)
mise run release-snapshot

# Full dry-run (validates everything without publishing)
mise run release-test
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
