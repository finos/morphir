---
type: Decision Record
title: Two Elm frontend providers
description: The CLI keeps morphir-elm as the default Elm frontend and morphir-elm-native as an opt-in provider until the native one reaches value and type-inference parity.
state: Accepted
decided: 2026-09-18
tags: [elm, extensions, frontend, mep]
status: stable
---

# Two Elm frontend providers

The `morphir` CLI registers two Elm frontends rather than one. `morphir-elm`, the JS process
extension (`ecosystem/morphir-elm/cli2/mep/`, morphir-elm#1285), stays the default for `.elm`
sources. `morphir-elm-native` (`ecosystem/morphir-rust/crates/morphir-elm-binding`,
finos/morphir-rust#173) is registered as a builtin but only runs when a caller asks for it with
`--extension morphir-elm-native`.

## Summary

`morphir-elm` is the reference implementation: it has shipped value lowering and type inference
and its output is what other frontends are checked against. `morphir-elm-native` is types-only
today. It parses with a vendored tree-sitter-elm grammar and a data-driven prelude, emits IR v3
and v4 natively, and already implements the MEP incremental fields (`baseline` and
`moduleResults`) that `morphir-elm`'s MEP server does not yet read or write. Keeping both lets the
CLI ship the native frontend's incremental behavior now, opt-in, without asking any project to
trade away the value and type coverage only the JS frontend has.

| Option | Outcome | Why |
| --- | --- | --- |
| `morphir-elm` (JS, MEP process extension) as the default Elm frontend | Chosen | It is the reference implementation; value lowering and type inference are proven against it |
| `morphir-elm-native` as an opt-in provider, selected with `--extension` | Chosen | Exercises the native path and its incremental cache fields without regressing default output |
| Ship only `morphir-elm-native` now | Rejected | Types-only output is not a parity replacement for the reference frontend |
| Ship only `morphir-elm` and drop the native provider | Rejected | Throws away the incremental (`baseline`/`moduleResults`) work and the native compile path |

## Why

`morphir-elm`'s output is the parity baseline every other Elm frontend is measured against; that
is what "reference implementation" means here. `morphir-elm-native` does not yet lower values or
run type inference, so its IR is not a substitute for `morphir-elm`'s in a default compile.
Defaulting `.elm` to the native provider would silently change what a plain `morphir compile`
produces for every existing Elm project.

At the same time, the native provider is not just a partial reimplementation sitting on the
shelf. It emits IR v3 and v4 directly from a vendored tree-sitter-elm grammar and a data-driven
prelude, and it is the first Elm frontend to speak the MEP incremental fields end to end:
`CompileRequest.baseline` and `CompileResult.moduleResults`, typed as
`morphir_extension_sdk::{CompileBaseline, BaselineModule, ModuleResult, ModuleStatus}`, with
per-module statuses of `compiled`, `unchanged`, `failed`, or `blocked`. Making it available
opt-in, via `morphir compile --extension morphir-elm-native`, gets that incremental behavior in
front of users today instead of waiting on `morphir-elm`'s MEP server to catch up.

## Alternatives rejected

### Ship only `morphir-elm-native` now

Would make `.elm` compiles default to a types-only frontend, dropping value lowering and type
inference for every project that does not explicitly ask for the JS frontend. The native
provider has not been checked against the reference model closely enough to carry that default.

### Ship only `morphir-elm` and drop the native provider

Keeps a single, proven Elm frontend but throws away the native compile path and the only
implementation of the MEP incremental fields, `baseline` and `moduleResults`, that either
provider currently supports.

## Consequences

Two Elm frontend extension ids exist side by side: `morphir-elm` (default for `.elm`) and
`morphir-elm-native` (opt-in). A caller reaches the native path with
`morphir compile --extension morphir-elm-native`; without that flag, `.elm` sources go through
`morphir-elm` as before.

The two providers are not interchangeable in what they report. `frontend.incremental` is only
`true` for `morphir-elm-native` today, so `baseline` and `moduleResults` only flow on that path;
`morphir-elm`'s MEP server does not populate or consume them yet. The CLI's compile cache follows
`frontend.incremental`: it only engages for providers that advertise it, so caching is currently
native-only, and `--no-cache` still applies there to skip both the read and the write.

## Unresolved

Nothing beyond the parity gate below is open; the identities, flag, and incremental fields are
fixed by finos/morphir-rust#173 and this record.

## Revisit when

Revisit the default once `morphir-elm-native` reaches value-lowering and type-inference parity
with `morphir-elm`'s output, checked by running the native provider's IR through the same parity
test used against the reference model. Also revisit if `morphir-elm`'s MEP server adopts
`baseline`/`moduleResults`, since at that point both providers would report incremental status
and the cache path would no longer be native-only.
