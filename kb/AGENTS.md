# AI Agent Guidelines for the Morphir Knowledge Base (`kb/`)

See the root [AGENTS.md](../AGENTS.md) for project-wide guidelines. This file covers everything specific to `kb/` and
is the primary source of truth for authoring and consuming knowledge bundles here.

## What lives here

`kb/` is the knowledge base root. Bundles land under `kb/bundles/`, one directory per bundle. Nothing under `kb/` is
compiled, referenced by the Cargo workspaces or the Docusaurus site, or shipped as part of a published artifact — it
is documentation-as-data, read by humans and agents, operated by the `morphir kb` CLI.

Bundles conform to the **Open Knowledge Format (OKF)**, currently **v0.2**:

- Spec: <https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md>
- OKF overview: <https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf>

When this file and the spec disagree, the spec wins — and the disagreement is a bug in this file worth fixing.

## Bundle structure

```
kb/bundles/<bundle-slug>/
  index.md                 # Bundle root index; the only file that may carry `okf_version`
  log.md                   # Optional update history
  <concept>.md             # Concept document at bundle root
  <subdirectory>/
    index.md               # Directory index (no frontmatter)
    <concept>.md
  sync.yaml                # Optional: what this bundle mirrors from an upstream repository
  sync.lock.yaml           # Generated companion to sync.yaml; never hand-edited
  sources/                 # The mirrored subtree, named by `root:` in sync.yaml
```

- `<bundle-slug>` is lower-case kebab-case, matching the slug convention used elsewhere in this repo.
- Every `.md` file that is not `index.md` or `log.md` is a **concept document**.
- `index.md` and `log.md` are reserved filenames outside a mirrored subtree. Do not use them for concepts.
- Subdirectories nest freely; depth is a modelling choice, not a spec constraint.

## Grouping directories

Related bundles may be grouped one level deeper — `kb/bundles/<group>/<bundle-slug>/`. Two rules keep a grouping
directory from being mistaken for a bundle:

- **A grouping directory gets a `README.md`, never an `index.md`.** An `index.md` is the marker of a bundle root; use
  it there and a consumer will try to walk the group as a bundle.
- **Never put a `README.md` *inside* a bundle.** Within a bundle, only `index.md` and `log.md` are reserved — every
  other `.md` file is a concept document, so a `README.md` there would be parsed as a concept missing its required
  `type` field. Bundle-level orientation belongs in `index.md`.

A group's `README.md` should list its bundles and record any constraints shared across them (which upstream sources
are authoritative, which are off-limits). Bundles in the same grouping directory are **co-located**. A Glossary or
Data Dictionary in one of them is a valid term catalog for the others. See [Glossaries and data dictionaries](#glossaries-and-data-dictionaries).

## Mirrored bundles

A bundle may carry a `sync.yaml` naming an upstream repository and the paths it mirrors. Everything under the
subtree that manifest's `root:` names is upstream's material, vendored here so it can be read exactly, diffed, and
edited with the edits sent back. Use it when a paraphrase will not do; use `sources` (below) when it will.

- **Markdown in the mirror is a concept document**, but its frontmatter is upstream's. The knowledge base owns one
  fenced `# kb:begin` … `# kb:end` region inside it, holding the `type` OKF requires and the upstream path.
  `morphir kb sync push` deletes exactly that region to recover upstream's bytes, so do not edit inside the fence by
  hand, and do not reformat anything outside it.
- **The fence is generated from `sync.yaml`.** `morphir kb sync pull` rewrites it whenever the manifest implies
  different keys, so an edit to `type`, `title`, `description` or `kb_upstream` there will not survive; change the
  manifest instead. A mirrored document is typed by what it *is* — `Decision Source`, not `Decision Record` — because
  the registers below discover their records by `type:` wherever those sit, and upstream's file would be judged
  against a schema it was never written to. `morphir kb sync` refuses a `type_map` that names a register-owned type.
- **Everything that is not markdown is an asset** — schemas, fixtures, `.mdx` pages, sidebar descriptors. Assets are
  mirrored byte-for-byte and tracked, but never parsed, so they carry no frontmatter and need no `type`.
- **`index.md` and `log.md` are reserved only outside the mirror.** Inside it those names belong to upstream,
  frontmatter and all, and the files are treated as ordinary concepts.
- **The bundle-root `index.md` carries `sync: true`.** That is the marker the `morphir kb sync` commands discover the
  bundle by; the `sync.yaml` itself is what makes the subtree vendored.
- `sync.lock.yaml` is generated: it records the upstream commit the import came from and, per file, a hash of its
  upstream form. Never edit it by hand, and let `morphir kb sync pull` regenerate the index region it maintains.

Mirrored documents are held to a looser standard than authored ones — checks that would judge upstream's frontmatter
or upstream's link rot are relaxed — so review a mirror by reading its diff against upstream, not by trusting a
clean `morphir kb check`.

→ the `kb` skill's [sync reference](../.claude/skills/kb/references/sync.md) for the manifest format and commands.

## Concept documents

Every concept document starts with a YAML frontmatter block.

### Writing style

- Use concise, plain language and short paragraphs.
- Use bullets or numbered steps when listing three or more items.
- Use tables for comparisons that repeat the same fields.
- Avoid repetitive framing and exhaustive prose when a link provides the detail.
- Write each `description` as one short, standalone sentence.
- Follow the style cards in [`.claude/skills/kb/styles/`](../.claude/skills/kb/styles/README.md): `voice.md`,
  `diagrams.md`, and `altitude.md` for every document, plus the register card (`article.md`, `whitepaper.md`,
  or `reference.md`) that the document's `type` selects. The cards apply to new and touched content; do not
  sweep existing prose. `voice.md` sets the audience: junior to early mid-level. Supply background on the
  page, as a summary, as a Glossary or Data Dictionary link (same bundle or co-located sibling is enough to
  skip an inline sidebar), as another kb link, or as an external link (least preferred).
- Prefer a captioned Mermaid diagram (or an SVG asset) over prose narration when the subject is a flow,
  lifecycle, structure, or state machine.
- Size documents to capability stories (`altitude.md`): each capability in flight has one narrative home, a
  Design Note that tells its accurate story and links its research, constraints, open questions, and intents.
  A fine-grained concept must be reachable from a narrative home; an intent must read as a feature definition
  on its own. Split a document only for reuse, an independent version pin, a register boundary, a Glossary, or
  a Data Dictionary, never merely for length.

### Required

- `type` — short string naming the kind of concept (`Playbook`, `Glossary`, `Data Dictionary`, `Design Note`, …).
  This is the only universally required field; consumers route, filter, and present on it. Type values are not
  centrally registered, so pick self-explanatory names and reuse the ones already present in the bundle rather than
  inventing near-synonyms.

  Two type values carry extra validation from this repository's tooling rather than from OKF: `Intent` and
  `Decision Record`. See [Registers](#registers) below.

### Recommended

- `title` — human-readable display name. Consumers may derive one from the filename if omitted; supply it anyway.
- `description` — one short sentence. Index generators and search snippets pull from this, so write it to stand alone.
- `resource` — URI uniquely identifying the underlying asset. Omit for abstract concepts.
- `tags` — YAML list of short strings for cross-cutting categorization.

### Optional families

- **Provenance** — `sources`, a list of the materials the concept derives from. Each entry requires `resource` (a
  concrete artifact URL or scope descriptor) and may carry `id` (stable key for per-claim attribution), `title`,
  `author`, `usage_count`, `last_modified`.
- **Trust** — `generated` (`by` actor, `at` ISO 8601 datetime) and `verified` (a single mapping or a list of
  verification events, each with `by` and `at`).
- **Lifecycle** — `status` (`draft`, `stable` (default), or `deprecated`) and `stale_after` (`YYYY-MM-DD`).
- **Computation** — for `type: Attested Computation` only: `runtime` (required), `parameters` (typed named holes of
  `{ name, type, required }`), `computation`, `executor` (`resource`, `receipt`), `attester`.

Example:

```markdown
---
type: Playbook
title: Publishing a Morphir IR from Elm sources
description: End-to-end steps for turning an Elm model into a published Morphir IR artifact.
tags: [elm, ir, publishing]
status: stable
generated:
  by: human:damianreeves
  at: 2026-07-28T00:00:00Z
---

Prose body starts here.
```

### Actors

Actor strings follow a fixed convention: `<producer>/<version>` for agents, `human:<id>` for people, and
`process:<id>` for automated processes. Use it in `generated.by` and `verified.by`.

## Registers

Three concept types carry a schema and validation beyond OKF's, because they answer three different questions about
the same work. Picking the wrong one is the most common modelling mistake here.

| Register | `type` | Tense | Lifecycle | Answers |
| -------- | ------ | ----- | --------- | ------- |
| Intent | `Intent` | future | yes | should we do this |
| Capability | `Capability` | present | no | what does the system do |
| Decision Record | `Decision Record` | past | terminal only | why is it shaped this way |

- **Intent** lives in the bundle whose index carries `intent: true`, is numbered `NNNN-slug.md`, and its lifecycle
  obligations are enforced by `morphir kb intent check` — most importantly, releasing requires linking the Capability
  it produced.
- **Capability** is plain prose with no extra schema. It is either true or stale.
- **Decision Record** is numbered `NNNN-slug.md` in a `decisions/` directory, carries `state`, `decided` and
  `supersedes`/`superseded_by`, and is validated by `morphir kb check`. **It is immutable**: superseded by a later
  record rather than edited, because its value is the reasoning available at the time.

The distinction that most often needs care is **Decision Record vs Design Note**. A Design Note is updated as
understanding improves — that is what makes it useful. A Decision Record must not be. If the document should change
when you learn more, it is a Design Note.

Full guidance: [`.claude/skills/kb/references/decisions.md`](../.claude/skills/kb/references/decisions.md). The
reasoning behind the third register is recorded in the morphir-scala knowledge base, where these conventions were
first worked out (`ecosystem/morphir-scala/kb/bundles/morphir/morphir-scala/decisions/0004-decision-records-are-a-third-register.md`).

## Glossaries and data dictionaries

A **Glossary** (`type: Glossary`) is the bundle's word list: term, then a short meaning. A **Data Dictionary**
(`type: Data Dictionary`) is the bundle's catalog of named fields, types, flags, or columns. Both use the
reference register. Prefer `glossary.md` and `data-dictionary.md` at the bundle root.

They exist so a Design Note can keep moving. Link the term instead of pausing for a sidebar definition. That
is the right call when the catalog is in the same bundle, or in a co-located sibling (another bundle under the
same grouping directory). Linking a glossary farther away is still a kb link; it does not replace naming the
term on first use.

Do not copy glossary entries back onto the narrative page. [kb/CONTEXT.md](./CONTEXT.md) is the vocabulary of
`kb/` itself. It is not a bundle concept. Bundle glossaries do not repeat it.

## Cross-linking

- Link concepts with plain markdown links. Prefer **bundle-relative** paths beginning with `/` — they survive file
  moves better than relative paths, which are also permitted. Absolute URLs are fine for external material.
- The meaning of a link — dependency, inheritance, join, "see also" — comes from the surrounding prose, not from the
  link itself. Say what the relationship is.
- Broken links are legitimate *to a consumer*: they mark not-yet-written knowledge, and nothing reading a bundle
  should fail because of one. Do not delete a link merely because its target does not exist yet.
- `morphir kb check` is a producer-side linter, not a consumer, and it reports a dangling link as an **error** —
  inside one repository it is nearly always a typo, and the cost of the occasional false positive is lower than the
  cost of silent rot. Pass `--allow-dangling` to restore OKF's lenient stance where a knowledge base genuinely links
  forward to unwritten work.

## Index files

`index.md` supports progressive disclosure — it lets a reader or agent see what a directory holds before opening
anything in it.

- Frontmatter appears **only** in the bundle-root `index.md`, and carries `okf_version: "0.2"`. Every other
  `index.md` has no frontmatter at all.
- The body is one or more headed sections of bulleted entries:

```markdown
## Playbooks

* [Publishing a Morphir IR from Elm sources](/publishing-ir.md) - End-to-end steps for turning an Elm model into a published Morphir IR artifact.
```

- Entry descriptions should match the target concept's `description` frontmatter. When you change a `description`,
  update the index entries that mirror it.

## Log files

`log.md` is optional and may appear at any level of the hierarchy.

- Date headings use ISO 8601 `YYYY-MM-DD`, newest first.
- Entries are prose bullets, conventionally prefixed `**Update**`, `**Creation**`, or `**Deprecation**` — suggested
  conventions, not requirements.

```markdown
## 2026-07-28
* **Creation**: Added the [IR publishing playbook](/publishing-ir.md).
```

## Adding a new bundle

1. Create `kb/bundles/<bundle-slug>/` — or `kb/bundles/<group>/<bundle-slug>/` — with a kebab-case slug.
2. Write `index.md` with `okf_version: "0.2"` frontmatter and a body listing the bundle's concepts.
3. Add concept documents. Give every one a `type`; give nearly every one a `title` and `description`.
4. Add `log.md` if the bundle's history is worth tracking.
5. Add the bundle to the **Bundles** table in [README.md](./README.md), using the same description as its `index.md`,
   and to the group's `README.md` if it is in a group.
6. Re-read the [spec](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) if you are doing
   anything the sections above do not cover — this file is a working summary, not a replacement.

`morphir kb new-bundle` scaffolds steps 1, 2 and 4 and prints a reminder for step 5.

## Consuming a bundle

Agents should discover concepts by reading `index.md` first, route on `type`, follow cross-links to build up domain
understanding, and check `status` and `stale_after` before treating content as current. Content marked `draft` or past
its `stale_after` date is a lead, not a fact. For `Attested Computation` concepts, bind parameters to the sanctioned
computation and submit it to the declared executor rather than reimplementing the logic — the separation between
agent-authored values and machine-sanctioned logic is the point.

## House rules

- Bundle content is knowledge, not build input. Do not wire `kb/` into the Cargo workspaces, the Docusaurus site, or
  any CI artifact build.
- Do not put secrets, credentials, or customer data in a bundle. These files are public.
- Scratch work, spikes, and planning artifacts belong in `.dev/` (gitignored), not in `kb/`. A bundle holds knowledge
  that has settled.
- The CLA and no-tool-attribution rules in the root [AGENTS.md](../AGENTS.md) apply to changes here exactly as they do
  to code.
