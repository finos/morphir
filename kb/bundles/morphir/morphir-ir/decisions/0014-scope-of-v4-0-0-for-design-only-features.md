---
type: Decision Record
title: Scope of v4.0.0 for the design-only features
description: "Layered decorations, $ref deduplication and the session journal are out of IR v4.0.0; $meta is reserved and ignored by readers; the books fixture migrates to the canonical product-ID spelling with no legacy-name compatibility rule."
state: Accepted
decided: 2026-09-04
tags: [ir, ir-v4, scope, decorations, document-tree, mck]
status: draft
---

# Scope of v4.0.0 for the design-only features

Four features exist only in the design documents under `docs/design/draft/ir/`. This record settles each for
v4.0.0, and closes the legacy-name question GitHub issue #793 raised.

| Feature | v4.0.0 | Rule |
| ------- | ------ | ---- |
| Layered decorations (`deco/` tree) | Out | Returns as its own design with a specified merge algebra the kit can pin |
| `$meta` file-level provenance | Out, name reserved | A v4 reader treats a top-level `$meta` member in a document-tree file as reserved and ignores it; it never reports `unknown_member` for it |
| `$ref` file-local deduplication | Out, not reserved | Same reasoning as the YAML profile's ban on anchors: a reader must not need a resolution pass to know what a node means |
| `session.jsonl` transaction journal | Out of the IR | Daemon workspace state, not part of a distribution; the document-tree page says so |
| `DocumentLiteral` | In | See [decision 0013](/decisions/0013-document-literal-is-in-v4-with-a-raw-payload.md) |

**GitHub #793.** `website/static/ir/examples/v4/books-and-records-example.json` migrates to the canonical `product-ID`
spelling. No legacy-name compatibility rule is added; the retired parenthesized encoding stays rejected, as kit case
`names-0003` pins.

| Option | Outcome | Why |
| ------ | ------- | --- |
| Decide each feature now, most out | Chosen | The kit's coverage rule cannot wait on features with no specification; reserving `$meta` costs nothing |
| Ship all five in 4.0.0 | Rejected | Decorations have no merge specification; `$ref` needs a resolution pass; the journal is not a value |
| Legacy-name compatibility for the books fixture | Rejected | Decision 0011 forces a rewrite of that file anyway; a compatibility rule would weaken the canonical parser for one fixture |

## Why

The register in [IR v4 stabilization](/ir-v4-stabilization.md) lists these as "present in the design, absent from
the specification and the schemas". Each was weighed on one question: can a kit case be written for it today?

Decorations describe cross-layer deep merge with higher-priority layers winning, in one sentence, and nothing more
specific exists. Annotations already carry semantic metadata on specifications inside the IR. `$ref` trades a
resolution pass for size; compression at the transport layer gives the size back without changing what a node
means. The journal records how a distribution came to be, which is tooling state. `$meta` is cheap to reserve and
would be expensive to reclaim once a tool used the name.

## Consequences

1. The design pages for decorations, `$meta`, `$ref`, and the journal gain a status line pointing at this record.
2. The document-tree specification page states that `session.jsonl` is not part of a distribution and that `$meta`
   is reserved.
3. The reference reader and every mirror ignore a top-level `$meta` member in document-tree files; the kit adds a
   `document-tree` case with one.
4. The books example is rewritten for `product-ID` and for `morphir/SDK` in one change; GitHub #793 closes with a
   pointer here.

## Revisit when

- A decorations design arrives with a merge specification.
- A frontend needs provenance in the tree, at which point `$meta` is specified rather than merely reserved.
