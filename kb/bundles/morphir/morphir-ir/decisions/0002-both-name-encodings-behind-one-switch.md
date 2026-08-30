---
type: Decision Record
title: Both name encodings are implemented, and the switch gates only the encoder
description: "Implementations carry both canonical name encodings; a compile-time constant selects which one is written, while readers always accept both."
state: Accepted
decided: 2026-08-30
supersedes: []
tags: [ir, ir-v4, naming, implementation, compatibility]
status: draft
---

# Both name encodings are implemented, and the switch gates only the encoder

Every implementation of v4 naming carries both canonical encodings chosen between in
[decision 0001](/decisions/0001-name-canonicalization-and-initialism-encoding.md). A single compile-time constant
selects which one is produced.

| Direction | Behavior |
| --------- | -------- |
| Encode | One style, selected by a compile-time constant. Option 1 (`value-in-USD`) is the shipped setting. |
| Decode | Both styles, always, with no constant consulted. |
| Specify | One style. The wire format remains Option 1 only; Option 2 stays an appendix. |

## Summary

Decision 0001 records two unresolved questions and judges one of them on legibility rather than proof. Carrying both
encodings makes revisiting that judgement a one-line change rather than a rewrite. The refinement that makes this
cheap is asymmetry: the two syntaxes are disjoint, so a reader can accept both without ambiguity, and only the writer
needs the constant.

| Option | Outcome | Why |
| ------ | ------- | --- |
| Both encodings, compile-time constant, encoder-only switch | Chosen | Flipping is non-breaking for readers, and the unselected branch stays exercised by decode tests |
| Both encodings, runtime or configuration switch | Rejected | Two producers emit different bytes for the same name with nothing detecting the divergence |
| Option 1 only | Rejected | Revisiting the unproven judgement in 0001 would cost a rewrite in every implementation |
| Both encodings, both normative in the specification | Rejected | Interop requires exactly one canonical form on the wire |

## Why

### The two syntaxes are disjoint, so decoding both is unambiguous

A canonical name under Option 1 matches `^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$`. A canonical name under
Option 2 matches `^(--)?[a-z0-9]+(--?[a-z0-9]+)*$`.

`value-in--usd` cannot match Option 1, because the doubled separator requires an empty segment and `[a-z0-9]+`
requires at least one character. `value-in-USD` cannot match Option 2, because Option 2 admits no uppercase. A name
carrying no initialism, such as `user-account`, matches both and decodes to the same segments under both.

The two languages are therefore disjoint exactly where they differ and identical where they agree. A union decoder
is total and unambiguous. This is proven by construction, and the patterns were checked against 39 accept and reject
cases.

The consequence is what makes the decision cheap. Flipping the constant is backward-compatible for every reader that
already shipped, so a change of mind does not strand existing artifacts.

### An unselected branch that nothing exercises is not an implementation

Carrying dead alternative code is usually a liability, because it rots unobserved. The encoder-only switch avoids
that: the decoder path for the unselected style runs on every decode test, and the conformance corpus covers both
styles regardless of the constant. Only the unselected encoder is unexercised in production, and a round-trip
property test over both styles covers it.

### A runtime switch would produce undetectable divergence

Canonical names are identity. If the encoding were selectable at run time, two producers configured differently would
emit different bytes for the same name, and no validator downstream could tell that the two artifacts describe the
same thing. Making the selection a compile-time constant in one module keeps a single build honest by construction.

The constant is not exposed as a CLI flag, a configuration key, an environment variable, or a per-call parameter.

### The specification stays single-valued

Two normative canonical forms would be an interop hazard for the same reason. The switch is an implementation
affordance for revisiting decision 0001 cheaply. It is not a format feature, and conforming producers emit Option 1.

## Alternatives rejected

### Both encodings, runtime or configuration switch

Argued above. The failure is silent divergence between producers, which no downstream validator can detect.

### Option 1 only

Decision 0001 states plainly that its choice rests on a legibility judgement that is not proven, and that Option 2
carries a real advantage in case-free identity. Implementing only the chosen style would make acting on that
admission expensive in five implementations. The measured cost of carrying both is one enumeration and two small
functions per implementation.

### Both encodings, both normative in the specification

Interop requires one canonical form. A consumer must not have to accept that the same name appears as `value-in-USD`
in one artifact and `value-in--usd` in another and treat them as equal, because that equality would then have to be
implemented everywhere rather than in the reader alone.

## Consequences

1. `Name` in `ecosystem/morphir-rust/crates/morphir-core/src/naming/` gains an explicit segment model and a style
   enumeration. The existing implementation stores `words: Vec<String>` and encodes parentheses in
   `to_canonical_string`.
2. `Serialize for Name` writes the style named by the constant. `Deserialize for Name` accepts Option 1, Option 2,
   and the legacy v1 through v3 array, and consults no constant.
3. The existing Rust implementation already treats a run of one single-letter word as a plain word rather than an
   acronym, so `["a"]` encodes as `a` and not `(a)`. It therefore already agrees with `docs/spec/draft/names.md`
   against `docs/design/draft/ir/naming.md`, and the legacy decoding rule in decision 0001 matches the behavior that
   shipped.
4. Round-trip property tests run over both styles regardless of the constant.
5. The conformance corpus carries both styles for every case, so an implementation that flips its constant needs no
   new fixtures.

## Revisit when

- A third canonical encoding is proposed, at which point a two-way disjointness argument no longer suffices and the
  union decoder needs a real grammar rather than a pair of patterns.
- The constant has stayed on Option 1 across two major versions with no serious proposal to flip it, at which point
  the Option 2 branch is cost without benefit and should be deleted.
