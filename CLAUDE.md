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


<!-- bd-doctor-divergence: ok -->
<!-- The Beads block lives in AGENTS.md only. Task tracking is the same for every
     agent that works here, so it belongs in the file they all read; this file
     carries what is specific to Claude Code. -->

## Issue tracking

This project tracks work with **bd (beads)**, and the guidance applies to every
agent, not just Claude Code — see [Beads Issue Tracker](AGENTS.md#beads-issue-tracker)
in AGENTS.md, and run `bd prime` for the full command reference and session-close
protocol.
