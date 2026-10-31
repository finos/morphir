---
type: Decision Record
title: Extensions declare IR capability sets
state: Accepted
decided: 2026-09-19
tags: [extensions, capabilities, mck, ir, mep, frontend, backend, transform]
status: stable
description: Every extension declares which IR features it handles, in a vocabulary the IR specification owns and the Morphir Compatibility Kit verifies, so the toolchain can plan and check a pipeline instead of discovering gaps at run time.
---

# Extensions declare IR capability sets

Every Morphir extension declares which IR features it handles, as a capability set. The feature
vocabulary belongs to the IR specification, next to the Morphir Compatibility Kit cases that
prove each feature. A declaration is a claim the kit checks, not prose.

This is toolchain-wide. It applies to every frontend, backend and transform, in any language
binding, and exists because no frontend or backend supports every IR feature and the toolchain
should be able to say so.

## Summary

MEP capabilities today answer "can this extension compile Elm, and to which IR versions". They
do not answer "how much of the IR does it actually handle". A caller finds that out by running a
compile and reading diagnostics, or by not finding out at all. The native Elm frontend made this
concrete: it lowers types and skips values, and a `typesOnly: false` request still returned
`success: true` with an empty `values` array, because nothing in the protocol could express the
gap.

| Option | Outcome | Why |
| --- | --- | --- |
| Capability sets in an IR-owned vocabulary, verified by the MCK | Chosen | Features are properties of the IR, and the kit is where a claim about one can be put under test, so a declaration cannot drift unnoticed |
| A vocabulary owned by the extension protocol | Rejected | Would duplicate the IR's own feature taxonomy and drift from the cases that define it |
| Per-extension boolean flags, hand-maintained | Rejected | No evidence behind a claim; rots as bindings change |
| Nothing declared; report gaps at run time only | Rejected | A host cannot choose a provider or check a pipeline before running it |

## Why

The IR defines the features. The MCK already enumerates them case by case, grouped by the
specification page that owns each area: `types`, `values`, `patterns-and-literals`, `names`,
`definitions`, `distributions`, `versions`, `document-tree`. Adapter reports
(`spec/mck/baseline/reports/*.json`) record pass or fail per case id per binding. So the features
already have names, and each name already has cases standing behind it.

What the kit does not have yet is evidence at the level a capability set talks about. The IR suite
drives codec operations — decode, re-encode, read and write a document tree — so its report says
whether a binding can *carry* a feature through serialization, not whether an extension can
*lower* or *generate* it. Two things are therefore missing: a way for an extension to state its
capability set in a request, and cases that exercise the extension itself.

Putting the vocabulary anywhere else would fork it. If the protocol owned the tags, the IR
specification and the protocol would each carry a partial list of IR features and they would
diverge. The protocol references the vocabulary; the IR specification defines it.

Three properties follow from declaring capabilities at all:

**Selection.** A host can pick a provider on what it handles rather than on reputation. The CLI
currently hard-codes that `morphir-elm` is the default Elm frontend and the native one is opt-in
(see [Two Elm frontend providers](/decisions/0001-two-elm-frontend-providers.md)); with capability
sets, that is a fact both providers state.

**Pipeline checking.** Frontends produce IR features; backends consume them; the same vocabulary
points both ways. A host can compare a frontend's output set against a backend's accepted set
before running either, so an unsupported construct is a plan-time error instead of a failure
inside `generate`.

**Composition.** MEP already defines a `Transform` extension type that nothing uses. A polyfill is
exactly a transform that consumes a feature and produces IR without it: pattern matching lowered
to nested conditionals, generics monomorphised. Once all three roles speak one vocabulary, a host
can plan `frontend -> transform* -> backend` rather than having someone wire it by hand. The
vocabulary is therefore directional from the start, even though transforms are built later.

## Shape

Three-valued support per area, with named feature tags for exclusions:

```json
"lowers": {
  "types":  { "support": "partial", "without": ["type-variables"] },
  "values": { "support": "none" }
}
```

`full`, `partial` or `none` per area. `without` names feature tags the area otherwise implies.
Backends and transforms use the same vocabulary for what they accept and emit. Receivers ignore
unknown areas and tags, so the vocabulary grows additively under the same rules as the rest of
MEP 0.1.

Tags are defined on the `spec/ir/mck` page that owns the area, each mapping to the case ids that
prove it. The registry starts small: a tag is added when a real extension needs to exclude it, not
in anticipation.

## Verification

A declared capability is a claim and a kit report is the evidence, but only a report that exercises
the operation being claimed.

The IR suite does not. Its cases drive codec operations — `decode`, `readTree`, `writeTree` — and
its records are pass or fail per case id, profile and role. That is evidence for one narrow claim:
that a binding can carry a feature through serialization. It cannot confirm or refute a frontend's
`lowers` or a backend's `accepts`, and reading it as if it could is wrong in both directions. The
native Elm frontend is the example again: it lowers no values at all, yet every `values-NNNN` case
passes through the Rust binding's codec, so the IR report would reject its honest `values: none`
and would equally have accepted a false `values: full`.

Capability evidence comes from extension-level cases instead: a source input, the extension invoked
under MEP, and an assertion about the IR it produced or consumed, reported per feature tag. That is
a second MCK suite beside the IR suite — the kit already expects to grow more than one, and the
package suite is the other. The IR suite keeps owning the vocabulary; the extension suite produces
the evidence for a declaration, and the IR suite's report remains a precondition on the binding
underneath, since an extension cannot honestly claim to emit what its binding cannot serialize.

With that suite in place, CI fails when a declaration and the extension report disagree in either
direction: claiming `full` for an area with failing cases, and claiming `none` or excluding a tag
whose cases pass. Until it exists, every declaration is unverified. An extension not yet enrolled
may declare, and its declaration is marked unverified rather than trusted. Enrollment is the
expectation, not an option, and an unverified declaration is a gap to close.

Run-time reporting closes the loop. When an extension meets a construct it cannot handle, it
reports it (see the unresolved item below). Anything reported that the declaration did not
predict is a defect: either the declaration is wrong or the extension is.

## Alternatives rejected

### A vocabulary owned by the extension protocol

Keeps everything about extensions in `protocol.md`, but makes the protocol the second home for a
taxonomy of IR features. The IR specification already names these features and the kit already
tests them; a protocol-owned list would restate and then contradict them.

### Per-extension boolean flags

`valueLowering: false` next to `incremental` is smaller and needs no registry. It carries no
evidence, cannot express "types except type variables", and gives a host nothing to check a
pipeline with. Hand-maintained capability flags rot: the flag stays false after the feature lands,
or stays true after a regression.

### Run-time reporting only

Reporting unhandled constructs after the fact is necessary regardless, and is cheaper. On its own
it means every question about a provider is answered by running it, which is no basis for
selecting a provider or validating a pipeline.

## Consequences

The IR specification gains a feature-tag registry under `spec/ir/mck`, tied to the cases that
prove each tag. MEP capabilities gain a `lowers`-style field for frontends, and equivalents for
backends and transforms, referencing that vocabulary. The MCK gains an extension suite whose cases
compile and generate through MEP rather than round-tripping documents, and a check comparing an
extension's declaration against that suite's report. Building that suite is the cost of this
decision, and nothing is verified before it lands.

Extensions may be partial and say so. A types-only frontend is a frontend with a declared gap, not
a frontend with a narrower contract, so the same provider improves over time without callers
changing how they call it.

Extensions that do not run the kit can still declare capabilities, but the declaration is
unverified, and that distinction is visible rather than implied.

## Unresolved

How an extension reports the constructs it skipped at run time, in a machine-readable form, is
open: a structured unhandled-constructs collection on the compile result, per-module status for
partial results, and what `success` means when the only shortfall is declared incompleteness. That
is the companion to this record and is being designed separately.

Whether a capability declaration should carry a version of the vocabulary it was written against,
or rely on additive growth and ignorable unknown tags alone, is open until the registry has more
than one revision.

## Revisit when

Revisit when the first transform extension ships, since that is the first real test of the
vocabulary pointing in both directions. Revisit the verification rule when the extension suite lands
and its case shape is known, or sooner if an extension outside the kit needs its declaration
trusted, and the tag granularity when an extension needs an exclusion the area-plus-tag shape
cannot express.
