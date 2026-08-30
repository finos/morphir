# Morphir Knowledge Base

This directory is the root of the Morphir knowledge base: a collection of **knowledge bundles** that capture
durable, reusable knowledge about Morphir, this repository, and the domains it serves, in a form that both humans
and agents can navigate. This is finos/morphir, the ecosystem umbrella repository — documentation, the Rust CLI and
the language implementations vendored under `ecosystem/` — so the knowledge here spans the
ecosystem rather than a single implementation.

Bundles here conform to the **Open Knowledge Format (OKF)**, an open specification for expressing knowledge as a
directory tree of markdown concept documents with YAML frontmatter.

- Open Knowledge Format: <https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf>
- OKF specification (SPEC.md): <https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md>
- Knowledge Catalog project: <https://github.com/GoogleCloudPlatform/knowledge-catalog>

Bundles currently target **OKF v0.2**.

## Layout

```
kb/
├── README.md      # This file — what the knowledge base is, and what's in it
├── AGENTS.md      # Primary guidance for agents authoring or consuming bundles
├── CLAUDE.md      # Claude-specific pointer to AGENTS.md
├── CONTEXT.md     # The vocabulary of kb/ itself
└── bundles/       # Knowledge bundles, optionally grouped by subject
    └── <group>/           # Grouping directory — README.md only, never index.md
        └── <bundle-slug>/
            ├── index.md     # Bundle root index; carries `okf_version`
            ├── log.md       # Optional update history
            └── <concept>.md # Concept documents
```

Each bundle is a self-contained OKF bundle rooted at its own directory. Bundle directory names are lower-case
kebab-case slugs, consistent with the folder-naming convention used elsewhere in this repo. Bundles may sit directly
under `bundles/` or be grouped one level deeper by subject.

## Bundles

| Bundle | Description |
| ------ | ----------- |
| [morphir/morphir-cli](bundles/morphir/morphir-cli/index.md) | The Rust morphir command line: its commands, behavior and design, as shipped from finos/morphir. |
| [morphir/morphir-ir](bundles/morphir/morphir-ir/index.md) | The Morphir IR: its data model, naming, canonical serialization and distribution formats. |

`morphir kb new-bundle` scaffolds a bundle and reminds you to add its row here — the wording of the row is a
judgement call, so the command does not write it for you.

## Tooling

The knowledge base is operated by the `morphir kb` subcommand of the Morphir CLI (`crates/morphir`):

```bash
morphir kb list
morphir kb check
```

The `kb` skill at [`.claude/skills/kb/SKILL.md`](../.claude/skills/kb/SKILL.md) wraps the CLI for agents: it says
which command fits which task, routes prose to the right register, and carries the full flag and check references.

## Working in this directory

Read [AGENTS.md](./AGENTS.md) before authoring or editing a bundle. It is the source of truth for the OKF
conventions this knowledge base follows — reserved filenames, required frontmatter, cross-linking, and the checklist
for adding a new bundle.

Project-wide guidelines live in the root [AGENTS.md](../AGENTS.md).
