# Declared output admission draft

Exact `0.1.0-draft.4` adds `validate-output` to the three [draft.3 operations](../draft.3/README.md).
Earlier drafts and their corpora are unchanged. Frozen `morphir-invocations-v1`,
`morphir-outcomes-v1` and connected `protocolVersion: 1` are unchanged.

This is offline output-value qualification. It does not invoke a function or
qualify a complete outcomes envelope, job/cleanup lifecycle, SDK semantics,
Ion binary compatibility, independent Rust/TypeScript evaluation or connected RPCs.

## Wire and semantics

Negotiate the exact draft using the existing bounded JSON-lines transport:

```json
{"id":1,"op":"capabilities","suite":"workbench","contractVersion":"0.1.0-draft.4"}
```

```json
{"id":1,"suite":"workbench","contractVersion":"0.1.0-draft.4","binding":"morphir-moonbit","language":"moonbit","operations":["decode-value","validate-value","validate-invocations","validate-output"],"formats":["json","ion-text"]}
```

Every advertised operation supports every advertised format. The new operation
is valid only under draft.4. Missing operation claims prevent full qualification.

```json
{"id":2,"op":"validate-output","suite":"workbench","contractVersion":"0.1.0-draft.4","format":"json","input":{"value":{"type":"model-error","code":"sdk.division_by_zero"},"type":{"type":"int"},"definitions":[]}}
```

```json
{"id":2,"status":"ok","value":{"type":"model-error","code":"sdk.division_by_zero"}}
```

The input has exactly `value`, `type` and `definitions`. In JSON, `value` is the
existing tagged outcome-value projection. In Ion text, only `value` changes to
one string, for example `morphir_value::{type:"model-error",code:"sdk.division_by_zero"}`.
Declarations stay JSON, using draft.2's closed descriptors and constructor registry.
Malformed declarations remain intentional rejection inputs; the runner never
interprets them or generates expected results from a binding.

Admit the entire declaration graph before decoding the value. Unused definitions,
dormant branches, duplicate identities, missing references and function boundaries
keep draft.2/3 strict semantics. Named recursive custom declarations remain valid.
All existing budgets and diagnostic codes apply, including the 1 MiB compact
input limit, 10,000 declaration nodes, depth 64 and bounded registry dimensions.
Output value decoding/validation retains its separate 100,000-node/UTF-16 budget.
A model error cannot bypass declaration admission or resource limits.

Validate ordinary returned values against the declared type and constructor
registry. This includes empty containers and ordinary typed `Result.Err` values.
Only the five top-level enumerated SDK model errors are admitted without matching
an ordinary returned type: `sdk.division_by_zero`, `sdk.invalid_number`,
`sdk.out_of_range`, `sdk.invalid_comparison`, `sdk.unrepresentable_text`.
Unknown codes, provider/cancellation/cleanup failures and nested model errors
cannot become admitted model outcomes. `validate-value` continues to reject
top-level model errors as arguments. Successful responses retain the canonical
value projection; rejected responses contain the bounded code before the first colon.

## Independent evidence

The [fixed draft.4 corpus](../mck/draft.4/cases.json) contains 291 cases: all 242
historical draft.3 cases plus 49 independently authored output cases. JSON and
Ion text cover exact numbers, Float64 bits, ordinary results, all SDK model-error
codes, unrelated/unknown error codes, nested errors and strict declaration closure.
Custom constructor cases cover named recursion, owner, tag and arity.

The parent runner dispatches explicit operation/draft context, sends no expectations
or case IDs, admits operation-specific projections and compares fixed goldens.
Report checking reloads the exact corpus SHA-256, admitted claims and ordered
case/operation/format inventory, then recomputes qualification. Fixed-observation
replay in runner tests verifies evidence admission only. Binding qualification
requires a real adapter. Report, retained-observation and framing limits are unchanged.

```sh
morphir --no-banner mck workbench run --kit spec/workbench/mck/draft.4 \
  --adapter /path/to/adapter --report .dev/workbench-outputs.json
morphir --no-banner mck workbench check --kit spec/workbench/mck/draft.4 \
  --report .dev/workbench-outputs.json
```

Run `mise run workbench:schema-check` for all four schema catalogs, structural
fixtures and corpus documents. Invoke the MoonBit adapter gate separately for
Node/native debug/release qualification and four-target protocol tests.
