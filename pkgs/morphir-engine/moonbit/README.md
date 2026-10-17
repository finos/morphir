# MoonBit source adapter

This package connects the pure [Boolean frontend](../../morphir-moonbit-frontend/README.md)
to the engine's rich source callback. Applications opt in explicitly:

```moonbit
let engine = @engine.Engine::new()
@moonbit_frontend.register(engine)
```

Import `finos/morphir-engine/moonbit` as `moonbit_frontend`. The adapter registers
provider `finos/morphir-moonbit-frontend`, exported as `PROVIDER`, for language
`moonbit` and `.mbt` files. It offers two profiles:

| Profile | Source behavior |
| --- | --- |
| `moonbit-model-bool-v1`, default | One function with explicit Bool signature, literals, parameters, Boolean operators and conditionals |
| `moonbit-model-bool-library-v1`, opt-in | Multiple explicit Bool functions, public and unexported helpers, immutable local bindings, lexical shadowing, direct same-file calls, forward and zero-input calls |

Both profiles process one document per unit and do not support incremental
compilation, cross-file imports or other source types. The library excludes
recursion, mutation, indirect and qualified calls. Profile names describe supported source
forms; the source language remains `moonbit`.

`provider()` exposes these same descriptors and callbacks to in-process clients.
`register` registers that provider with the engine; it accepts optional `limits` for the seed, `library_limits` for the library,
and `unit_limits` for rich envelope validation. It validates source budgets before
registering and reports their configured values in capability descriptors. Parser
0.4.5 and lexer 0.4.3 remain explicit dependency pins. Both profiles report local
acceptance evidence; this is separate from ecosystem MCK qualification.

An optional host-owned `observer` instruments frontend stages and defaults to a
disabled observer. Planning never invokes it. The library adds resolution and a
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
