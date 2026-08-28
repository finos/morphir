# AGENTS.md - Agentic Hints for Morphir

This document provides guidance for AI assistants and developers working on the **finos/morphir** repository.

## Project Overview

**finos/morphir** is the Morphir ecosystem umbrella (parent) repository. It coordinates documentation, shared tooling, and integration with language-specific implementations — it is not a single-language Morphir implementation.

### In this repository

1. **Morphir Documentation Website** — Docusaurus-based documentation site (`website/`, `docs/`)
2. **Morphir Live** — Rust-based interactive visualization and IR management application (`crates/morphir-live`)
3. **Morphir CLI** — Rust command-line tool for working with Morphir IR (`crates/morphir`)
4. **Ecosystem Integration** — Git submodules for ecosystem repos under `ecosystem/`

### Ecosystem submodules (vendored under `ecosystem/`)

- **[finos/morphir-elm](https://github.com/finos/morphir-elm)** — Reference Elm implementation; IR definition, compilers, visualization, backend processors
- **[finos/morphir-rust](https://github.com/finos/morphir-rust)** — Rust libraries (`morphir-core`, `morphir-common`, etc.) used by the CLI and Morphir Live
- **[finos/morphir-examples](https://github.com/finos/morphir-examples)** — Example Morphir projects
- **[finos/morphir-moonbit](https://github.com/finos/morphir-moonbit)** — MoonBit implementation of Morphir tooling
- **[finos/morphir-python](https://github.com/finos/morphir-python)** — Python implementation of Morphir tooling
- **[finos/morphir-scala](https://github.com/finos/morphir-scala)** — Scala implementation of Morphir tooling
- **[finos/morphir-ui](https://github.com/finos/morphir-ui)** — User-interface work for the Morphir project

See [ecosystem/README.md](ecosystem/README.md) and [ecosystem/AGENTS.md](ecosystem/AGENTS.md) for submodule workflows.

### Sibling FINOS repositories (not vendored here)

These live in their own repositories. Do not assume their code or build instructions apply to this tree unless they are added as submodules.

- **[finos/morphir-go](https://github.com/finos/morphir-go)** — Go implementation of Morphir tooling (CLI, WIT pipeline, Go backends)
- **[finos/morphir-jvm](https://github.com/finos/morphir-jvm)** — JVM-based implementation
- **[finos/morphir-dotnet](https://github.com/finos/morphir-dotnet)** — .NET implementation
- **[finos/morphir-bosque](https://github.com/finos/morphir-bosque)** — Bosque language integration

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

### Ecosystem Build Tasks

Build and test ecosystem submodules from the top-level repo:

- `mise run build:morphir-moonbit` - Build all MoonBit packages
- `mise run build:morphir-moonbit -- <pkg>` - Build specific package(s)
- `mise run test:morphir-moonbit` - Run all MoonBit tests
- `mise run test:morphir-moonbit -- <pkg>` - Test specific package(s)

Valid package names: `morphir-sdk`, `morphir-core`, `morphir-moonbit-bindings`

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

### The `.dev/` Working Area

`.dev/` is a gitignored scratch area for AI-assisted development: temporary scripts, agent and script outputs, and working documents. Nothing in it is committed. Suggested layout:

- Specs from the superpowers `brainstorming` skill: `.dev/docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
- Plans from the superpowers `writing-plans` skill: `.dev/docs/superpowers/plans/YYYY-MM-DD-<topic>-plan.md`
- Scratch scripts and their outputs: `.dev/scripts/`, `.dev/out/`

Never place working documents under `docs/`: everything in `docs/` is published to morphir.finos.org by the website build. When a design is final and meant for readers, write it up under `docs/design/` with the usual front matter.

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

Session-close git behavior is governed by the **Agent Context Profiles** in the
managed Beads block below. The default (**Conservative**) profile does NOT
commit or push unless explicitly asked — at handoff, report changed files,
validation results, and the exact commands you would run.

## Landing the Plane (Session Completion)

**When ending a work session**, complete the steps below. Steps 1–3 and 5
apply to every session; step 4 depends on the active profile.

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile:**
   - **Conservative (default) / minimal**: do NOT commit or push unless the
     user asked for it this session. Report status and the proposed commands.
   - **Team-maintainer (explicit repository opt-in only)**: commit and push as
     part of session close — work is then not complete until `git push`
     succeeds:
     ```bash
     git pull --rebase
     bd sync
     git push
     git status  # MUST show "up to date with origin"
     ```
     If push fails under this profile, resolve and retry until it succeeds. A
     current "do not commit" or "do not push" instruction still wins.
5. **Hand off** - Provide context for next session: changes, validation,
   issue status, and any blocked sync/commit/push step

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:970c3bf2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   bd dolt push
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

<!-- BEGIN BEADS CODEX SETUP: generated by bd setup codex -->
## Beads Issue Tracker

Use Beads (`bd`) for durable task tracking in repositories that include it. Use the `beads` skill at `.agents/skills/beads/SKILL.md` (project install) or `~/.agents/skills/beads/SKILL.md` (global install) for Beads workflow guidance, then use the `bd` CLI for issue operations.

### Quick Reference

```bash
bd ready                # Find available work
bd show <id>            # View issue details
bd update <id> --claim  # Claim work
bd close <id>           # Complete work
bd prime                # Refresh Beads context
```

### Rules

- Use `bd` for all task tracking; do not create markdown TODO lists.
- Run `bd prime` when Beads context is missing or stale. Codex 0.129.0+ can load Beads context automatically through native hooks; use `/hooks` to inspect or toggle them.
- Keep persistent project memory in Beads via `bd remember`; do not create ad hoc memory files.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.
<!-- END BEADS CODEX SETUP -->
