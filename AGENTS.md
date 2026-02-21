# AGENTS.md - Agentic Hints for Morphir

This document provides guidance for AI assistants and developers working on the Morphir project.

## Project Overview

This repository contains:
1. **Morphir Documentation Website** - Docusaurus-based documentation site
2. **Morphir Live** - Rust-based interactive visualization and IR management application
3. **Morphir CLI** - Command-line tool for working with Morphir IR
4. **Ecosystem Integration** - Git submodules for ecosystem repos (morphir-rust, morphir-examples, etc.)

### Related Morphir Projects

- **[finos/morphir-go](https://github.com/finos/morphir-go)** - Go implementation of Morphir tooling
- **[finos/morphir-elm](https://github.com/finos/morphir-elm)** - Reference implementation in Elm (most mature)
- **[finos/morphir-jvm](https://github.com/finos/morphir-jvm)** - JVM-based implementation
- **[finos/morphir-scala](https://github.com/finos/morphir-scala)** - Scala implementation
- **[finos/morphir-dotnet](https://github.com/finos/morphir-dotnet)** - .NET implementation
- **[finos/morphir-rust](https://github.com/finos/morphir-rust)** - Rust tooling
- **[finos/morphir-python](https://github.com/finos/morphir-python)** - Python tooling
- **[finos/morphir-moonbit](https://github.com/finos/morphir-moonbit)** - MoonBit implementation of Morphir tooling

### Morphir IR Specification

The Morphir IR specification and JSON schemas are available in the morphir-dotnet documentation. Always maintain alignment with the official IR specification when implementing features.

## Core Morphir Design Principles

### Functional Programming

**Functional programming is fundamental to this codebase.** All code should follow functional programming principles:

- **Immutable data structures** - Prefer immutable types and avoid mutating state
- **Pure functions** - Functions should have no side effects when possible
- **Separation of concerns** - Clearly define I/O boundaries
- **Functional composition** - Build complex behavior from simple, composable functions

## Development Practices

### Test-Driven Development (TDD)

**Write tests before implementation.** Follow the TDD cycle:

1. Write a failing test
2. Write minimal code to make it pass
3. Refactor while keeping tests green

### Clean, Well-Organized Code

- Write self-documenting code with clear names
- Keep functions small and focused
- Follow Rust conventions and idioms
- Organize code by feature/domain, not by technical layer

## Rust Development Guidelines

### Workspace Structure

- Cargo workspace at repository root
- Crates located in `crates/` directory
- Edition 2024 with resolver v3

### Key Dependencies

- **dioxus** - Cross-platform UI framework (web, desktop, mobile)
- **clap** - Command-line argument parsing with derive macros
- **miette** - Fancy diagnostic error reporting
- **tracing** - Structured, async-aware logging and diagnostics
- **serde** - Serialization/deserialization

### Rust Development Guidelines

1. Use workspace dependencies for version consistency
2. Prefer `miette` for user-facing errors with helpful diagnostics
3. Use `tracing` macros (`info!`, `debug!`, `error!`) instead of `println!`
4. Follow Rust 2024 edition idioms

### Example Rust patterns

```rust
// CLI with clap
use clap::Parser;

#[derive(Parser)]
#[command(name = "morphir-live")]
struct Cli {
    #[arg(short, long)]
    verbose: bool,
}

// Error handling with miette
use miette::{Diagnostic, Result};
use thiserror::Error;

#[derive(Error, Diagnostic, Debug)]
#[error("Failed to parse IR")]
#[diagnostic(code(morphir::parse_error))]
struct ParseError {
    #[source_code]
    src: String,
    #[label("here")]
    span: (usize, usize),
}

// Structured logging with tracing
use tracing::{info, instrument};

#[instrument]
fn process_ir(path: &str) -> Result<()> {
    info!(path, "Processing IR file");
    // ...
    Ok(())
}
```

## Project Structure

```
morphir/
├── crates/
│   ├── morphir/          # Morphir CLI tool
│   └── morphir-live/     # Interactive visualization app (Dioxus)
├── ecosystem/            # Git submodules for ecosystem repos
│   ├── morphir-rust/     # Rust libraries (morphir-core, morphir-common, etc.)
│   ├── morphir-examples/ # Example Morphir projects
│   ├── README.md         # User guide for ecosystem submodules
│   └── AGENTS.md         # Agent guidelines for ecosystem directory
├── website/              # Docusaurus documentation site
├── docs/                 # Documentation content
├── examples/             # Example projects
├── Cargo.toml            # Rust workspace configuration
└── .config/mise/         # Development task configuration
```

See [ecosystem/AGENTS.md](ecosystem/AGENTS.md) for guidelines on working with submodules and path dependencies.

## Build and Development

Use `mise` task runner (`mise run <task>`) for build orchestration:

- `mise run init` - Initialize development environment (submodules, etc.)
- `mise run build` - Build the project
- `mise run test` - Run all tests
- `mise run fmt` - Format code
- `mise run lint` - Run linters (clippy)
- `mise run dev` - Run morphir-live in development mode
- `mise run submodules:init` - Initialize git submodules (first-time setup)
- `mise run submodules:update` - Update submodules to recorded commits
- `mise run submodules:status` - Show submodule status
- `mise run submodules:add -- <name> [url]` - Add a new ecosystem submodule

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

3. **Reference other Morphir implementations**
   - Check how similar features are implemented in other languages
   - Maintain consistency with Morphir IR specification

### ⚠️ CRITICAL: Commit Authorship for AI Assistants

**ABSOLUTELY DO NOT include AI assistants (like Claude) as co-authors in commits.**

This project is part of the FINOS foundation and uses **EasyCLA** for compliance.

- ❌ Adding AI co-authors **breaks the CLA check**
- ❌ This **blocks pull requests** from being merged

**Correct approach:**
```bash
git commit -m "feat: add new feature"
```

**INCORRECT approach (WILL BREAK EasyCLA):**
```bash
git commit -m "feat: add new feature

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Monitoring GitHub PR Checks

When monitoring GitHub PR checks (CI status, workflow runs, etc.), **prefer using watch mode with timeout or failfast** rather than performing a sleep and then checking.

**Preferred approach:**
- Use `gh pr checks watch` or similar watch-mode commands with timeout/failfast flags
- This provides real-time updates and exits as soon as checks complete or fail
- More efficient than polling with sleep intervals

**Example:**
```bash
# Watch PR checks with timeout
gh pr checks watch --timeout 30m --failfast

# Or watch specific workflow runs
gh run watch --timeout 20m --exit-status
```

**Avoid:**
- ❌ `sleep 60 && gh pr checks` (inefficient polling)
- ❌ Manual polling loops with fixed delays

Watch mode provides better responsiveness and resource efficiency by reacting to state changes immediately rather than waiting for arbitrary time intervals.

## Documentation

The Docusaurus website is located in `website/`. To run locally:

```bash
cd website
npm install
npm start
```

## Questions?

When in doubt:
1. Check reference implementations (especially morphir-elm)
2. Consult Morphir IR specification
3. Follow functional programming principles
4. Write tests first
5. Keep code simple and composable

---

## Beads Workflow Integration

This project uses beads for issue tracking. Issues are stored in `.beads/` and tracked in git.

### Essential Commands

```bash
bd ready              # Show issues ready to work (no blockers)
bd list --status=open # All open issues
bd show <id>          # Full issue details with dependencies
bd create --title="..." --type=task --priority=2
bd update <id> --status=in_progress
bd close <id>
bd sync               # Commit and push changes
```

### Session Protocol

**Before ending any session:**

```bash
git status              # Check what changed
git add <files>         # Stage code changes
bd sync                 # Commit beads changes
git commit -m "..."     # Commit code
git push                # Push to remote
```

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
