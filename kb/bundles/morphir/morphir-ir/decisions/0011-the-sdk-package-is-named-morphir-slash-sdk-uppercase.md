---
type: Decision Record
title: The SDK package is named morphir/SDK
description: "The Morphir SDK's canonical v4 package name is morphir/SDK, because morphir-elm's Path.fromString splits SDK into single-letter words that decision 0001 decodes as an initialism; every morphir/sdk spelling in published v4 material is a different name and is rewritten."
state: Accepted
decided: 2026-09-04
tags: [ir, ir-v4, naming, sdk, mck]
status: draft
---

# The SDK package is named morphir/SDK

The canonical v4 name of the Morphir SDK package is `morphir/SDK`. Its legacy array is
`[["morphir"], ["s", "d", "k"]]`, and its document-tree directory is `pkg/morphir/_sdk/`.

```yaml
morphir/SDK:basics#int        # the SDK
morphir/sdk:basics#int        # a different package whose second segment is the word "sdk"
```

| Option | Outcome | Why |
| ------ | ------- | --- |
| `morphir/SDK` | Chosen | It is what the v3 encoding decodes to under decision 0001 and what morphir-elm's `packageName` means |
| `morphir/sdk` | Rejected | Under decision 0001 it names a package whose second segment is a word; no v3 artifact ever encoded the SDK that way |
| Fold `sdk` and `SDK` together | Rejected | Reintroduces the case-insensitive identity decision 0001 rejected, and would equate `in-USD` with `in-usd` |

## Why

morphir-elm's `Name` module treats any run of single-letter words as an abbreviation, and `Morphir.IR.SDK.packageName`
is `Path.fromString "Morphir.SDK"`, which yields `[["morphir"], ["s", "d", "k"]]`. Every v3 distribution encodes the
SDK dependency with that array. [Decision 0001](/decisions/0001-name-canonicalization-and-initialism-encoding.md)
decodes a run of two or more single-letter words as one initialism, so the v4 canonical spelling is `morphir/SDK`,
and the kit's active case `names-0004` already pins it.

Every published v4 example, the v4 specification pages, the specification draft, and the design documents write
`morphir/sdk`. They predate decision 0001, when names had no case, and were never updated. Under the decided grammar
that spelling is a different package, so the examples and the kit disagreed about which package the SDK is.

## Consequences

1. Every `morphir/sdk` in `website/static/ir/examples/v4/`, `docs/spec/ir/schemas/v4/`, `docs/spec/draft/`, and
   `docs/design/draft/ir/` becomes `morphir/SDK`. The rewrite is mechanical; once the reference binding resolves
   references, a stray `morphir/sdk:basics#int` resolves to nothing and fails the kit.
2. Kit `names-0006` becomes active with `morphir/SDK` canonical and the legacy array accepted. `morphir/sdk` is not
   rejected as a name, because it is a valid name for some other package; a new `distributions-0005` pins that the
   SDK dependency is keyed `morphir/SDK`.
3. The document-tree layout is unaffected: the escape already writes `pkg/morphir/_sdk/`, per the naming corpus.
4. The Scala and Rust follow-ups check their SDK package constants against `names-0006`.

## Revisit when

- Decision 0001 is superseded by its doubled-hyphen fallback, in which case the spelling becomes `morphir/--sdk`
  and this record's reasoning still holds.
