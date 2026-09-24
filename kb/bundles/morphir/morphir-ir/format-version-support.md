---
type: Design Note
title: "Format-version support and revisions"
description: "How a Morphir IR reader states which format versions it reads, what a patch, minor and major revision may change, and where each binding publishes its table."
tags: [ir, ir-v4, versioning, format-version, mck]
status: draft
---

# Format-version support and revisions

A reader states what it reads as a support table: a union of intervals over release strings, in Maven-style interval
notation, with one canonical spelling. A patch changes nothing a reader can observe, so a table's ceilings sit on minor
boundaries. The reference table is `[3.0.0,3.2.0),[4.0.0,4.1.0)`. This page is the narrative home for that design. The
reasoning is in [decision 0016](/decisions/0016-support-tables-are-intervals-and-a-patch-changes-nothing-observable.md),
and the normative text is the format-version page of the specification. The v3 ceiling moved from `3.1.0` to `3.2.0`
when IR `3.1.0` was minted ([decision 0018](/decisions/0018-ir-3-1-adds-specs-and-v3-document-trees.md)).

## The revision promise

| Revision | May change |
| --- | --- |
| Patch | Nothing a reader can observe: prose, examples, kit cases pinning behaviour already required |
| Minor | What a reader accepts or emits, including closing an acceptance window |
| Major | Anything, including the reading of older documents |

A revision exists when the kit carries cases for it. Before the formal 4.0.0 release every change stays inside `4.0.0`.

## Support tables

```
[3.0.0,3.2.0),[4.0.0,4.1.0)
```

The grammar is small:

- A square bracket is an inclusive bound; a round bracket is an exclusive one.
- A comma between two intervals is union.
- `[a]` is exactly the release `a`.
- A missing bound means unbounded on that side, and the bracket beside an absent bound is written round.
- At least one of the two bounds is required, so `(,)` is not a table.
- The release grammar starts at major 3, so an absent lower bound reaches down to `3.0.0` and no further; `(,3.0.0)`
  contains no release and is not a table.
- A table needs one canonical spelling that parses back to itself, so a table whose intervals merge into an interval
  with neither bound is not a table either.

Membership is "inside any interval". The canonical spelling rewrites every interval as half-open `[a,b)` wherever a
bound can be advanced (`next(x.y.z)` is `x.y.(z+1)`), then sorts, merges, and drops whitespace. A patch component
already at `4294967295` cannot be advanced, so that bound keeps its original bracket; `next()` never carries into the
minor.

Three renderings exist for people; none is accepted as input:

| Style | Reads as |
| --- | --- |
| Cargo | `>=3.0.0, <3.2.0` and `>=4.0.0, <4.1.0` |
| Elm | `3.0.0 <= v < 3.2.0` and `4.0.0 <= v < 4.1.0` (an unbounded interval cannot be rendered) |
| Prose | `3.0.0 up to but not including 3.2.0, or 4.0.0 up to but not including 4.1.0` |

## Compatibility results

| Result | When |
| --- | --- |
| `supported` | The release is inside some interval of the table |
| `unsupported_format_version_major` | No interval touches the release's major |
| `unsupported_format_version_minor` | An interval touches its major, but none contains the release |

The last replaces `unsupported_format_version_revision`, because under the patch promise the mismatch is always the
minor.

## Where each binding publishes its table

Each binding declares its table where this table says.

| Binding | Table | Published |
| --- | --- | --- |
| Specification reference | `[3.0.0,3.2.0),[4.0.0,4.1.0)` | format-version page and corpus |
| morphir-typescript (`@finos/morphir-ir`) | `[4.0.0,4.1.0)` | adapter `formatVersions`; run report |
| morphir-rust (`morphir_core`) | `[3.0.0,3.2.0),[4.0.0,4.1.0)` | adapter `formatVersions`; run report |
| morphir-ui | `[3.0.0,3.1.0),[4.0.0,4.1.0)`, until it adopts `3.1.0` | README |

The `mck` driver refuses a non-canonical `formatVersions`, prints the table in prose at the head of a run, and writes the
canonical string into the report.

## Unresolved

- Minting the first minor after 4.0.0 is released: which kit cases move, how every binding's ceiling advances in one
  change, and whether the legacy-spelling window (bead `morphir-ir-v4-stabilize.19`) is the whole of `4.1.0` or one
  part of it.
- Which of morphir-scala and morphir-elm adopts the contract first, and whether either needs a table narrower than the
  reference.
