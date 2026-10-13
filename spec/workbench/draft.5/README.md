# Terminal outcome admission draft

Exact `0.1.0-draft.5` adds `validate-outcomes` to the four [draft.4 operations](../draft.4/README.md).
Earlier drafts and their fixed corpora remain unchanged. Generated-driver
`morphir-outcomes-v1` and connected `protocolVersion: 1` remain unchanged.

This operation admits supplied terminal evidence against a public-entry manifest
and an invocation suite. Admission does not authenticate the producer, invoke a
function, prove live cancellation, or qualify an actual host lifecycle. A response
with `status: "ok"` means valid evidence, including failed or cancelled calls.

## Wire and admission order

Use the existing bounded JSON-lines transport and negotiate the exact draft:

```json
{"id":1,"op":"capabilities","suite":"workbench","contractVersion":"0.1.0-draft.5"}
```

```json
{"id":1,"suite":"workbench","contractVersion":"0.1.0-draft.5","binding":"morphir-moonbit","language":"moonbit","operations":["decode-value","validate-value","validate-invocations","validate-output","validate-outcomes"],"formats":["json","ion-text"]}
```

Every advertised operation supports every advertised format. `validate-outcomes`
is unavailable under earlier drafts. Input has exactly `suite`, `manifest` and
`outcomes`. Suite and manifest use the existing JSON representations in both
formats. Only `outcomes` becomes an Ion-text string when format is `ion-text`.

```json
{"id":2,"op":"validate-outcomes","suite":"workbench","contractVersion":"0.1.0-draft.5","format":"json","input":{"suite":{"profile":"morphir-invocations-v1","calls":[{"id":"first","entry":"demo:main#run","arguments":[]}]},"manifest":{"entries":[{"name":"demo:main#run","inputs":[],"output":{"type":"int"}}],"definitions":[]},"outcomes":{"contractVersion":"0.1.0-draft.5","calls":[{"id":"first","outcome":{"status":"returned","value":{"type":"int","value":"42"}}}],"cleanup":null,"extensions":null}}}
```

Admit the entire declaration graph, including unused definitions and dormant
branches, before decoding outcomes. Then admit the invocation suite, public-entry
membership and every argument. Public entries are supplied explicitly; the
operation never infers visibility from names. Failed or cancelled evidence cannot
bypass missing custom declarations, function boundaries or wrong arguments.
Finally decode and admit the terminal envelope and validate returned outputs.

## Closed terminal envelope

All four fields are required: `contractVersion`, `calls`, `cleanup`, `extensions`.
There must be exactly one call per admitted invocation, with matching IDs in the
submitted order. Reject duplicate, missing, extra or swapped calls. Each call has
exactly `id` and `outcome`. Each outcome is exactly one of:

| Status | Required additional fields | Meaning |
| --- | --- | --- |
| `returned` | `value` | Ordinary typed value checked against the entry output. Typed `Result.Err` remains returned data. |
| `model-error` | `code` | One of the five existing SDK model-error codes. |
| `failed` | `failure` | Primary acquire/build/invoke/evaluate/compare failure. |
| `cancelled` | None | Supplied terminal cancellation claim. |

The SDK codes are `sdk.division_by_zero`, `sdk.invalid_number`, `sdk.out_of_range`,
`sdk.invalid_comparison` and `sdk.unrepresentable_text`. A top-level model-error
value is forbidden under `returned`; it requires the `model-error` variant.
Nested model errors remain invalid ordinary values. Unknown model-error codes
reject. Primary failures cannot use these SDK codes or `execution.cancelled`.
Unknown provider codes can remain primary failures without becoming model errors.
Nonterminal states, contradictory payloads and unknown fields reject.

A failure descriptor has exactly `stage`, `code`, `message`. Primary stages are
`acquire`, `build`, `invoke`, `evaluate`, `compare`. `cleanup` is null or a failure
descriptor whose stage is exactly `cleanup`. A cleanup failure can accompany any
terminal inventory. It never overwrites the primary failure, cancellation or
returned value. There is no redundant successful boolean.

JSON values use the existing canonical tagged value projection. Ion values use
the published value codec: native integers, booleans and decimals; Float64 and
compound values use `morphir_value` with tagged children. For example:

```ion
{contractVersion:"0.1.0-draft.5",calls:[{id:"first",outcome:{status:"returned",value:morphir_value::{type:"float64",bits:"9223372036854775808"}}}],cleanup:null,extensions:null}
```

This preserves signed-zero and NaN bits, exact integers, decimal coefficient and
exponent, UTF-16 units and ordinary typed results. Record fields compare by name;
call order and extension byte order remain significant.

Extensions are absent as unannotated untyped null, or opaque Ion binary bytes.
JSON uses `{format:"ion-binary",bytes:[...]}`; Ion uses a blob. Validate the bounded
binary payload and require an exact byte echo of the admitted suite. Do not decode
and reserialize metadata. A blob containing encoded Ion null differs from absence.
This operation does not claim general Ion binary or reverse-encoding qualification.

## Limits and diagnostics

Retain the 1 MiB compact input limit, 1,000-call limit, strict declaration depth 64
and 10,000-node budget, and existing declaration dimensions. IDs contain 1–128
UTF-16 units. Each returned value retains the 100,000-node/UTF-16 budget and depth
64. Failure codes contain 1–128 UTF-16 units; messages contain 0–512. Extension
bytes are limited to 65,536. Wire framing and report limits remain unchanged.

Malformed terminal/root or variant fields use `workbench.invalid_outcomes` or
`workbench.invalid_outcome`; failure descriptors use `workbench.invalid_failure`.
Inventory count uses `execution.result_count`; duplicate or mismatching IDs use
`execution.call_identity`; extension mismatch uses `execution.outcome_extensions`.
Existing value, declaration, manifest, invocation, annotation, extension and Ion
parse diagnostics retain their meaning. Rejections expose only the bounded code
before the first colon. Declaration and invocation errors precede outcome decoding.

## Independent evidence

The [fixed draft.5 corpus](../mck/draft.5/cases.json) has 377 cases: all 291
historical draft.4 cases unchanged, plus 86 independently authored terminal cases.
JSON and Ion cover exact values, typed Result.Err, all SDK codes, primary stages,
cleanup with each variant, cancellation, inventory/order, opaque metadata,
declaration precedence, malformed fields and UTF-16 limits.

The single shared Rust runner sends no expectations or case IDs. It admits an
operation-specific terminal projection, retains ordered identities and cleanup,
and compares against fixed goldens. Report checking reloads the exact corpus
SHA-256, capabilities and case/operation/format inventory, then recomputes verdicts.
Runner replay tests validate evidence admission only. Real adapters qualify binding
behavior. UI adoption, live job transitions and cancellation acknowledgement,
producer authentication, SDK semantics and connected negotiation are subsequent work.

```sh
morphir --no-banner mck workbench run --kit spec/workbench/mck/draft.5 \
  --adapter /path/to/adapter --report .dev/workbench-outcomes.json
morphir --no-banner mck workbench check --kit spec/workbench/mck/draft.5 \
  --report .dev/workbench-outcomes.json
```

Run `mise run workbench:schema-check` for all five catalogs, structural fixtures
and corpus documents. The MoonBit gate separately qualifies Node/native debug
and release adapters and pure protocol tests on JS/native/Wasm/Wasm GC.
