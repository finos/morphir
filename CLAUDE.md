# Claude Code Agent Instructions

This file provides instructions for Claude Code and other AI assistants working on the **finos/morphir** repository — the Morphir ecosystem umbrella project.

For complete development guidelines, coding standards, and contribution practices, please refer to [AGENTS.md](AGENTS.md).

## What this repository is

**finos/morphir** is the parent repository for the Morphir ecosystem. It contains:

- **Documentation** — Docusaurus site (`website/`) and published docs (`docs/`)
- **Morphir CLI** — Rust command-line tool (`crates/morphir`)
- **Morphir Live** — Rust interactive visualization app (`crates/morphir-live`)
- **Ecosystem integration** — Git submodules for language implementations (`ecosystem/`)

This is **not** the Morphir Go repository. Go-based Morphir tooling lives in the sibling repo [finos/morphir-go](https://github.com/finos/morphir-go).

## ⚠️ CRITICAL: No AI Co-Authors in Commits

**DO NOT add Claude or any AI assistant as a commit co-author under any circumstances.**

This project uses EasyCLA (Easy Contributor License Agreement) for FINOS compliance. Adding AI co-authors:
- ❌ Breaks the CLA verification process
- ❌ Blocks pull requests from being merged
- ❌ Violates FINOS contribution requirements

**NEVER include lines like:**
```
Co-Authored-By: Claude <noreply@anthropic.com>
🤖 Generated with Claude Code
```

Only the human developer should be listed as the author/co-author. See [AGENTS.md](AGENTS.md#commit-authorship-for-ai-assistants) for details.

## Quick Reference

- **Umbrella repo**: Docs, Rust CLI/Live, and ecosystem submodules — not a single-language implementation
- **Functional Programming First**: This codebase follows functional programming principles
- **TDD/BDD**: Write tests before implementation
- **No AI Co-Authors**: See critical warning above - this breaks EasyCLA
- **Morphir Alignment**: Maintain compatibility with Morphir IR specification
- **Ecosystem work**: See [ecosystem/AGENTS.md](ecosystem/AGENTS.md) when touching submodules

See [AGENTS.md](AGENTS.md) for detailed guidelines.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
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
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
