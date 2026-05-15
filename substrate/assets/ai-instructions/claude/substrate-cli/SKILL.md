---
name: substrate-cli
description: Use the substrate CLI to manage, refactor, validate, and slice the markdown corpus in a Substrate package. Trigger whenever the user wants to rename a markdown file, rename or move a heading/section, update cross-document links, validate links, install or update vendored packages, or extract a tree-shaken markdown slice for LLM context.
---

# Substrate CLI

Substrate is a CLI for working with a corpus of plain markdown files that are
linked together as a semantic knowledge graph. The corpus root is the
directory that contains `substrate.json`. Vendored dependencies live under
`substrate/` next to that manifest.

The CLI exists so that **you never edit markdown links by hand** when a file
or heading moves: every operation that could break a link is implemented as a
single subcommand that updates the disk *and* every reference in the project
atomically. Prefer these commands over hand-edits, multi-step bash, or
search-and-replace.

## When to reach for this skill

Reach for `substrate` whenever the user asks you to:

- Rename a markdown file in a Substrate project.
- Rename a heading (and have inbound `#anchor` links keep working).
- Move a section from one document to another.
- Check that every link in the corpus resolves.
- Install, update, or publish a Substrate package.
- Produce a focused, self-contained markdown slice from a large corpus
  ("give me just the part of these docs an LLM needs to answer X").
- Count words, links, or sections in a markdown file.

Detect whether the project is a Substrate corpus by looking for
`substrate.json` walking up from the current directory. If none is found,
this CLI doesn't apply.

## Refactoring — `substrate refactor rename`

**This is the most important command in this skill.** Whenever a file or
heading moves, use it instead of editing files manually. It rewrites every
inline link `[text](path)` and every reference-style definition
`[id]: path` in every `.md` file in the project — you do not have to find
them yourself.

The operation performed is determined by the **shape** of the two
arguments. There is only one command; three different operations:

### Rename a file

```bash
substrate refactor rename specs/old-name.md specs/new-name.md
```

Both arguments are plain file paths. Renames the file on disk and rewrites
every link that pointed at the old path. Use whenever a `.md` file moves
or is renamed.

### Rename a section (same file)

```bash
substrate refactor rename specs/foo.md#old-anchor specs/foo.md#new-anchor
```

Both arguments are in the same file but with different anchors. Changes the
heading text in the file, then rewrites every inbound `#anchor` reference.

The new heading text is **derived from the anchor slug**: hyphens become
spaces and the first letter is capitalised. `my-new-section` becomes the
heading `# My new section`. If the user gives you the *heading text they
want* rather than a slug, convert it to a slug first
(`Decision Table` → `decision-table`).

### Move a section between files

```bash
# Interactive — opens a TTY picker for the insertion point in b.md.
substrate refactor rename specs/a.md#section specs/b.md

# Non-interactive — appends the section after #parent in b.md.
substrate refactor rename specs/a.md#section specs/b.md#parent
```

`from` has an anchor; `to` is a different file. Removes the section and
all its sub-sections from the source file, then appends them in the
target file. Every reference to any of the moved anchors is rewritten to
point at the target file. Heading depth is **not** adjusted.

When you are running unattended (no TTY), always specify the parent
anchor in the `to` argument — the interactive picker will refuse to run
and the command will fail.

### Failure modes worth anticipating

- **Anchor collision when moving.** If any moved heading slug already
  exists in the target file the command errors before making changes.
  Tell the user to rename the conflicting section first (with the
  section-rename form above), then retry the move.
- **Same anchor on both sides of a section rename.** If the new heading
  slugifies to the existing anchor (e.g. only capitalisation changed),
  the command errors with "nothing to do." Pick a textually different
  heading.
- **File rename with anchors.** Mixing file and anchor shapes — e.g.
  `rename a.md b.md#x` — is rejected. Decide whether you are renaming a
  file or moving a section.

### What does *not* count as a refactor

These do not have dedicated commands; do them manually and then run
`substrate validate`:

- Splitting one large `.md` into several files.
- Merging several files into one.
- Renaming a directory (rename each file individually, or `git mv` plus
  hand-fixups + `substrate validate`).

`substrate validate` after any manual change is the safety net.

## Markdown management commands

### `substrate validate`

Walks every `.md` file in the corpus and reports unresolved links. Exits
non-zero on any broken link. Run it after any hand-edit that could move
content or change a heading; run it before publishing.

```bash
substrate validate
```

### `substrate context <file>[#section] ...`

Produces a single self-contained markdown document on stdout, tree-shaken
to the sections actually reachable from the supplied roots and rewritten
so cross-file links become in-document anchors. Use this whenever the
user wants to feed a slice of the corpus to an LLM as compact context.

```bash
# Default — tree-shake to just the sections needed.
substrate context specs/spec.md#decision-table > context.md

# Include the full file (still rewrites links).
substrate context --no-tree-shaking specs/spec.md > context.md

# Only the explicitly named roots; do not follow links.
substrate context --no-inline specs/a.md specs/b.md > context.md

# Pull in matching sections from a horizontal package via reverse traversal.
substrate context spec.md --horizontal horizontals/examples
```

If a file has a section whose anchor is `summary`, asking for the whole
file is silently rewritten to just that summary — author the `summary`
section deliberately when you want a compact synopsis.

### `substrate stats [file]`

Prints word count, line count, rough token estimate, link breakdown,
section count, and heading depth statistics. Reads stdin when no file is
supplied — useful for piping `substrate context` output:

```bash
substrate context spec.md | substrate stats
```

Use this to size a slice before sending it to an LLM.

### `substrate verify <file>`

Runs the full pipeline (parse → include → lint → references → typecheck
→ test) on a single file. Heavier than `validate`; reach for it when the
user wants the *language* checks, not just link resolution.

## Package commands

### `substrate init`

Scaffolds a new Substrate package in the current directory. Prompts for
name, kind (`corpus` / `library` / `horizontal`), and version. Writes
`substrate.json` and creates `substrate/`. Pass `-y` / `--yes` to
accept all defaults.

Aborts without writing anything if `substrate.json` already exists.

`substrate init` also drops AI-assistant instructions into the project —
this skill at `.claude/skills/substrate-cli/SKILL.md` and a GitHub Copilot
equivalent at `.github/instructions/substrate-cli.instructions.md` — so
that any LLM working in the project knows about the CLI.

### `substrate install`

Resolves every dependency in `substrate.json` and vendors it under
`substrate/`. Writes (or honours) `substrate-lock.json`. Idempotent.

Pass `-f` / `--force` to reinstall every dependency even when the
lockfile says it is already present and intact — useful after local
edits to vendored content or an interrupted install.

Running `substrate install` also refreshes the bundled AI-assistant
instructions in the project (`.claude/skills/substrate-cli/SKILL.md` and
`.github/instructions/substrate-cli.instructions.md`). Treat those files
as **managed by the CLI** — they are overwritten on every install. If a
user has hand-edited them, save their changes elsewhere or rename the
file before running `install`.

### `substrate update [package]`

Re-resolves one dependency (or every dependency) against the latest
matching git tag, updates `substrate-lock.json`, and refreshes the vendored
tree.

### `substrate publish`

Tags the current `package.version` and pushes the tag. Refuses to
publish a `corpus`. Refuses to publish a dirty working tree. Runs
`validate` first and aborts on any failure.

## Conventions when you generate substrate commands

- Always use **forward slashes** in paths, even on Windows — the CLI is
  cross-platform and accepts them everywhere.
- Anchors use **GFM slug rules**: lowercase, alphanumerics and hyphens
  only, sequences of other characters collapsed to a single hyphen,
  duplicates within a file get `-2`, `-3`, … suffixes.
- The CLI mutates the working tree. Confirm with the user before
  running anything that mutates more than one file (refactors, install,
  update, publish) unless the user has already approved it.
- When a refactor errors, **do not fall back to a manual fix**.
  Surface the error to the user — the precondition (collision, identical
  anchor, missing section) is something the user should resolve, and
  hand-editing risks leaving the corpus in a half-renamed state.
- After any hand-edit you make to markdown, run `substrate validate`
  before reporting the task complete.
