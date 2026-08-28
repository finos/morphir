---
type: Capability
title: Knowledge Base Tooling
description: "The morphir kb command manages the OKF knowledge base and the intent recorded in it, from the command line."
tags: [tooling, kb]
status: stable
generated:
  by: process:kb-seed
  at: 2026-08-28T00:00:00Z
---

# Knowledge Base Tooling

The morphir kb command manages the OKF knowledge base and the intent recorded in it, from the command line.

The `kb` subcommand of the Morphir CLI operates everything under `kb/`: it lists and
searches bundles, scaffolds new bundles and concept documents, lints the tree against the OKF conventions,
builds a SQLite full-text index, vendors upstream sources into mirrored bundles, and runs the intent and
decision registers. It carries the command surface of the Scala `kb` tool from morphir-scala — the same
subcommands, flags, defaults, JSON shapes and exit codes — so playbooks written against that tool run here
unchanged. Parity stops at its faults: where the reference behaves wrongly, this implementation corrects it.

The implementation lives in the morphir-rust workspace as two crates. `morphir-okf` models the Open Knowledge
Format itself: bundles, concept documents, frontmatter, links, and the parsing rules. `morphir-kb` builds the
operations on top: the check catalogue, scaffolding, the index, sync, the registers, and the refresh that keeps
generated markdown and the index in step. The CLI in `crates/morphir` is a thin argument layer over those
crates.

Day to day, three commands carry most of the weight: `morphir kb check` before committing kb content,
`morphir kb add-concept` to scaffold a new document into its index and log, and `morphir kb search` (or
`--index` for full-text ranking) to find what is already written. The kb skill at
`.claude/skills/kb/SKILL.md` wraps these workflows for agents.
