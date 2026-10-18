# Runtime capability policy adapter

This explicit offline adapter implements Workbench `0.1.0-draft.12`, JSON transport
and `run-capability-policy`. The parent `finos/morphir` specification owns the
schemas, fixed expectations and the single Rust runner/checker. The adapter
receives input only and reports observations, never verdicts.

`plan_scheme_capabilities` captures the original Library IR, selected public
entries, full input/output type closure, arguments and effective policy. Omitted
policy is strict. Explicit permissive execution uses the bounded Scheme backend
and defers represented Hole and IncompleteBody operations until reached, producing
`failed/evaluate/execution.unsupported_reached`. Missing bindings, malformed
source, visibility failures, resource limits, SDK model errors and ordinary
`Result.Err` retain distinct meanings. The narrow draft.11 adapter and existing
`plan_scheme`/`evaluate` route keep their original behavior.

The new operation has two explicit observation modes:

- `execute` calls the real immutable plan and validates actual typed terminals.
- `validate-completion` validates supplied JSON/Ion-text terminal evidence against
  that same captured context, without executing the model. It is validation
  evidence and does not establish execution, cancellation or provider authority.

Both preserve ordered call identities, extensions and independent primary/cleanup
failures. Failed or cancelled evidence never waives selected boundary validation.
Actual Scheme Decimal results use the existing SDK normalization law; supplied
completion validation preserves valid wire representation without arithmetic.

Run the six-lane gate from the repository root after installing the pinned Bun
and Workbench Playwright dependencies and Chromium:

```bash
MORPHIR_MCK_BIN=/path/to/finos/morphir/target/debug/morphir \
MORPHIR_WORKBENCH_KIT=/path/to/finos/morphir/spec/workbench/mck/draft.12 \
mise run test:workbench-capability-policy-mck
```

The gate tests the portable adapter on JS, native, Wasm and Wasm GC, then runs and
independently rechecks all 182 cases in Node, Chromium and native, each debug and
release. Reports default to `.dev/capability-policy-mck/reports`. Override them
with `MORPHIR_WORKBENCH_EVIDENCE` and the build directory with
`MORPHIR_CAPABILITY_SCHEME_BUILD`. The Chromium transport runs this same compiled
MoonBit handler, with no network access or compatibility verdict in JavaScript.

These are specific source, selected-type, value, encoded-byte and interpreter
fuel/depth/frame budgets, not a hard process-memory or CPU quota over opaque SDK
internals. SDK allocation/cancellation hardening is tracked as `morphir-be5t`.
Registered native fallback tests qualify the backend only; this production plan
registers no caller-supplied native implementations.

No Workbench UI, asynchronous execution, native/HTTP mapping, generated backend or
packaged-platform capability is advertised by this adapter. Those integrations
have separate implementation and qualification tasks.
