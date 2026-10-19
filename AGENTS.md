# Agent Instructions

General agent configuration, skills and the pre-push checks for this repository are in
[.github/AGENTS.md](.github/AGENTS.md). This file adds how work is tracked.

## Project-management skill

For initiative reports, progress, priorities, ready work, blockers, or organizing tracked work, read
[project-management](.github/skills/project-management/SKILL.md) and the references relevant to the request.
It covers beads, GitHub Issues, and mixed trackers, with progress bars, ratios, percentages, issue IDs, and
short summaries. Follow this repository's shared-tracker and document rules below.

The canonical skill ships in `.github/skills/project-management/`. Repository-local discovery links in
`.agents/skills/`, `.claude/skills/`, and `.grok/skills/` point to that same directory. Agents without native
skill discovery can read its `SKILL.md` directly. See the [skill catalog](.github/skills/README.md) for agent
paths, invocation, and reuse in other projects.

## Issue tracking with beads

Work is tracked with [beads](https://github.com/steveyegge/beads) (`bd`) in the **shared Morphir tracker**, not
in a database of this repository. The database lives in finos/morphir and syncs over its `refs/dolt/data` ref.
`.beads/config.yaml` points `bd` at it, so you do not need a finos/morphir checkout.

### Set up and sync

```shell
bd bootstrap          # first time on a machine: clones the shared database
bd dolt pull          # before you start work
bd dolt push          # after you change issues
```

The readable JSONL mirror on the `beads-sync` branch is published from finos/morphir, so pushing the database is
all you need to do here. Run `bd prime` for the full command reference.

### Worktrees

All worktrees use one database: `.beads/embeddeddolt` in the main checkout. A worktree finds it through the git
common directory, inside or outside the repository, so it needs no `.beads/redirect` file.

Run `bd bootstrap` in the main checkout before you open a worktree or start an agent session. Any `bd` command,
including the SessionStart `bd prime` hook, makes an empty local database when it finds none. An empty database in
the main checkout stops `bd bootstrap` ("Database already exists"), and a database in a worktree hides the shared
one.

```shell
mise run beads:check   # in any checkout or worktree: fails with the fix if the database is wrong
moonx scripts/beads-check.mbtx   # the same check without mise
```

To repair, move the empty `embeddeddolt` (and `backup`) directory aside and run `bd bootstrap` in the main
checkout again. Use `bd count` to make sure that a database is empty before you move it.

### Find this repository's work

Issues whose work happens here carry the label `repo:morphir-moonbit`:

```shell
bd ready --label repo:morphir-moonbit        # unblocked work
bd list --label repo:morphir-moonbit --all   # everything, including closed
bd show <id> --long                          # description, design, notes and comments
```

The work belongs to the Morphir ecosystem roadmap, epic `morphir-ukvn`, whose design is the approved roadmap spec.
The MoonBit work is Track 5, `morphir-ukvn.5`: its notes are the handoff, and the E0 spike report is the comment on
`morphir-ukvn.5.1`.

### Specs and plans are HTML documents

Use the [rich-designs skill](.agents/skills/rich-designs/SKILL.md) for creating, validating, preserving and landing
these artifacts. The installed [Anthropic frontend-design skill](.agents/skills/frontend-design/SKILL.md) supports
visual choices within the approved template and the user's brief; it does not override the template requirements.

Write superpowers specs, implementation plans and other documents a person reviews as HTML pages, not Markdown.
Thariq Shihipar of Anthropic's Claude Code team makes the case in "Using Claude Code: The Unreasonable
Effectiveness of HTML" (May 2026; examples at <https://thariqs.github.io/html-effectiveness>) and on the How I AI
episode "HTML is the new Markdown" (18 May 2026): a long Markdown plan gets skimmed, while an HTML page with a table
of contents, tables, collapsible sections and highlighted code gets read, questioned and corrected, and its explicit
structure lets an agent re-read and edit its own document reliably on every later pass. HTML costs more output
tokens per document, so the rule covers specs, plans and reports, not commit messages, issue text or notes.

- Start from [docs/templates/agent-document.html](docs/templates/agent-document.html). Keep its `<head>` and CSS as
  they are, so every document looks the same and the effort goes into content.
- Put code in `<pre><code class="language-moonbit">` (also `scheme`, `toml`, `json`, `bash`, `diff`). The template
  loads highlight.js 11.11.1 from cdnjs, pinned with integrity hashes, deferred and optional: online it highlights;
  offline the browser's cache serves it, or the page shows plain code blocks. Add no other external resource and no
  other script. Do not inline a highlighter or its CSS.
- Escape `<`, `>` and `&`. Give every section an `id` and list the sections in `nav.toc`.
- A plan has one `<section class="task" id="task-N">` with an `<h3>Task N: title</h3>` heading per task.
- Files: `.dev/beads-specs/<epic>.html` and `.dev/beads-plans/<plan-epic>.html`. `.dev/` is gitignored; beads is
  the record (next section).

### Specs, plans and ledgers live in beads

Superpowers specs, implementation plans and execution ledgers are stored in beads, not committed here. This
overrides the superpowers skill defaults for spec, plan and ledger location.

- **Spec:** draft it locally, then `mise run beads:plan -- spec <epic> <file.html>` stores it as the epic's design;
  the design holds text of any format. `mise run beads:plan -- spec <epic> --render` writes it back to
  `.dev/beads-specs/<epic>.md` whatever its format; rename the file to `.html` to open it.
- **Plan:** `mise run beads:plan -- import <plan.md> --parent <bead> --spec morphir-ukvn` turns it into a plan
  epic with one child bead per `### Task N`. The importer reads Markdown headings (`# title`, `### Task N: title`)
  and does not read HTML yet; until `bd-plan` in finos/morphir does, import an HTML plan through a Markdown outline
  with the same title and one `### Task N: <title>` per task, each body naming the task's files and tests and
  linking to the HTML plan's `#task-N` section. `mise run beads:plan -- render <plan-epic>` writes
  `.dev/beads-plans/<plan-epic>.md`; use that path as the plan file for every superpowers script, and never edit it.
- **Ledger:** `mise run beads:plan -- ledger <plan-epic> "<line>" --workspace <sdd-dir>` adds a ledger line to the
  plan epic as a comment and to the local `progress.md`.
- Close each task bead with its commit range and test result as the reason.

`beads:plan` fetches `bd-plan` from finos/morphir at a pinned commit and runs it with Bun.

For rich-design retrieval and reusable discoveries, use the
[beads companion skill](.agents/skills/beads-companion/SKILL.md). For example,
`moonx scripts/beads-companion.mbtx design export <bead>` restores HTML as `.html`, preserving embedded SVG.
`design inspect <bead>` gives compact context without printing the full document. The helper also supports
`design store`, `note` and `remember`; run it with `--help` for arguments. Sync tracker changes with `bd dolt push`.

### Working rules

- Commits use Conventional Commits, in plain English, with no AI attribution and no `Co-Authored-By` lines.
- Merges, releases and anything irreversible wait for the maintainer's approval unless a beads memory records it
  (`bd memories approval`).
