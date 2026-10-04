# Workbench invocation admission

Test contract version: `0.1.0-draft.3`. This exact draft adds public-entry invocation
admission to the shared Rust Workbench MCK runner. Historical draft.1 and draft.2
contracts, schemas, cases and kits remain unchanged and supported. The frozen
`morphir-invocations-v1` and `morphir-outcomes-v1` payload IDs and connected
`protocolVersion: 1` remain unchanged.

This is an offline admission test. It accepts an explicitly supplied public-entry
allowlist, checks complete declarations and validates existing invocation values.
It does not derive an allowlist from a model, prove that a supplied entry is public
in an actual model, execute a function, acquire a provider, admit output values,
compare SDK results or advertise a connected RPC method.

## Adapter wire

Use the existing bounded UTF-8 JSON-lines transport and safe-integer correlation
identifiers. Negotiate this exact draft before dispatch:

```json
{"id":1,"op":"capabilities","suite":"workbench","contractVersion":"0.1.0-draft.3"}
```

```json
{"id":1,"suite":"workbench","contractVersion":"0.1.0-draft.3","binding":"morphir-moonbit","language":"moonbit","operations":["decode-value","validate-value","validate-invocations"],"formats":["json","ion-text"]}
```

Every advertised operation supports every advertised format. Claims are unique,
closed and tied to the exact selected draft. Missing claims skip cases and prevent
full qualification. Operations added by a later draft cannot be advertised or
used under an older draft. `decode-value` and `validate-value` keep their draft.2
semantics; `validate-invocations` adds the following request:

```json
{"id":2,"op":"validate-invocations","suite":"workbench","contractVersion":"0.1.0-draft.3","format":"json","input":{"suite":{"profile":"morphir-invocations-v1","calls":[{"id":"c","entry":"demo:main#identity","arguments":[{"type":"int","value":"007"}]}]},"manifest":{"entries":[{"name":"demo:main#identity","inputs":[{"type":"int"}],"output":{"type":"int"}}],"definitions":[]}}}
```

```json
{"id":2,"status":"ok","value":{"profile":"morphir-invocations-v1","calls":[{"id":"c","entry":"demo:main#identity","arguments":[{"type":"int","value":"7"}]}]}}
```

For `format: "ion-text"`, only `input.suite` changes to one Ion text string. The
manifest remains JSON. For example:

```ion
{profile:"morphir-invocations-v1",calls:[{id:"c",entry:"demo:main#identity",arguments:[7]}]}
```

The input envelope contains exactly `suite` and `manifest`. The manifest contains
exactly `entries` and `definitions`. Each public-entry descriptor contains exactly
`name`, ordered `inputs` and `output`; there is no visibility flag. Entries are an
allowlist with unique bounded names. An empty allowlist is valid but cannot admit
any call from a nonempty suite. Missing selected entries return
`execution.entry_not_public_or_supported`; exact argument-count mismatch returns
`execution.wrong_arity`.

Types and constructor definitions use the [draft.2 descriptors](../draft.2/README.md),
with the same closed shapes and registry limits. Parse all entries in array order,
parsing each input in order and then its output, followed by definitions. Admit the
complete declaration graph before decoding the suite. This includes unused
entries, unused definitions and dormant branches. All custom references must name
a supplied definition; named recursive cycles remain valid. Function descriptors
are forbidden in inputs, outputs and registry constructors. Admitting an output
*declaration* does not test an output *value*.

After declaration admission, use the existing suite codec and its validation,
then public-entry lookup, exact arity and declared argument validation in call
order. SDK model errors cannot be arguments; ordinary typed `Result.Err` values
remain admissible. A successful observation contains the canonical decoded
`Suite::to_json` projection, including call identities and ordered arguments.
Failures return only the stable bounded code, before the first colon.

## Limits and projection

- The entire compact `input` JSON encoding is at most 1 MiB, including escaped Ion
  text and all manifest declarations. Overflow is `workbench.input_limit`.
- At most 1,000 public entries are admitted. Each name is 1–1,024 UTF-16 code units;
  names are unique. Each entry has at most 64 inputs and one required output.
- Type depth remains 64 with every input, output and constructor input starting at
  depth zero. The shared 10,000-node declaration budget counts every entry, type
  descriptor, record-field descriptor, definition and constructor.
- Draft.2 registry and descriptor dimensions remain: 256 definitions, 256
  constructors per definition, 64 constructor inputs, 1,024 tuple items/record
  fields and 1–1,024 UTF-16 units per declaration identity.
- Declaration dimension, identity, depth and node overflow is
  `workbench.type_limit`. Malformed manifest/entry envelopes, duplicate entries
  and empty entry names are `workbench.invalid_manifest`. Descriptor and registry
  errors retain draft.2 codes; missing references and functions retain
  `execution.unresolved_custom_type` and `execution.boundary_function`.
- Existing suite limits remain: 1–1,000 calls, distinct nonempty call IDs of at most
  128 UTF-16 units, entry identities of at most 1,024 units, 64 arguments per call,
  value depth 64 and 100,000 aggregate value nodes/UTF-16 units **per call**, shared
  across arguments. Codec integer, Decimal, Float64 and constructor limits remain.
- Optional extensions remain at most 64 KiB of Ion binary. JSON supplies the
  existing `{format:"ion-binary",bytes:[...]}` projection, and those bytes survive
  exactly. Ion text supplies an Ion metadata value whose projection uses the
  adopted suite codec's Ion binary writer. The tiny fixed null-extension golden
  checks that adopted projection only; it establishes no general canonical Ion
  binary, reverse-encoding or cross-implementation binary compatibility claim.

The runner structurally validates successful invocation projections against the
historical invocation and argument-value schemas. It checks unique call IDs,
UTF-16 identity limits, canonical numeric strings and the per-call aggregate
budget. Nested model-error values cannot appear in argument projections. The
runner does not decode input suites, manifests or extension binaries, nor does it
produce expected answers from an implementation. Extension bytes are bounded,
opaque evidence compared exactly. Call and argument order remain significant;
record fields compare by name recursively. Numeric comparison follows the existing
codec projection rules, including exact Decimal scale and Float64 bits.

## Fixed corpus and evidence

The [explicit draft.3 kit](../mck/draft.3/cases.json) has 242 cases: the 162 fixed
historical draft.2 cases plus 80 independently authored invocation cases. The new
cases cover JSON/Ion success and rejection, rich/recursive values, ordinary
`Result.Err`, public allowlist and arity, malformed suites/manifests, complete
closure, identity and structural limits, exact aggregate budgets, and narrow
extension projection. Large repetitive fixtures use compact formatting; their
exact bytes remain part of report identity.

Requests contain only operation, selected draft, format and input, never case IDs
or expected results. Cases and report records carry explicit operations. Report
checking reloads the exact corpus SHA-256 and ordered case/operation/format
inventory, re-admits exact-draft capabilities and operation-specific observations,
and recomputes every verdict and qualification. Replaying fixed observations in
runner tests verifies evidence handling, not implementation qualification.

All drafts retain the 16 MiB corpus, 1,024-case, 1 MiB per input/projection, 16 MiB
retained-observation, 32 MiB report and 127-container JSON framing limits. The corpus
loader rejects oversized input before adapter launch; direct adapter protocol
tests establish `workbench.input_limit` responses for oversized requests.

```sh
morphir --no-banner mck workbench run \
  --kit spec/workbench/mck/draft.3 --adapter /path/to/adapter \
  --report .dev/workbench-invocations.json
morphir --no-banner mck workbench check \
  --kit spec/workbench/mck/draft.3 --report .dev/workbench-invocations.json
```

Run `mise run workbench:schema-check` for all three offline schema catalogs,
structural fixtures and corpus documents. Runner and subprocess tests use
`cargo test --locked -p morphir-mck --lib workbench` and
`cargo test --locked -p morphir --test mck_workbench`.

Output-value admission, evaluation, SDK comparisons, independent adapters,
Ion binary compatibility and connected-host negotiation remain follow-up work.
