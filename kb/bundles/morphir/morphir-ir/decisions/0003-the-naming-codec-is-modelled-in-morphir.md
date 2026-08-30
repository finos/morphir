---
type: Decision Record
title: The naming codec is modelled in Morphir, with a host-language bootstrap
description: "The v4 naming codec is expressed as a Morphir model in finos/morphir and drives a shared conformance corpus, while one host implementation remains as the bootstrap."
state: Proposed
decided: 2026-08-30
tags: [ir, ir-v4, naming, dogfooding, conformance, testing]
status: draft
---

# The naming codec is modelled in Morphir, with a host-language bootstrap

The encode, decode, escape, unescape and render logic for v4 names is written once as a Morphir model in
finos/morphir. That model is the normative definition of the algorithm. Host implementations in Rust, Elm, Scala,
MoonBit and Python are conformance-tested against a corpus derived from it rather than against each other.

One host implementation remains hand-written as the bootstrap. This is not redundancy; see
[the bootstrap is unavoidable](#the-bootstrap-is-unavoidable).

## Summary

finos/morphir exists to hold the specification and its testing corpus. The naming codec is small, total, and free of
input and output, which makes it the best available candidate for expressing part of the specification in Morphir
itself. Doing so replaces five hand-written algorithms that can drift with one definition and five conformance
suites that cannot.

| Option | Outcome | Why |
| ------ | ------- | --- |
| Morphir model as normative, corpus derived from it, one host bootstrap | Chosen | The algorithm is written once, and finos/morphir already owns the corpus role |
| Hand-written conformance corpus, no model | Rejected | Removes drift between implementations but still leaves the algorithm written five times |
| Each implementation writes its own tests | Rejected | Drift is then invisible until an artifact fails to load in another toolchain |
| Generate host code from the model | Rejected for now | Depends on backend maturity the v4 work has not reached, and the bootstrap still cannot be generated |

## Why

### The SDK surface is sufficient, and this was checked

The codec needs character classification and string decomposition. Both exist in the Morphir SDK as declared in
`ecosystem/morphir-elm/src/Morphir/IR/SDK/`.

| Module | Values the codec needs, confirmed present |
| ------ | ---------------------------------------- |
| `Char` | `isUpper`, `isLower`, `isDigit`, `isAlpha`, `isAlphaNum`, `toUpper`, `toLower`, `toCode`, `fromCode` |
| `String` | `toList`, `fromList`, `split`, `join`, `uncons`, `cons`, `foldl`, `foldr`, `any`, `all`, `isEmpty`, `length`, `concat`, `toUpper`, `toLower` |
| `List`, `Maybe`, `Result` | Present |

No regular expressions are required. The grammar in decision 0001 is a character-class fold, which these values
express directly. This is verified against the SDK sources rather than assumed.

### The codec is a good dogfooding candidate

It is total, it has no input or output, it has no dependency on time or randomness, and its inputs and outputs are
strings and small data. It is also a piece of the specification rather than an application, so modelling it puts
Morphir in the position finos/morphir claims for it.

### The bootstrap is unavoidable

The naming rules govern how Morphir IR is itself serialized. A Morphir model of naming compiles to Morphir IR, and
that IR is written using the naming rules the model defines. Reading it therefore requires a naming implementation
that already exists.

This is ordinary compiler self-hosting and it is not a defect, but it does fix the framing. The Rust implementation
in `ecosystem/morphir-rust/crates/morphir-core/src/naming/` is not made redundant by the model. It is the bootstrap,
and it is the one implementation that must be correct on its own reading of the specification prose.

### One gap in the model, stated where it occurs

The path-length truncation rule in decision 0001 suffixes a stem with the first eight hex digits of a SHA-256 digest.
The Morphir SDK has no hashing primitive, so that step cannot be modelled today and stays native in each host. The
model covers encode, decode, escape, unescape and render, and the corpus marks truncation cases as host-verified
rather than model-derived.

**A hashing primitive is planned for the Morphir SDK.** Adding SHA-256 closes this gap and makes the model cover the
whole codec. The work is not scoped here, and it is larger than this decision: a hash is useful well beyond naming,
so its shape belongs to the SDK rather than to this record. Until it lands, the split above holds. `Morphir.SDK.UUID`
is the nearest existing precedent for a value type with non-trivial internal computation, and is worth reading before
designing the surface.

## Alternatives rejected

### Hand-written conformance corpus, no model

This is the cheaper half of the chosen option and remains valuable on its own. It fixes drift between
implementations, because all five run the same fixtures. It does not address the original goal, which was to pay the
implementation cost once, because the algorithm is still written five times and only its outputs are compared.

It is the correct fallback if the Morphir model proves impractical, and the corpus format is designed so that it can
be produced by hand.

### Each implementation writes its own tests

Drift then surfaces only when an artifact produced by one toolchain fails to load in another, which is the failure
mode the corpus exists to prevent.

### Generate host code from the model

Generating the Rust, Scala and MoonBit codecs from the model would be the strongest form of writing it once. It is
rejected for now rather than on principle: it depends on backend maturity that the v4 work has not reached, and the
bootstrap implementation cannot be generated in any case.

## Consequences

1. finos/morphir gains a Morphir model of the naming codec. Its location is unresolved; see below.
2. The conformance corpus is a build output of that model, and is checked in so that implementations without a
   Morphir toolchain can consume it.
3. The corpus covers both encodings from
   [decision 0002](/decisions/0002-both-name-encodings-behind-one-switch.md), so it does not change when an
   implementation flips its constant.
4. `morphir-tests` in morphir-rust already carries a Cucumber-driven acceptance suite with JSON fixtures under
   `crates/morphir-tests/fixtures/`, which is the natural driver for the corpus in that implementation.
5. Truncation cases in the corpus are marked host-verified, because the model cannot produce them.

## Unresolved

**Where the model lives.** It could sit in this repository beside the schemas, in `ecosystem/morphir-examples`, or in
a new specification-models directory. This repository is the argued home, because the corpus role belongs here, but
no directory convention exists for a Morphir model that is part of the specification.

**Whether the v4 test tooling is ready.** The plan assumes Morphir's own testing tooling advances alongside v4. That
work is not scoped, and if it lags, the corpus is generated by evaluating the model rather than by running Morphir
tests over it. The fallback is the hand-written corpus.

**Whether the model can be compiled at all today.** The model is Elm source compiled by the morphir-elm frontend,
which currently emits v1 through v3 IR. Producing v4 IR from it is a dependency that has not been checked.

## Revisit when

- A Morphir backend can generate the host codecs, at which point the rejected generation option becomes available and
  the bootstrap is the only hand-written implementation left.
- The Morphir SDK gains the planned hashing primitive, which closes the truncation gap and lets the model cover the
  whole codec.
- The model turns out to be slower to change than five hand-written codecs, which would mean the abstraction is
  costing more than the drift it prevents.
