---
type: Decision Record
title: "Support tables are intervals, and a patch changes nothing a reader can observe"
description: "An implementation declares the IR format versions it reads as a union of intervals in Maven-style notation with one canonical spelling; a patch revision never changes what a reader accepts or a writer emits, a minor may, so the reference table is [3.0.0,3.1.0),[4.0.0,4.1.0) and a later minor fails with unsupported_format_version_minor."
state: Accepted
decided: 2026-09-16
tags: [ir, ir-v4, versioning, format-version, mck]
status: draft
---

# Support tables are intervals, and a patch changes nothing a reader can observe

An implementation declares the format versions it can read as a support table: a union of intervals over the release
grammar, written in the interval notation that Maven, NuGet and OSGi share, with one canonical spelling. A patch
revision changes nothing a reader can observe, a minor revision may change what a reader accepts or emits, and a major
may change anything. The reference table is therefore `[3.0.0,3.1.0),[4.0.0,4.1.0)`: a reader for `4.0.0` accepts every
`4.0.x` and fails a `4.1.0` document with `unsupported_format_version_minor`, which replaces
`unsupported_format_version_revision`. Bindings driven through the Morphir Compatibility Kit publish their table in the
`formatVersions` member of the adapter's capabilities reply.

## Summary

The format-version contract shipped in finos/morphir#738 treated every exact release as its own island. The reference
table listed `3.0.0` and `4.0.0`, and a `4.0.1` or `4.1.0` document failed. A reviewer on finos/morphir#790 asked why
the contract rejected `4.1.0`. GitHub issues #792 and #795 then asked that no support for `4.1.0` be added silently, and
that any change to the policy be recorded as a contract decision. The intent behind the exact list was never to reject later
revisions. It was to avoid minting `4.1.0` while the vocabulary is still moving before the formal 4.0.0 release. This
record separates the two questions: what a revision is allowed to change, and how a reader states what it supports.

| Option | Outcome | Why |
| ------ | ------- | --- |
| Exact-release lists (status quo) | Rejected | Every patch would need a new release of every reader; the list said nothing about what a revision means |
| Intervals in Maven-style notation, one canonical spelling | Chosen | The grammar is exactly a union of intervals with nothing to subset; every binding parses it in a few lines; NuGet, OSGi, Ivy and Eclipse p2 use it too |
| Cargo comparator sets | Rejected for the wire form, kept as a rendering | `>=a, <b` reads well, but a bare release means caret in Cargo and there is no union inside one string |
| Elm constraints `a <= v < b` | Rejected for the wire form, kept as a rendering | One shape only, exclusive upper only, no union; an inclusive ceiling needs the next-patch trick |
| npm ranges | Rejected | The full grammar is large, a subset would be our own invention, and Rust's semver crate lacks the union and hyphen forms |
| Readers tolerate newer minors by ignoring unknown members | Rejected | It weakens `unknown_member` for every reader and makes a document's meaning depend on the reader's age |
| Keep `unsupported_format_version_revision` | Rejected | Under the patch promise the mismatch is always the minor; the code should say so, and the rename costs one pre-release sweep |

## Why

### The revision promise comes first

A range only means something once each component promises something. A patch promises nothing a reader can observe:
prose clarifications, corrected examples, kit cases that pin behaviour the contract already required. That is what makes
a ceiling on a minor boundary safe: a `4.0.0` reader can accept a `4.0.7` document it has never seen, because `4.0.7`
could not have added anything. A minor is the only revision that may change what a reader accepts or emits, which also
settles that closing the legacy-spelling window is a minor, not a patch. A major may change anything.

The kit mints revisions, and nothing else does. Until 4.0.0 is formally released, every change stays inside `4.0.0`.

### Why interval notation

The table a reader needs to express is a union of closed-or-open intervals, one per major. Maven's interval notation is
exactly that: `[a,b)` for a half-open interval, a comma for union, round brackets for exclusive bounds. It carries no
operators to subset and nothing to extend. Cargo and Elm each express one interval well but not the union, and Cargo's
bare-release caret rule is a trap. Cargo's comparator sets read well, so they are kept as a rendering, along with Elm's
constraint form and a prose form for reports.

### One canonical spelling

Adapters, reports and READMEs must agree byte for byte, so the table has one spelling: half-open `[a,b)` wherever a
bound can be advanced, sorted, merged, no whitespace. The next release after `x.y.z` is `x.y.(z+1)`, so an inclusive
upper `b]` becomes `next(b))`. A patch component already at `4294967295` cannot be advanced, so that bound keeps its
original bracket; `next()` never carries into the minor. The full grammar is accepted on input so a person can write
`[4.0.0,4.0.2]` and mean it.

### Why rename the diagnostic

With the patch promise in force, a patch can never be the reason a document is unsupported. Whether the table is the
reference or a narrower one such as `[4.1.0,4.2.0)` refusing `4.0.3`, the mismatching component is the minor.
`unsupported_format_version_minor` names that condition and pairs with `unsupported_format_version_major`. The old name
is pre-release and pinned only by the kit, so the rename is one sweep with no alias.

## Alternatives rejected

### Exact-release lists

Keeping the shipped contract means every reader enumerates the releases it accepts. Under the patch promise that list
is mostly noise: a `4.0.7` patch adds nothing a reader can observe, yet every reader would need a new release before it
would read a `4.0.7` document. Worse, the list is silent about meaning. It says which releases were known when the
reader was built, not what a revision is allowed to change, so nobody reading it can tell whether a rejection is a real
incompatibility or a stale enumeration.

### Cargo comparator sets as the wire form

`>=4.0.0, <4.1.0` is the most readable spelling of a single interval, and it was the first candidate. It fails on two
counts. A comparator set has no union operator, so a binding supporting two majors cannot put its whole table in one
string, and the table is exactly the thing that must travel as one string through `formatVersions`. And a bare release
in Cargo means caret — `4.0.0` is `>=4.0.0, <5.0.0` — which is a trap for anyone hand-writing a table. The form is kept
as a rendering, where readability is the only requirement.

### Elm constraints as the wire form

`4.0.0 <= v < 4.1.0` is unambiguous and needs no bracket vocabulary. It offers exactly one shape: an inclusive lower
bound and an exclusive upper bound, with no union and no way to spell an unbounded side. An inclusive ceiling has to be
faked by naming the next patch, which is the same `next()` trick the canonical spelling performs but with no notation
to record that it happened. Like Cargo's form, it survives as a rendering.

### npm ranges

npm's range grammar already expresses everything needed, including unions via `||`. It also expresses far more —
hyphen ranges, `x` wildcards, tilde and caret — so adopting it whole means every binding implements a large grammar for
a table that is never more than a handful of intervals. Adopting a subset means inventing a dialect that looks like npm
but rejects valid npm input, which is worse than a small grammar of our own. Rust's `semver` crate settles it: it
supports neither the union nor the hyphen form, so the Rust binding would hand-roll a parser anyway.

### Readers tolerate newer minors by ignoring unknown members

The cheapest-looking fix is to let a `4.0.0` reader accept a `4.1.0` document and skip whatever it does not recognize.
That trades one diagnostic for a worse one: `unknown_member` is how every reader reports a typo or a malformed
document, and it cannot stay strict if it must also absorb legitimate future vocabulary. It also makes a document's
meaning depend on the age of whatever opened it, so two conforming readers can disagree about the same file and neither
is wrong. A refusal that names the minor is the honest answer.

### Keeping `unsupported_format_version_revision`

Not renaming the diagnostic costs nothing today, and it was tempting for that reason. But "revision" names the wrong
component: with the patch promise in force, a patch can never be the reason a document is refused, so the code would
describe a condition that cannot occur. It also fails to pair with `unsupported_format_version_major`, leaving the two
halves of the same check named on different axes. The old code is pre-release and pinned only by the kit, so keeping it
buys one avoided sweep in exchange for a permanently misleading name.

## Consequences

1. The format-version page gains a "Revisions" section with the promise table, and its "Recognition and compatibility"
   section defines support tables, their grammar, canonical spelling, renderings and publication.
2. The conformance corpus replaces `supportedVersions` with `supportTable`, flips `4.0.1` to supported, adds `4.1.0`
   as `unsupported_format_version_minor`, and gains `supportTableCases` for parsing, canonical spelling, membership and
   rendering. Kit case distributions-0001 rejects `"4.1.0"` with the new code and distributions-0008 reads `"4.0.1"`.
3. Adapter protocol contract 1 gains a required `formatVersions` member in the capabilities reply; the run report carries
   it. The TypeScript binding declares `[4.0.0,4.1.0)`; the Rust binding declares `[3.0.0,3.1.0),[4.0.0,4.1.0)`;
   morphir-ui publishes its table in its README.
4. `@finos/morphir-ir` and `morphir_core::format_version` each carry one support-table module: parse, canonical form,
   membership, and the Cargo, Elm and prose renderings.
5. The legacy-spelling window closes as `4.1.0` after the formal 4.0.0 release.
6. Bead `morphir-ir-v4-stabilize.8` closes on this record.

## Revisit when

- The first minor after the formal 4.0.0 release is minted, which is the first time a ceiling moves.
- A binding needs a table the grammar cannot express, which would mean a revision promise was broken.
- A third-party adapter appears, at which point adding a required protocol member needs a contract version bump.
