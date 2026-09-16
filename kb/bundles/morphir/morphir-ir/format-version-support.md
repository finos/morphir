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
boundaries. The reference table is `[3.0.0,3.1.0),[4.0.0,4.1.0)`. This page is the narrative home for that design; the
reasoning is in [decision 0016](/decisions/0016-support-tables-are-intervals-and-a-patch-changes-nothing-observable.md)
and the normative text is the format-version page of the specification.

## The revision promise

| Revision | May change |
| --- | --- |
| Patch | Nothing a reader can observe: prose, examples, kit cases pinning behaviour already required |
| Minor | What a reader accepts or emits, including closing an acceptance window |
| Major | Anything, including the reading of older documents |

A revision exists when the kit carries cases for it. Before the formal 4.0.0 release every change stays inside `4.0.0`.

## Support tables

```
[3.0.0,3.1.0),[4.0.0,4.1.0)
```

Square brackets are inclusive, round brackets exclusive, a comma between intervals is union, `[a]` is exactly `a`, and a
missing bound is unbounded on that side. Membership is "inside any interval". The canonical spelling rewrites every
interval as half-open `[a,b)` where a bound can be advanced (`next(x.y.z)` is `x.y.(z+1)`), sorts, merges, and drops
whitespace; a component at `4294967295` cannot be advanced and keeps its bracket.

Three renderings exist for people; none is accepted as input:

| Style | Reads as |
| --- | --- |
| Cargo | `>=3.0.0, <3.1.0` and `>=4.0.0, <4.1.0` |
| Elm | `3.0.0 <= v < 3.1.0` and `4.0.0 <= v < 4.1.0` (an unbounded interval cannot be rendered) |
| Prose | `3.0.0 up to but not including 3.1.0, or 4.0.0 up to but not including 4.1.0` |

## Compatibility results

`supported` when the release is inside the table; `unsupported_format_version_major` when no interval touches its major;
`unsupported_format_version_minor` when an interval touches its major but none contains it. The last replaces
`unsupported_format_version_revision`, because under the patch promise the mismatch is always the minor.

## Where each binding publishes its table

| Binding | Table | Published |
| --- | --- | --- |
| Specification reference | `[3.0.0,3.1.0),[4.0.0,4.1.0)` | format-version page and corpus |
| morphir-typescript (`@finos/morphir-ir`) | `[4.0.0,4.1.0)` | adapter `formatVersions`; run report |
| morphir-rust (`morphir_core`) | `[3.0.0,3.1.0),[4.0.0,4.1.0)` | adapter `formatVersions`; run report |
| morphir-ui | `[3.0.0,3.1.0),[4.0.0,4.1.0)` | README |

The `mck` driver refuses a non-canonical `formatVersions`, prints the table in prose at the head of a run, and writes the
canonical string into the report.

## Unresolved

- Minting the first minor after 4.0.0 is released: which kit cases move, how every binding's ceiling advances in one
  change, and whether the legacy-spelling window (bead .19) is the whole of `4.1.0` or one part of it.
- morphir-scala and morphir-elm do not yet declare tables; they adopt the notation when they adopt the contract.
