# Workbench declared-value admission

Test contract version: `0.1.0-draft.2`. This exact draft adds bounded declared-value
admission to the shared Rust Workbench MCK runner. The historical
`0.1.0-draft.1` codec contract, schemas and 64-case kit remain unchanged and
supported. Readers never substitute one draft for another. The frozen
`morphir-invocations-v1` and `morphir-outcomes-v1` payloads and connected
`protocolVersion: 1` remain unchanged.

This contract tests a value against an explicit declared type and a closed
constructor registry. It does not load a public entry manifest, infer types,
validate entry visibility or argument arity, execute a function, compare SDK
results, or advertise connected-host RPC support.

## Adapter wire

Use the same bounded UTF-8 JSON-lines transport and correlation identifiers as
[draft.1](../mck/README.md). Negotiate this exact draft first:

```json
{"id":1,"op":"capabilities","suite":"workbench","contractVersion":"0.1.0-draft.2"}
```

```json
{"id":1,"suite":"workbench","contractVersion":"0.1.0-draft.2","binding":"morphir-moonbit","language":"moonbit","operations":["decode-value","validate-value"],"formats":["json","ion-text"]}
```

The operation and format arrays are independent unique claims. Every advertised
operation must support every advertised format. Missing claims produce unsupported
cases and prevent full qualification. Unknown claims and a response with another
draft version fail negotiation. `decode-value` retains its existing projection
semantics; `validate-value` supports both JSON and Ion text values.

```json
{"id":2,"op":"validate-value","suite":"workbench","contractVersion":"0.1.0-draft.2","format":"json","input":{"value":{"type":"int","value":"0007"},"type":{"type":"int"},"definitions":[]}}
```

```json
{"id":2,"status":"ok","value":{"type":"int","value":"7"}}
```

For `format: "ion-text"`, only `input.value` changes to a single Ion text string,
for example `"7"`. The declared type and definitions remain JSON. Unexpected Ion
annotations, duplicate value fields and malformed Ion text are rejected by the
existing value codec. Invalid values return `{"id":2,"status":"invalid","code":"…"}`.

The input envelope has exactly `value`, `type` and `definitions`. There is no
output-admission switch: an SDK model error is forbidden as an argument.
`Result.Err` remains an ordinary value whose error branch has a declared type.
A successful observation contains the canonical decoded JSON projection, not a
boolean, an inferred type or a normalized Decimal comparison result.

Malformed declaration inputs remain representable in the MCK request/corpus
schemas so independent negative cases can reach the adapter. The separate
[value-type schema](schemas/value-type.schema.json) and
[definitions schema](schemas/definitions.schema.json) describe well-formed shapes.
JSON Schema alone does not establish unique names, UTF-16 identity limits,
aggregate budgets or complete reference closure.

## Declared types and registry

Primitive descriptors contain only `type`, one of `int`, `bool`, `unit`,
`decimal`, `float64`, `text` or `character`. Other descriptors are:

| Type | Additional members |
| --- | --- |
| `list`, `maybe` | `item`, a declared type |
| `tuple` | `items`, an ordered array of declared types |
| `record` | `fields`, an array of `{name, type}` entries with distinct names |
| `custom` | `name`, the constructor owner identity |
| `result` | `ok` and `err`, the two declared branch types |
| `function` | None; always rejected at this boundary |

All descriptors are closed. Definitions are an array of closed
`{name, constructors}` entries, and constructors are closed `{name, inputs}`
entries. Definition names are unique across the registry. Constructor names are
unique within their definition. The registry has no inferred definitions or
parameter substitution. Custom references recurse by name; finite mutually
recursive and self-recursive definitions are allowed.

Admission checks the compact input byte budget first, then parses the root type
and definitions in array order with a shared budget. Function descriptors are
rejected wherever encountered. Once all shapes are admitted, every custom type
reference in the root and every definition input must name an existing registry
entry, including unused definitions and dormant branches. Named cycles do not
consume inline descriptor depth. Only after that closure check does the adapter
decode the supplied value and apply the shipped `validate_as` semantics.

This closure guard is new bounded adapter admission. The older `validate_as`
function alone validates only branches reached through a concrete value; it does
not establish whole-registry closure. An empty list, `Nothing` or an unselected
Result branch therefore still requires a closed declared type under this draft.

## Limits and rejection codes

- The entire compact `input` JSON encoding is at most 1 MiB, including an escaped
  Ion text value, the declared type and registry. Overflow is `workbench.input_limit`.
- Inline type depth is at most 64, counting the root descriptor at depth zero.
  Each registry input starts at depth zero. A shared budget admits at most 10,000
  descriptor/record-field/definition/constructor nodes across the root and registry.
- At most 256 definitions, 256 constructors per definition, 64 constructor inputs,
  and 1,024 fields/items per record/tuple descriptor are admitted.
- Every field, custom owner, definition and constructor name contains 1 to 1,024
  UTF-16 code units. Duplicate names are rejected in their respective scopes.
- Type depth, aggregate node, dimension or identity upper-bound overflow is
  `workbench.type_limit`. Malformed descriptors and duplicate declared record
  fields are `workbench.invalid_type`. Malformed or duplicate definition and
  constructor envelopes are `workbench.invalid_definitions`. A malformed
  constructor input descriptor remains `workbench.invalid_type`.
- Any function descriptor is `execution.boundary_function`. Any unresolved
  custom name is `execution.unresolved_custom_type`.
- The existing value codec limits remain: depth 64, 100,000 aggregate value
  nodes/UTF-16 units, 10,000-character integer strings, exact UInt64 Float64 bits,
  bounded constructor identities and normalized Decimal admission.

Typed value mismatch retains the shipped stable codes:
`execution.wrong_type`, `execution.tuple_arity`,
`execution.missing_record_field`, `execution.extra_record_field`,
`execution.constructor_owner`, `execution.constructor_tag`,
`execution.constructor_arity` and `execution.model_error_argument`.
Codec rejections remain unchanged. Malformed Ion text is `workbench.invalid_ion`.
Only the bounded code before the first colon is returned; input names and paths
are diagnostic details. Transport failures and unexpected runtime failures do
not become model errors or admitted values.

## Corpus and evidence

The explicit [draft.2 kit](../mck/draft.2/cases.json) has 162 cases: 64 historical
codec inputs/goldens plus 98 independently authored admission cases. It covers
JSON/Ion equivalence, primitive and container types, empty values, exact record
fields, recursive ADTs, constructor identity and arity, dormant closure,
function rejection, model errors, malformed declarations and structural budgets.
The corpus never derives expected answers by calling an implementation.

Draft.2 cases and report records carry an explicit `operation`. Draft.1 records
retain their original wire shape with implicit `decode-value`. The runner sends
only the operation, selected draft, format and input, never case IDs or goldens.
Saved report checking reloads the exact corpus bytes and ordered
case/operation/format inventory, re-admits same-draft capabilities and observations,
and recomputes verdicts and qualification. An admitted value cannot be a top-level
model error. Report checking validates evidence consistency, not report origin.

Both drafts retain the 16 MiB corpus, 1,024 cases, 1 MiB per input/projection,
16 MiB retained observations, 32 MiB report and 127-container JSON framing limits.
Draft.2 measures every operation input in its compact JSON encoding; draft.1
retains its original raw UTF-8 Ion text input bound. The corpus loader rejects
oversized requests before spawning an adapter; adapter
`workbench.input_limit` behavior therefore requires direct protocol tests rather
than an oversized executable corpus case.

```sh
morphir --no-banner mck workbench run \
  --kit spec/workbench/mck/draft.2 --adapter /path/to/adapter \
  --report .dev/workbench-admission.json
morphir --no-banner mck workbench check \
  --kit spec/workbench/mck/draft.2 --report .dev/workbench-admission.json
```

Run `mise run workbench:schema-check` for both offline schema catalogs,
structural tests and both actual corpus documents. Use
`cargo test --locked -p morphir-mck --lib workbench` and
`cargo test --locked -p morphir --test mck_workbench` for runner and CLI boundaries.
Ion binary, reverse encoding, independent Rust/TypeScript adapters, public entry
manifest admission, host negotiation and evaluation remain separate follow-up work.
