# MoonBit source adapter

This package connects the pure [source frontend](../../morphir-moonbit-frontend/README.md)
to the engine's rich source callback. Applications opt in explicitly:

```moonbit
let engine = @engine.Engine::new()
@moonbit_frontend.register(engine)
```

Import `finos/morphir-engine/moonbit` as `moonbit_frontend`. The adapter registers
provider `finos/morphir-moonbit-frontend`, exported as `PROVIDER`, for language
`moonbit` and `.mbt` files. It offers versioned profiles:

| Profile | Source behavior |
| --- | --- |
| `moonbit-model-stable-v1`, default | Typed Bool/String/Int32 libraries, bindings, direct calls, String ordering, length and owned slices, audited Boolean SDK call |
| `moonbit-model-experimental-v1`, opt-in | Stable plus expanded integer widths, BigInt, Float/Double, SDK math/Integer conversions and checked Decimal |

Engine, CLI, Workbench and MEP use stable by default. Select experimental with
`frontend.profile = "moonbit-model-experimental-v1"` or
`--frontend-profile moonbit-model-experimental-v1`. Numeric/Decimal support remains
experimental pending installed numeric qualification. Promote capabilities with the
[evidence required by the source frontend](../../morphir-moonbit-frontend/README.md),
keeping the same two channel IDs. The Boolean seed and intermediate IDs are retired.
retained checkpoints preserve their original identities and provenance.

All profiles process one document per unit and do not support incremental
compilation or cross-file imports. The library excludes
recursion, mutation and indirect calls. Qualified calls are limited to each profile's audited SDK bindings. Profile names describe supported source
forms; the source language remains `moonbit`.

`provider()` exposes these same descriptors and callbacks to in-process clients.
`register` registers that provider with the engine; it accepts optional `library_limits` shared by both channels,
`max_string_code_units` for a String limit from 0 through 1048576, and `unit_limits` for rich envelope validation. It validates source budgets before
registering and reports their configured values in capability descriptors. Parser
0.4.5 and lexer 0.4.3 remain explicit dependency pins. All profiles report local
acceptance evidence; this is separate from ecosystem MCK qualification.

An optional host-owned `observer` instruments frontend stages and defaults to a
disabled observer. Planning never invokes it. Both channels include resolution and a
second profile-check stage after name resolution. Observation leaves binary Ion
checkpoints unchanged. Registration conflicts fail. Engine core stays independent
of the parser package; the Morphir CLI opts in here.

The callback preserves native Ion metadata, annotations and provenance, forwards
cancellation and translates source diagnostics into `SourceFrontendError::Rejected`.
The engine supplies canonical package/module names and validates the logical unit ID
and metadata ownership. Checkpoint and generation pipelines retain the rich unit.
Legacy text output requires a separate explicit projection contract.

No file, process, acquisition or compiler operations happen in this adapter.
Installed source-to-execution acceptance and A2 extension delivery are separate
roadmap slices. See the [CLI example](../../../apps/morphir/README.md#moonbit-source-models).

```sh
moon test -p finos/morphir-engine -p finos/morphir-engine/moonbit --target all
```
