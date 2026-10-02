# Workbench typed value profile

Schema package version: `0.1.0-draft.1`. Status: proposed adoption of the MoonBit
execution codecs. Draft readers support only an explicitly listed exact draft.
Schema identifiers identify this draft package; they are not an announcement of
deployed URLs or runtime support.

This first contribution records existing typed model values and invocation JSON.
It preserves the payload codec ID `morphir-invocations-v1`. No `formatVersion` field
is added to that frozen document. A future negotiated transport profile will use
Morphir's SemVer contract rules and explicitly map these existing codec IDs.

The existing Rust connected host stays at `protocolVersion: 1`, with its existing
compile, generate and workspace methods. This contribution defines no RPC method,
job receipt or capability claim. Clients must keep connected evaluation and server
cancellation unavailable until the host implements and advertises an agreed
extension. Compile output and generation must use the same negotiated IR version,
even when a client migrates a copy for local inspection.

## JSON values

`schemas/value.schema.json` describes model values admitted as typed arguments.
Every value is tagged. JSON numeric values cannot replace exact integer strings or
Float64 bit strings.

| Type | Payload |
| --- | --- |
| `int` | `value`, a signed base-10 integer string |
| `bool` | `value`, a JSON boolean |
| `unit` | No payload |
| `decimal` | `coefficient`, an integer string, and integer `exponent` |
| `float64` | `bits`, a base-10 string representing the unsigned 64-bit pattern |
| `text`, `character` | `units`, an array of UTF-16 code units from 0 to 65535 |
| `list`, `tuple` | `items`, recursively tagged values |
| `record` | `fields`, an array of `{name, value}` entries |
| `custom` | `owner`, `tag` and `items`; the public type registry governs admission |
| `maybe` | `case: "nothing"`, or `case: "just"` with `value` |
| `result` | `case: "ok"` or `case: "err"`, with `value` |

Float64 patterns preserve signed zero, infinities, subnormals and NaN payloads.
Text does not convert through a Unicode string. Isolated surrogates survive;
Character may contain multiple units after an SDK case expansion. Empty containers
do not infer their declared types. Constructor owner, tag and arity are checked
against the public manifest and registry. Boundary function values are unsupported.

The existing integer decoder accepts leading zeroes and negative zero. The encoder
emits the canonical integer spelling. Exact integer input strings have a maximum
length of 10,000 characters, including a minus sign. Schema string lengths count
Unicode code points; the implementation's identity budgets count UTF-16 units, so
the decoder must still enforce those identity limits.

Decimal represents `coefficient * 10^exponent`. Input exponents range from -10,000
to 10,000. Semantic admission removes trailing coefficient zeroes, then requires
the normalized exponent to be from -32 to 10,000. A zero coefficient normalizes to
exponent zero. For example, coefficient `"10"` with exponent `-33` is admissible
after normalization, while coefficient `"1"` with exponent `-33` is rejected.
Comparison normalizes decimals without truncating them through the SDK.

`schemas/outcome-value.schema.json` admits a typed model value or a top-level
`model-error` with one of these codes:

- `sdk.division_by_zero`
- `sdk.invalid_number`
- `sdk.out_of_range`
- `sdk.invalid_comparison`
- `sdk.unrepresentable_text`

`Result.Err` is an ordinary model value. A `model-error` is a captured, enumerated
SDK failure. Provider crashes, validation, transport, cancellation, deadlines and
cleanup failures belong to host execution status. They must not become model
errors or successful results. This outcome-value schema does not describe the
`morphir-outcomes-v1` report envelope or authoritative job state.

## Invocation suites and Ion

`schemas/invocations.schema.json` records the existing JSON projection. A suite
has profile `morphir-invocations-v1` and a nonempty `calls` array. Each call has a
nonempty unique `id`, an `entry` and tagged `arguments`. The engine validates
entry visibility, argument arity and declared types before acquiring a provider.

Ion text and binary encode Int, Bool and Decimal with native Ion types; Unit is
`morphir_unit::null`. Other values use one `morphir_value` annotation on a tagged
struct. Nested values in that struct use the same tagged payload fields as JSON,
without nested annotations. Ion floats and strings are not substitutes for
Float64 bits or UTF-16 unit payloads. Unexpected annotations are rejected.

Optional suite `extensions` hold arbitrary Ion metadata outside semantic values
and semantic identity. Their JSON projection is `{format: "ion-binary", bytes:
[...]}`. The decoder validates one Ion binary value; execution echoes and verifies
the bytes before reporting. Metadata is not an untyped escape hatch inside values.

The source implementation rejects unknown members in these frozen codec payloads.
The draft schemas retain that rule. This does not change Morphir's rule that new
released SemVer contracts ignore unknown members unless marked critical. Evolving
the legacy payload requires an explicit codec mapping or a new negotiated contract,
rather than adding unrecognized members to the existing document.

## Validation boundaries

Run `mise run workbench:schema-check`. This uses the repository's existing JSON
Schema CLI to check formatting, lint, metaschemas and positive/negative structural
fixtures. It is not a semantic compatibility runner or evidence that Rust and
TypeScript implement these codecs.

After structural validation, a decoder and the execution engine must enforce:

- 1 MiB encoded suite size, at most 1,000 calls and 64 arguments per call.
- Distinct call IDs; identity limits of 128 UTF-16 units for IDs and 1,024 for
  entry, constructor and record-field names.
- Depth at most 64 and an aggregate budget of 100,000 value nodes/code units per
  call. Individual schema array limits do not establish that aggregate bound.
- Exact integer bounds, normalized Decimal admission and unsigned Float64 bits
  no greater than `18446744073709551615`.
- Unique record field names and exact declared fields; constructor ownership and
  arity; recursive registry and declared argument types.
- At most 64 KiB of extensions, containing a valid Ion binary value.

The accepted and rejected structural fixtures are language-neutral. Semantic
fixtures, Ion/JSON roundtrip goldens, comparisons and execution receipts belong in
the shared Rust `morphir mck` runner through explicit implementation adapters.
There is no second compatibility checker here. Complete the shared fixture
intersection and connected host acceptance before advertising an extension.

## Source and next contribution

The source is finos/morphir-moonbit at merged PR #36 revision
`fd4026eff313ed0d94f7e9ccb3ec79a63864f1e0`:

- [Invocation codec and limits](https://github.com/finos/morphir-moonbit/blob/fd4026eff313ed0d94f7e9ccb3ec79a63864f1e0/pkgs/morphir-execution/values.mbt)
- [Typed value codec and manifest admission](https://github.com/finos/morphir-moonbit/blob/fd4026eff313ed0d94f7e9ccb3ec79a63864f1e0/pkgs/morphir-execution/rich_values.mbt)
- [Execution contract documentation](https://github.com/finos/morphir-moonbit/blob/fd4026eff313ed0d94f7e9ccb3ec79a63864f1e0/pkgs/morphir-execution/README.md)

Local Workbench
input controls and result display trees are private UI projections and are not
part of the profile. The parent connected-protocol inventory was inspected at
`90f7df0a125acc27db45a4b98d2b2883ba0ec471`. The JSON examples are codec documents;
execution also requires the corresponding model and public entry manifest.

The next slice maps full invocation manifests, outcomes and lifecycle receipts,
then adds shared MCK fixtures and Rust/TypeScript/MoonBit adapter acceptance.
Model/revision handles, worksheet source maps, job query/cancellation/recovery,
artifact publication and provider availability require coordinated host and UI
contracts. Required results remain separate from observational telemetry.
