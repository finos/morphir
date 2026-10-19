# MoonBit source adapter

This package connects the pure [source frontend](../../morphir-moonbit-frontend/README.md)
to the engine's rich source callback. Applications opt in explicitly:

```moonbit
let engine = @engine.Engine::new()
@moonbit_frontend.register(engine)
```

Import `finos/morphir-engine/moonbit` as `moonbit_frontend`. The adapter registers
provider `finos/morphir-moonbit-frontend`, exported as `PROVIDER`, for language
`moonbit` and `.mbt` files. It offers nine profiles:

| Profile | Source behavior |
| --- | --- |
| `moonbit-model-library-2026-10-19-r2`, opt-in | Current cumulative snapshot: Bool/String, all qualified integer/float forms, and pinned Basics sqrt/sin/cos/power_float/abs_float/not_ calls |
| `moonbit-model-library-2026-10-19`, opt-in | Frozen snapshot: Bool, bounded String operations and ordering, signed Int32 arithmetic, UTF-16 length, and owned slicing |
| `moonbit-model-library-2026-10-17`, opt-in | Pinned earlier cumulative snapshot, including Bool, bounded String operations and ordering, and Int32 identity/selection/calls |
| `moonbit-model-library-v2`, opt-in | Cumulative v1 plus UTF-16 shortlex String comparisons, with the same String guards |
| `moonbit-model-library-v1`, opt-in | Pinned v1 source union: Bool, String basics and Int32 identity/selection/calls in one library, including mixed signatures |
| `moonbit-model-bool-v1`, engine/CLI compatibility default | One function with explicit Bool signature, literals, parameters, Boolean operators and conditionals |
| `moonbit-model-bool-library-v1`, opt-in | Multiple explicit Bool functions, public and unexported helpers, immutable local bindings, lexical shadowing, direct same-file calls, forward and zero-input calls |
| `moonbit-model-typed-library-foundation-v1`, opt-in | Narrow Bool/Int32 typed signatures, bindings, conditionals and direct calls; numeric arithmetic remains separate |
| `moonbit-model-int32-library-v1`, opt-in | Signed Int32 literals, wraparound arithmetic, comparisons and Bool expressions |
| `moonbit-model-string-library-v1`, opt-in | String/Bool libraries, quoted literals, bounded concatenation and exact equality with executable public String guards |

The workbench prefers **Supported MoonBit library 2026-10-17** for fresh local projects. Engine
and CLI callers select it explicitly with `frontend.profile = "moonbit-model-library-2026-10-17"`
or `--frontend-profile moonbit-model-library-2026-10-17`. Existing saved profile choices and
the engine/CLI Boolean default remain compatible. This cumulative version covers
local source conformance. Select `moonbit-model-library-2026-10-19-r2` explicitly for
signed arithmetic, String length and owned slicing. Imports and full ecosystem
qualification remain outside these profiles.

All profiles process one document per unit and do not support incremental
compilation or cross-file imports. The library excludes
recursion, mutation, indirect and qualified calls. Profile names describe supported source
forms; the source language remains `moonbit`.

`provider()` exposes these same descriptors and callbacks to in-process clients.
`register` registers that provider with the engine; it accepts optional `limits` for the seed, `library_limits` for the library,
`max_string_code_units` for a String limit from 0 through 1048576, and `unit_limits` for rich envelope validation. It validates source budgets before
registering and reports their configured values in capability descriptors. Parser
0.4.5 and lexer 0.4.3 remain explicit dependency pins. All profiles report local
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
