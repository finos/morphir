---
name: kb
description: "Manages the Morphir knowledge base under kb/ — OKF bundles and concept documents. Use when adding content to a bundle, creating a new bundle, checking the knowledge base for conformance or provenance drift, building or querying its SQLite index, managing intent through its lifecycle, recording or reading architectural decisions as Decision Records, or navigating, searching and listing its bundles, concepts and links."
allowed-tools: Bash(morphir kb *), Bash(cat *), Bash(ls *), Bash(find *), Bash(git *), Read, Edit, Write
metadata:
  version: 0.1.0
  lineage: descends from the morphir-scala kb skill 0.7.0, retargeted at the morphir CLI
---

# kb — Morphir Knowledge Base Assistant

Manages `kb/`, the Open Knowledge Format knowledge base. Bundles live under `kb/bundles/`, optionally grouped a level
deeper. [kb/AGENTS.md](../../../kb/AGENTS.md) is the source of truth for the conventions; this skill automates the
mechanical parts of following them.

## The `morphir kb` command

Everything runs through the `kb` subcommand of the Morphir CLI. It takes the same subcommands, flags, defaults,
JSON shapes and exit codes as the Scala `kb` tool from morphir-scala, so a playbook written against that tool runs
here. Where the reference implementation was wrong it is corrected rather than reproduced — a filter you pass is a
filter that applies, and `--json` means JSON.

```bash
morphir kb list
```

```bash
morphir kb check --verbose
```

**Every command accepts `--json`.** Progress output goes to stderr, so `--json` on stdout is clean and pipeable —
prefer it when you need to consume the result rather than read it.

Full flag reference: → [references/commands.md](references/commands.md)

| Command | Does |
| ------- | ---- |
| `list` | Bundles and their concept counts; `--bundle X` lists that bundle's concepts |
| `show --path /x.md` | One document: frontmatter, outbound links, heading outline |
| `search --query X` | Search titles, descriptions, tags and paths; `--body` to include prose |
| `check` | Conformance and provenance findings; non-zero exit on errors |
| `index` | Builds the SQLite index; `--status` reports its freshness |
| `refresh` | Both kinds of derived state; narrow with `refresh markdown` / `refresh db` |
| `query --sql` | Read-only SQL over that index |
| `sync …` | Mirroring an upstream repository into a bundle — `status`, `pull`, `push`, `diff` |
| `intent …` | Intent lifecycle — `new`, `list`, `show`, the transition verbs, `check` |
| `decision …` | Decision Records — `list`, `show` |
| `new-bundle` | Scaffolds a bundle with `index.md` and `log.md` |
| `add-concept` | Scaffolds a concept and wires it into the index and log |

## When to use what

**Adding content to an existing bundle.** Run `add-concept` to create the file and wire it up, then write the body
yourself. The scaffold deliberately leaves a `TODO` comment rather than plausible-looking prose.

→ [references/authoring.md](references/authoring.md) before writing the body.

**Writing or reviewing prose.** Every concept body is written in one of three registers, chosen by its `type:`.
The style cards are tool-neutral and live at [`styles/`](styles/); `voice.md` there applies to all registers and
includes the banned-pattern list (no em-dashes, no AI filler), `diagrams.md` says when a Mermaid diagram or SVG
should replace prose narration of a flow or structure, and `altitude.md` sizes documents to capability stories:
one narrative-home Design Note per capability in flight, with every fine-grained concept reachable from it.

| `type:` | Register | Card |
| ------- | -------- | ---- |
| Playbook, tutorial, orientation, guidance | article | `styles/article.md` |
| Design Note, Decision Record, Intent, synthesis | white-paper | `styles/whitepaper.md` |
| Reference, Specification Section, Glossary, Data Dictionary, version-pinned notes | reference | `styles/reference.md` |

Delegate drafting to the `kb-writer` subagent and review to the `kb-reviewer` subagent
(`.claude/agents/kb-writer.md`, `kb-reviewer.md`), naming the target file and register in the dispatch. Writing
inline is fine for small edits; still apply the cards. Style applies to new and touched content only; do not
sweep existing prose.

**Creating a bundle.** Run `new-bundle`, then add it to the Bundles table in `kb/README.md` and to the group's
`README.md` if it is in a group. The command reminds you; it does not edit those files, because their wording is a
judgement call.

**Checking the knowledge base.** Run `check`. It reports structural problems (missing `type`, broken links,
unindexed concepts, frontmatter that does not parse) and provenance drift (commit-pinned sources whose reference
checkout has moved on). Nothing here touches the network.

→ [references/checks.md](references/checks.md) for the catalogue and how to fix each finding.

**Searching and locating.** `search` scans the markdown and is always current. For anything heavier — full-text
search over bodies, "what links here", orphaned concepts, tag or provenance distributions — build the SQLite index
once and query it.

```bash
morphir kb index
```

```bash
morphir kb search --query "entry point" --index
```

The index is derived state under `.dev/kb/index.db`, gitignored, and rebuilt from the markdown. It has no automatic
invalidation — `morphir kb index --status` lists files changed since the last build.

**Keeping derived state honest.** `morphir kb refresh` does both halves in one pass: it rewrites index bullets that
have drifted from their concept's `description`, then rebuilds the SQLite index if anything changed.

```bash
morphir kb refresh --dry-run
```

Narrow it when you only want one half — `morphir kb refresh markdown` or `morphir kb refresh db`, equivalently
`--no-db` and `--no-markdown`. Reach for it after editing descriptions or adding concepts, and before relying on a
query. `--add-missing` also appends entries for unindexed concepts, which is opt-in because it has to pick a section.

→ [references/index-db.md](references/index-db.md) for the schema, the views, and worked queries.

**Managing intent.** Features, enhancements and bugs are recorded as prose in the intent bundle, with a lifecycle
whose obligations are enforced — most importantly, releasing requires linking the Capability it produced.

→ [kb/CONTEXT.md](../../../kb/CONTEXT.md) for the vocabulary — states, kinds, and what each obliges;
[references/commands.md](references/commands.md) for flags.

**Recording a decision.** Architectural decisions are the knowledge base's third register, alongside Intent and
Capability: past-tense, immutable, and **superseded rather than edited**. `morphir kb decision list` and
`morphir kb decision show` read them; `morphir kb check` validates their supersession links.

→ [references/decisions.md](references/decisions.md) for the frontmatter, the checks and how to supersede one.

**Mirroring an upstream repository.** A bundle may declare a `sync.yaml` and carry upstream's own files rather than
a paraphrase of them. Markdown lands as concepts with an injected, fenced block of kb-owned frontmatter; everything
else lands as byte-identical assets. `morphir kb sync push` deletes exactly that fenced region, so what goes back
upstream is what came from it.

```bash
morphir kb sync status
```

→ [references/sync.md](references/sync.md) for the manifest, the lockfile and the state model.

**Finding divergence in the *content*.** `check` finds mechanical inconsistency. Contradictions between what two
concepts assert — the thing that actually matters in a knowledge base — cannot be detected by a script.

→ [references/divergence.md](references/divergence.md) for that procedure.

## Rules that the tooling assumes

- A **bundle root** is a directory whose `index.md` carries `okf_version`. That is how bundles are discovered.
- Only `index.md` and `log.md` are reserved. Every other `.md` file inside a bundle is a concept and needs `type:`.
  The reservation stops at a mirror boundary — inside a vendored subtree those names are upstream's own files.
- A **grouping directory** gets a `README.md` and never an `index.md`. `README.md` inside a bundle is an error.
- Sub-directory `index.md` files carry **no frontmatter**.
- Index bullets mirror the target concept's `description`. Changing one means changing the other.

## Where the implementation lives

The `morphir kb` command is implemented in Rust, in the `morphir-okf` (format model and parsing) and `morphir-kb`
(knowledge-base operations) crates under `ecosystem/morphir-rust/crates/`, wired into the CLI in `crates/morphir`.
Develop and test it there with `cargo test`; this skill only documents the command surface.
