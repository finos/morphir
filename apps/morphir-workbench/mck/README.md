# Workbench MCK adapter

This component exposes the shipped `finos/morphir-execution` value codec and
validator to the shared Rust MCK. It supports exact contracts
`0.1.0-draft.1` through `0.1.0-draft.5`, plus replacement drafts14–16 and
the exact boundary/codec drafts20, 23 and 26. It has no goldens, evaluator or separate
conformance runner. The parent `finos/morphir` repository owns the specification,
corpora and verdict calculation. Draft.1/.2 are merged; draft.3 adds invocation
validation; draft.4 adds output validation; draft.5 adds terminal outcome validation.

Capability verification uses scoped contract and MCK evidence for provider
claims. Passing these fixed cases is not formal proof of correctness for every
program or business result. Capability validation checks the chosen runtime or
provider against a particular run, selected function and model revision under policy. The value,
type, invocation, output, receipt and authority checks below remain ordinary
validation. Historical code and wire identifiers retain their names.

`protocol.mbt` handles capabilities and `decode-value`, echoes correlation IDs
and rejects unknown/duplicate JSON members. Draft.1 capabilities and its original
64-case corpus remain unchanged. JSON calls `Value::from_json`; Ion text calls
the Ion parser and `Value::from_ion`. Both return `Value::to_json`, preserving
exact numbers, Float64 bits and UTF-16 units. Successful decode of a model error
is an outcome projection, without argument validation.

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
forbidden as an argument; ordinary `Result.Err` values remain valid.
Successful validation returns the canonical value projection, without evaluation.

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

Every entry input/output and unused registry declaration is validated before
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

<a id="declared-output-admission"></a>

## Declared output validation

Exact draft.4 adds `validate-output` with the same closed `value`, `type` and
`definitions` input as `validate-value`. Complete declaration validation precedes
decoding, then the shipped `validate_as(output=true)` checks returned values.
Only the five recognized top-level SDK model errors bypass ordinary type matching.
Typed `Result.Err` must match its declared error type; nested model errors and
provider/cancellation/cleanup codes reject. Argument validation remains unchanged.
The new operation is unavailable under earlier drafts. The parent owns independent
goldens, corpus inventory and report rechecking; no connected RPC is advertised.
Select `spec/workbench/mck/draft.4` with the existing gate to qualify this draft.
Live execution lifecycle and authoritative cleanup behavior remain separate.

<a id="terminal-outcome-admission"></a>

## Terminal outcome validation

Exact draft.5 adds `validate-outcomes` with closed `{suite,manifest,outcomes}`
input. Suite and manifest stay JSON in both formats; outcomes is a tagged JSON
envelope or Ion-text string. Strict declaration and argument validation precede
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
Validation of failed/cancelled evidence means valid evidence, not successful or
authenticated execution. UI adoption, live daemon executions, acknowledged cancellation
and connected protocol extensions remain subsequent work.

## Execution transition qualification

Exact offline MCK draft.14 advertises only `reduce-execution` and JSON. It maps the
replacement `morphir/workbench/executions` `0.2.0-draft.1` profile and its nested draft.5
terminal outcomes. It does not add operations to the five historical drafts or
define an Ion receipt mapping. Requalify historical kits separately.

Input is exactly `{offer,identity,calls,initial,actions}`. The adapter validates the
offer, caller-owned expected identity, ordered call IDs and initial submitted
receipt through `finos/morphir-execution/executions`. It validates closed action syntax
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
observation validation, comparisons and report rechecking. No expected data or
case ID is sent to this adapter.

Select `spec/workbench/mck/draft.14` with the existing gate. Set
`MORPHIR_WORKBENCH_EVIDENCE` to retain reports in a separate directory per kit;
the default remains `.dev/workbench-mck/`. This qualifies recorded transitions,
replay/conflict handling, cancellation races and same-session reconciliation.
It does not authenticate receipts or qualify live execution RPC, host execution,
durable recovery, Proton IPC or generated browser execution.

## Native request-frame qualification

Exact offline draft.15 advertises only `validate-native-frame` and JSON. It
uses `finos/morphir-workbench-native-session/request`, the portable native
`0.2.0-draft.1` request decoder. Select `spec/workbench/mck/draft.15` with the same
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
activate the public IPC endpoint, authenticate caller context, validate a Morphir
function or Ion values, create workspace grants or qualify a packaged platform.
The live native protocol uses `0.2.0-draft.1`.

## Native reply qualification

Exact offline draft.16 advertises only `validate-native-reply` and JSON. Select
`spec/workbench/mck/draft.16` in the existing parent-owned gate. The adapter calls
`finos/morphir-workbench-native-session/response.decode` on the original bytes,
with `expectedOperation` and required nullable `expectedSession` captures. These
are closed fixture context, not caller authentication. Encoding, source and the
optional bounded ASCII-space prefix recipe follow draft.15; compact input is
limited to 1 MiB and materialization to 2 MiB. Exact decimal recipe tokens are
preserved before fixture validation.

The production decoder checks strict UTF-8, whole duplicate-aware JSON, byte and
parser budgets, operation/session correlation, closed payloads, execution receipt
consistency, unique project IDs and canonical base64 chunks. A validated success
projects to `{replyAccepted:true,ok:true,operation}`. A validated native failure
projects to `{replyAccepted:true,ok:false,error:{code,effect}}`, preserving
`none` versus `unknown`. Private messages, paths, session credentials and payload
bytes never appear in observations. Decoder rejection uses exactly
`native.reply.limit`, `.utf8`, `.json`, `.shape`, `.operation` or `.authority`.
Malformed fixture infrastructure terminates the adapter instead of fabricating a
domain rejection. The shared runner owns expectations, verdicts and saved-report
rechecking; it does not parse native replies.

This qualifies offline response validation only. The live native profile remains
`0.2.0-draft.1`; executable client/owner lifecycle MCK and actual platform
acceptance remain separate work. Historical MCK drafts.1–.7 remain supported.

## Native client lifecycle qualification

Exact offline draft.17 runs the shipped TypeScript client with controlled native
reply delivery. It uses a separate explicit adapter because the production client
runs in JavaScript in both browser and Proton CEF. The existing Rust MCK still owns
all expectations, comparisons and independent report checks.

```sh
MORPHIR_MCK_BIN=/path/to/morphir \
MORPHIR_WORKBENCH_KIT=/path/to/finos/morphir/spec/workbench/mck/draft.17 \
mise run test:workbench-native-client-mck
```

The task builds checked Node/browser adapters and debug/release production
MoonBit execution cores, runs all 48 scenarios in Node and Chromium, and checks each
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
or packaged platforms. Live native `0.2.0-draft.1` uses execution names. Historical MCK drafts6–10/13 remain frozen and are rejected by current adapters. See the upstream `spec/workbench/mck/draft.17/README.md` contract.

The separate [native owner adapter](../../../pkgs/morphir-workbench-native/README.md#controlled-owner-qualification)
adds exact offline draft.18 for production owner orchestration with controlled
host dependencies. It runs natively and does not add owner operations to this
portable codec adapter. Both use the same shared Rust runner.

## Runtime capability checking

The separate [capability policy adapter](capabilities/README.md) implements exact
offline draft.12 with actual selected Scheme execution and explicitly labelled
captured-completion validation. Its independent 182-case kit qualifies the named
Node/Chromium/native debug/release lanes. Existing draft.1–.11 contracts stay
unchanged; this does not add a UI, execution or live provider offer.
## Immutable Scheme execution selection

The separate [`capability-executions`](capability-executions/README.md) adapter drives real
host-owned Session state under exact Workbench MCK `0.1.0-draft.19`. It qualifies
captured runtime/policy, immutable source and selected boundaries, once-only
claims, independent replans and typed completion. Execute actions and supplied
completion evidence are distinct. The parent Rust CLI owns fixed cases and every
verdict. Frozen adapters and receipts retain their formats.

Run `mise run test:workbench-capability-execution-mck` with explicit `MORPHIR_MCK_BIN`
and `MORPHIR_WORKBENCH_KIT`. Reports cover Node, Chromium and native, debug and
release. The private Node execution provider also has actual isolated-worker tests in
`scripts/capability-execution.test.ts`. These controlled traces and process tests add no
browser, connected HTTP or native capability offer; those integrations remain
separate tasks.

HTTP checking-policy boundary qualification selects exact `0.1.0-draft.23` and
`validate-http-policy-boundary`. Compact opaque byte fixtures retain their actual
UTF-8 or hex encoding, with captured session, offer and submission context. The
production core checks descriptors, selected requests and accepted plans; the
adapter only materializes fixture bytes and projects decisions. Node and native,
debug and release, use the same implementation. Draft24 client traces and draft25
actual authenticated gateway/provider traces have separate production adapters
and gates. Frozen native drafts20–22 remain unchanged.

HTTP client/provider kits retain their own 2-MiB complete NDJSON envelope budget
and 1-MiB compact input budget. Their separate `json-frame` codec uses the shared
duplicate-aware wire parser. Actual HTTP requests, replies and argument-source
validation continue through the production 1-MiB boundary.

## Artifact client traces

`browser/artifact-client-trace.ts` drives the actual `ArtifactTransferAttempt`,
`VerifiedArtifactSet`, `ArtifactDownloadRegistry`, file-byte and ZIP APIs through
held effect ports. It accepts the independently reviewed draft28 scenario
vocabulary in `artifact-client-trace-contract.ts`. The shared runner must first
validate that closed input and its expansion/work budgets. Initial current
context is empty. Actions explicitly select context, settle or reject effects,
cancel, publish or clear output, mutate returned copies and request downloads.
Every attempt and held effect must finish before final evidence is returned.

Evidence retains actual outbound frames losslessly and measures digest input,
original owner bytes, previews, download bytes and decompressed ZIP entries.
Opaque local view tokens are aliased only after checking actual bindings.
The driver receives no expected projection or case identity. Context changes
affect currentness; registry invalidation is a separate explicit action.
Constructor input failures carry actual typed reasons; display text remains
separate. Optional bounded local-value recipes let compact cases reach the
real complete generation-request boundary. Expansion is checked before string
allocation and precedes local faults and construction.

The CLI adapter reuses the compiled duplicate-aware MCK framing codec. Bun builds
checked Node and browser bundles; `test:workbench-artifact-client-mck` runs Bun,
Node and Chromium bindings through one explicit parent runner and independently
checks every saved report. Set `MORPHIR_MCK_BIN` and `MORPHIR_WORKBENCH_KIT` to the
parent executable and its draft28 client kit. `MORPHIR_WORKBENCH_EVIDENCE` selects
the ignored report directory. This opt-in command refuses a mixed/server kit.
Before invoking the parent runner, it tests the actual CLI's complete frame
boundary, duplicate and unexpected members, unsafe IDs, malformed Unicode and
UTF-8, batched correlation, incomplete EOF and process exit.

The shared client contract remains a review candidate. Full independent corpus
and saved-report qualification, hostile and lifecycle coverage, and final
published contract/source pins remain pending. A focused controlled workflow
or a successful typecheck does not establish shared MCK compatibility.

## Invocation transcoding and comparison

Exact offline draft.26 exercises the shipped invocation codecs and value
comparator. `transcode-invocations` decodes opaque JSON, Ion text or binary bytes,
encodes the captured suite into the selected destination, and decodes those
actual output bytes. Fixed independent upstream expectations check the normalized
suite, including exact Int/Decimal, Float64 bits, UTF-16 and extension bytes.
Binary Ion has multiple valid encodings; this gate makes no canonical-byte claim.

`compare-values` uses the existing exact or explicitly approximate comparison
policy and reports equality plus the first mismatch as a JSON Pointer. Comparison
qualification is distinct from claiming support for every SDK operation.

```sh
MORPHIR_MCK_BIN=/path/to/morphir \
MORPHIR_WORKBENCH_KIT=/path/to/finos/morphir/spec/workbench/mck/draft.26 \
MORPHIR_WORKBENCH_EVIDENCE=.dev/workbench-codec-comparison \
mise run test:workbench-mck
```

The existing gate runs all four portable test targets and actual Node/native
debug/release adapters, then independently checks each report. The exact new kit
allows 3 MiB compact fixture inputs and a separate 1-KiB framing reserve to test
the production 1-MiB source boundary with hexadecimal binary fixtures.
Its retained compact value projection remains bounded to 1 MiB; expansion beyond
that evidence budget reports `workbench.output_limit`. That evidence limit does
not change production codec acceptance. Frozen kits and live native/HTTP offers
retain their own contracts.
