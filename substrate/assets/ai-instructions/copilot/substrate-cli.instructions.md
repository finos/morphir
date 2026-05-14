---
applyTo: "**/*.md,**/substrate.json,**/substrate.lock"
description: "How to use the substrate CLI to manage and refactor the markdown corpus in a Substrate package."
---

# Substrate CLI — instructions for GitHub Copilot

This project is a [Substrate](https://github.com/AttilaMihaly/morphir/tree/substrate)
corpus: a directory of plain markdown files linked together as a semantic
knowledge graph, rooted at the nearest `substrate.json`. The `substrate`
CLI manages, validates, and refactors that corpus.

**Never edit cross-document links by hand.** Whenever a file or heading
moves, use `substrate refactor rename` so every reference in the project is
updated atomically.

## Refactoring (most important)

`substrate refactor rename <from> <to>` performs one of three operations
based on the shape of its arguments. Use this command in place of `mv`,
`git mv`, or hand-edits whenever a `.md` file or heading moves.

| From shape | To shape | Operation |
| --- | --- | --- |
| `path/file.md` | `path/file.md` | Rename a file on disk and rewrite every link to it. |
| `file.md#old` | `file.md#new` | Rename a heading and rewrite every `#anchor` reference. |
| `a.md#section` | `b.md` | Move section to `b.md`; opens an interactive picker for insertion point. |
| `a.md#section` | `b.md#parent` | Move section to `b.md`, inserted after the `#parent` subtree. |

Examples:

```bash
substrate refactor rename specs/old-name.md specs/new-name.md
substrate refactor rename specs/foo.md#old-anchor specs/foo.md#new-anchor
substrate refactor rename specs/a.md#my-section specs/b.md#parent
```

The new heading text for a rename is derived from the anchor slug —
hyphens become spaces and the first letter is capitalised
(`my-new-section` becomes the heading `My new section`). If the user
gives you the heading text, slugify it first.

**Anchor collisions and identical-slug renames error before any change
is made**; surface the error rather than retrying with hand-edits.

**The interactive picker requires a TTY.** When invoking from automation
or CI, always pass an explicit `#parent` anchor in the destination.

There are no commands for splitting, merging, or renaming directories;
do those manually and then run `substrate validate`.

## Validation and context

| Command | Purpose |
| --- | --- |
| `substrate validate` | Walk every `.md` in the corpus and report unresolved links. Run after any hand-edit. |
| `substrate verify <file>` | Full pipeline: parse → include → lint → references → typecheck → test. Heavier than `validate`. |
| `substrate context <file>[#section] ...` | Emit a tree-shaken, self-contained markdown slice to stdout — for feeding into an LLM. |
| `substrate stats [file]` | Word count, line count, token estimate, link breakdown, heading depths. Reads stdin when no file. |

Useful `substrate context` flags:

- `--no-tree-shaking` — include each referenced file in full, but still rewrite cross-file links to in-document anchors.
- `--no-inline` — do not follow links at all; emit only the explicit roots.
- `--horizontal <path>` — pull in matching sections from a horizontal package via reverse traversal. Repeatable.

If a file has a `#summary` section, asking for the whole file is silently
rewritten to that summary. Author `#summary` deliberately for compact
slices.

## Packages

| Command | Purpose |
| --- | --- |
| `substrate init` | Scaffold a new package: prompts for name, kind, version. Pass `-y` for defaults. Also drops these AI instructions into the project. |
| `substrate install` | Resolve and vendor every dependency under `substrate/`. Writes `substrate.lock`. Also refreshes these AI instructions. Idempotent. Pass `-f` / `--force` to reinstall everything even if already present per the lockfile. |
| `substrate update [pkg]` | Re-resolve one or every dependency against the latest matching git tag. |
| `substrate publish` | Tag and push a library/horizontal release. Refuses on dirty trees or `kind: corpus`. |

The contents of `.github/instructions/substrate-cli.instructions.md` and
`.claude/skills/substrate-cli/SKILL.md` are **managed by `substrate
install`** — they are overwritten on every install. Do not hand-edit
them; if you need a customisation, copy them to a different filename.

## Conventions for generated commands

- Always use forward slashes in paths, even on Windows.
- Anchors follow GFM slug rules: lowercase, alphanumerics and hyphens,
  duplicates within one file get `-2`, `-3`, … suffixes.
- The CLI mutates the working tree. Confirm before running a refactor,
  install, update, or publish unless the user has pre-approved it.
- After any hand-edit you make to a markdown file, run `substrate
  validate` before reporting the task complete.
