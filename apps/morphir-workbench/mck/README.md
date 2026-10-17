# Workbench MCK adapter

This component exposes the shipped `finos/morphir-execution` value codec and
validator to the shared Rust MCK. It supports exact contracts
`0.1.0-draft.1` through `0.1.0-draft.7`. It has no goldens, evaluator or separate
conformance runner. The parent `finos/morphir` repository owns the specification,
corpora and verdict calculation. Draft.1/.2 are merged; draft.3 adds invocation
admission; draft.4 adds output admission; draft.5 adds terminal outcome admission.

`protocol.mbt` handles capabilities and `decode-value`, echoes correlation IDs
and rejects unknown/duplicate JSON members. Draft.1 capabilities and its original
64-case corpus remain unchanged. JSON calls `Value::from_json`; Ion text calls
the Ion parser and `Value::from_ion`. Both return `Value::to_json`, preserving
exact numbers, Float64 bits and UTF-16 units. Successful decode of a model error
is an outcome projection, without argument admission.

Draft.2 also supports `validate-value` in both formats. Its `input` has exactly
`value`, `type` and `definitions`. `value` is tagged JSON or a single Ion text
value according to `format`. The type and registry use JSON descriptors matching
`ValueType::to_json` and the generated constructor definitions:

```json
{"value":{"type":"int","value":"9007199254740993"},
 "type":{"type":"int"},"definitions":[]}
```

`admission.mbt` parses closed declarations before decoding the value and calling
the shipped `validate_as`. Every custom owner referenced anywhere in the graph
must be declared, including dormant Maybe/Result branches and unused definitions.
Named recursion is allowed without expanding declarations. Function types are
rejected throughout the graph. Record-field, definition and constructor names
must be unique within their containing declaration. A top-level model error is
forbidden as an argument; ordinary `Result.Err` values remain admissible.
Successful admission returns the canonical value projection, without evaluation.

Draft.3 retains both value operations and adds `validate-invocations`. Its input
is exactly `{suite,manifest}`. `suite` is the existing `morphir-invocations-v1`
JSON object or one Ion text string. `manifest` is exactly `{entries,definitions}`;
entries are `{name,inputs,output}` and definitions use the draft.2 shape.
The supplied entries form a public/supported allowlist. This tests membership
against that list, without inferring hidden declarations or model visibility.

```json
{"suite":{"profile":"morphir-invocations-v1","calls":[
  {"id":"c","entry":"identity","arguments":[{"type":"int","value":"007"}]}
]},"manifest":{"entries":[
  {"name":"identity","inputs":[{"type":"int"}],"output":{"type":"int"}}
],"definitions":[]}}
```

Every entry input/output and unused registry declaration is admitted before
suite decoding. Duplicate entry names and malformed manifest shapes use
`workbench.invalid_manifest`. There are at most 1,000 entries, 64 inputs per
entry and 1–1,024 UTF-16 units per name. Entry nodes share the declaration budget.
The adapter then uses the shipped Suite codec and shared `validate_invocations`,
also used by the engine. Missing entries return
`execution.entry_not_public_or_supported`; arity returns `execution.wrong_arity`.
Argument errors retain the existing typed validation codes.

Success contains the canonical `Suite::to_json` under `value`, preserving ordered
calls/arguments and JSON extension bytes. Calls retain shipped identity, arity,
value and extension limits. The parent compares records by field name but keeps
call and argument order. Tiny Ion extension fixtures specify their binary
projections; this is not general Ion binary or reverse-encoding qualification.

The complete compact input envelope is limited to 1 MiB of UTF-8 JSON. Type
parsing allows depth 64 and 10,000 aggregate nodes, counting type descriptors,
record-field descriptors, registry definitions and constructors. Registries allow
256 definitions, 256 constructors per definition and 64 inputs per constructor;
tuples and records allow 1,024 entries. Identities allow 1–1,024 UTF-16 units.
Value codec/type validation retains its separate existing budgets. The wire's
127-container JSON framing limit can be stricter than logical type depth.

Malformed declarations use `workbench.invalid_type` or
`workbench.invalid_definitions`; declaration budget violations use
`workbench.type_limit`; excess input bytes use `workbench.input_limit`.
Unresolved custom references and function boundaries use the existing
`execution.unresolved_custom_type` and `execution.boundary_function` codes.
Execution diagnostics retain only the code before the first colon. Malformed
Ion uses `workbench.invalid_ion`. Exit closes stdout without an observation.
Node/native launchers bound input lines at 2 MiB; the parent owns deadlines,
process supervision and report rechecking.

From the repository root, select a built parent runner and its offline corpus:

```sh
MORPHIR_MCK_BIN=/path/to/finos/morphir/target/debug/morphir \
MORPHIR_WORKBENCH_KIT=/path/to/finos/morphir/spec/workbench/mck/draft.3 \
mise run test:workbench-mck
```

Choose `spec/workbench/mck` or `spec/workbench/mck/draft.2` to requalify the unchanged
earlier corpora. The gate
builds Node/native debug and release adapters, rechecks every saved report through
the parent command and writes evidence beneath `.dev/workbench-mck/`. Pure
protocol tests run on JS, native, Wasm and Wasm GC. No upstream checkout, model or
toolchain is downloaded. Live execution, SDK comparison,
general Ion binary or reverse encoding remain separate work. These offline
operations advertise no connected-host protocol extension.

## Declared output admission

Exact draft.4 adds `validate-output` with the same closed `value`, `type` and
`definitions` input as `validate-value`. Complete declaration admission precedes
decoding, then the shipped `validate_as(output=true)` checks returned values.
Only the five recognized top-level SDK model errors bypass ordinary type matching.
Typed `Result.Err` must match its declared error type; nested model errors and
provider/cancellation/cleanup codes reject. Argument admission remains unchanged.
The new operation is unavailable under earlier drafts. The parent owns independent
goldens, corpus inventory and report rechecking; no connected RPC is advertised.
Select `spec/workbench/mck/draft.4` with the existing gate to qualify this draft.
Live job lifecycle and authoritative cleanup behavior remain separate.

## Terminal outcome admission

Exact draft.5 adds `validate-outcomes` with closed `{suite,manifest,outcomes}`
input. Suite and manifest stay JSON in both formats; outcomes is a tagged JSON
envelope or Ion-text string. Strict declaration and argument admission precede
outcome decoding. The portable `Outcomes` codec preserves ordered call IDs and
`returned`, enumerated `model-error`, primary `failed`, or `cancelled` evidence,
with a separate optional cleanup failure. It validates returned values against
entry outputs and requires exact opaque extension-byte echo. Typed Result.Err
remains returned data. Contradictory/nonterminal shapes, wrong inventory/order,
invalid stages, reserved failure codes and resource violations reject.

Select `spec/workbench/mck/draft.5` with the existing gate for the upstream
377-case corpus. The parent owns the specification, independent expectations
and all verdicts. Pure codec tests cover round trips, duplicate fields, typed
null/annotations, UTF-16 and value budgets. Earlier exact drafts remain supported.
Admission of failed/cancelled evidence means valid evidence, not successful or
authenticated execution. UI adoption, live daemon jobs, acknowledged cancellation
and connected protocol extensions remain subsequent work.

## Job transition qualification

Exact offline MCK draft.6 advertises only `reduce-job` and JSON. It maps the
unchanged `morphir/workbench/jobs` `0.1.0-draft.1` profile and its nested draft.5
terminal outcomes. It does not add operations to the five historical drafts or
define an Ion receipt mapping. Requalify historical kits separately.

Input is exactly `{offer,identity,calls,initial,actions}`. The adapter admits the
offer, caller-owned expected identity, ordered call IDs and initial submitted
receipt through `finos/morphir-execution/jobs`. It preadmits closed action syntax
before executing up to 64 actions. Actions are `observe` with a receipt,
`reconnect` with an offer, `disconnect`, or `cancel-action`. Invalid receipt or
offer payloads produce a bounded per-action rejection and leave the cursor
unchanged. A malformed trace/action shape rejects the entire operation.

The canonical observation retains the final identity, complete latest receipt,
connection availability, cancellation action and ordered step observations.
Each step includes its operation, disposition or rejection code, and a bounded
view of sequence, state, acknowledgement, connection and cancellation action.
Values and cleanup appear only in the final receipt, not in every view. Input
and output are each capped at 1 MiB. The parent owns all fixed expectations,
observation admission, comparisons and report rechecking. No expected data or
case ID is sent to this adapter.

Select `spec/workbench/mck/draft.6` with the existing gate. Set
`MORPHIR_WORKBENCH_EVIDENCE` to retain reports in a separate directory per kit;
the default remains `.dev/workbench-mck/`. This qualifies recorded transitions,
replay/conflict handling, cancellation races and same-session reconciliation.
It does not authenticate receipts or qualify live job RPC, host execution,
durable recovery, Proton IPC or generated browser execution.

## Native request-frame qualification

Exact offline draft.7 advertises only `validate-native-frame` and JSON. It
uses `finos/morphir-workbench-native-session/request`, the portable native
draft.1 request decoder. Select `spec/workbench/mck/draft.7` with the same
parent-owned gate. Historical kits are qualified separately.

Input is exactly `{encoding,source}`, with optional
`generate:{prefix:{repeat:" ",count}}`. Encoding is `utf8` or complete hex
byte pairs. The optional count is an exact integer from zero to 1,048,576,
including integral decimal/exponent spellings. Compact input is limited to
1 MiB and materialization to 2 MiB before calling the decoder. Malformed fixture
envelopes terminate the adapter as infrastructure failures, rather than yielding
a native rejection. The new draft preserves original compact number tokens.

The decoder checks raw frame size, strict UTF-8, duplicate-aware bounded whole
JSON, the 4 KiB workspace command limit, closed native request shape, then nested
model JSON and JSON argument arrays. Original nested strings are not reserialized
before decoding. Success is exactly `{frameAccepted:true}`; the six stable
rejection codes are `native.frame.limit`, `native.frame.utf8`,
`native.frame.json`, `native.frame.shape`, `native.frame.model` and
`native.frame.arguments`. Source, paths and authority are absent from observations.

This tests frame acceptance through an implementation decoder. It does not
activate the public IPC endpoint, authenticate caller context, admit a Morphir
function or Ion values, create workspace grants or qualify a packaged platform.
The live native protocol remains draft.1.

## Native reply qualification

Exact offline draft.8 advertises only `validate-native-reply` and JSON. Select
`spec/workbench/mck/draft.8` in the existing parent-owned gate. The adapter calls
`finos/morphir-workbench-native-session/response.decode` on the original bytes,
with `expectedOperation` and required nullable `expectedSession` captures. These
are closed fixture context, not caller authentication. Encoding, source and the
optional bounded ASCII-space prefix recipe follow draft.7; compact input is
limited to 1 MiB and materialization to 2 MiB. Exact decimal recipe tokens are
preserved before fixture admission.

The production decoder checks strict UTF-8, whole duplicate-aware JSON, byte and
parser budgets, operation/session correlation, closed payloads, job receipt
consistency, unique project IDs and canonical base64 chunks. An admitted success
projects to `{replyAccepted:true,ok:true,operation}`. An admitted native failure
projects to `{replyAccepted:true,ok:false,error:{code,effect}}`, preserving
`none` versus `unknown`. Private messages, paths, session credentials and payload
bytes never appear in observations. Decoder rejection uses exactly
`native.reply.limit`, `.utf8`, `.json`, `.shape`, `.operation` or `.authority`.
Malformed fixture infrastructure terminates the adapter instead of fabricating a
domain rejection. The shared runner owns expectations, verdicts and saved-report
rechecking; it does not parse native replies.

This qualifies offline response admission only. The live native profile remains
`0.1.0-draft.1`; executable client/owner lifecycle MCK and actual platform
acceptance remain separate work. Historical MCK drafts.1–.7 remain supported.

## Native client lifecycle qualification

Exact offline draft.9 runs the shipped TypeScript client with controlled native
reply delivery. It uses a separate explicit adapter because the production client
runs in JavaScript in both browser and Proton CEF. The existing Rust MCK still owns
all expectations, comparisons and independent report checks.

```sh
MORPHIR_MCK_BIN=/path/to/morphir \
MORPHIR_WORKBENCH_KIT=/path/to/finos/morphir/spec/workbench/mck/draft.9 \
mise run test:workbench-native-client-mck
```

The task builds checked Node/browser adapters and debug/release production
MoonBit job cores, runs all 48 scenarios in Node and Chromium, and checks each
saved report. Portable cursor tests also run JS, native, Wasm and WasmGC. Four
complete JSON/Ion assets separately import and evaluate to Int 42 through the
production worker. `MORPHIR_WORKBENCH_EVIDENCE` selects an existing or new evidence
directory; the default is `.dev/native-client-mck/reports`.

The driver advances held replies and polling only through fixture actions.
Successful authority checks are transparent and use the current raw check reply;
substantive calls consume per-operation outcomes. The corpus can change authority
between actions. Closed snapshots preserve uncertainty, cancellation, retained
identity, terminal outcomes, exact workspace bytes, inspector order and disposal.
Client refusals are observations. Malformed infrastructure terminates the adapter.
No expected results or case IDs enter it.

This qualifies client behavior with controlled replies. It does not qualify native
owner lifecycle, real picker grants, authenticated caller authority, process exit
or packaged platforms. Live native draft.1 and historical MCK drafts.1 through .8
remain unchanged. See the upstream `spec/workbench/draft.9/README.md` contract.
