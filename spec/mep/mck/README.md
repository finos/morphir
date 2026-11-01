# MEP compatibility cases

## Executable guest qualification

`morphir mck mep guest-run` runs a real Content-Length framed JSON-RPC guest
through the shared Rust MCK engine. The executable and repeated arguments are
explicit. A Wasm guest can run through its installed Node embedding host; a
native stdio guest uses its executable directly. No shell interprets arguments.

```bash
morphir mck mep guest-run \
  --kit spec/mep/mck/guest-moonbit-bool.json \
  --expect-kit-sha256 <fixed-sha256> \
  --host /absolute/path/to/node \
  --host-arg /absolute/path/to/node-mep-cli.mjs \
  --host-arg /absolute/path/to/extension \
  --identity-file /absolute/path/to/node-mep-cli.mjs \
  --identity-file /absolute/path/to/extension/manifest.ion \
  --identity-file /absolute/path/to/extension/model.wasm \
  --report .dev/mep-guest.json
morphir mck mep report-check \
  --kit spec/mep/mck/guest-moonbit-bool.json .dev/mep-guest.json
```

Pin every runtime host module and guest artifact with repeated `--identity-file`
arguments, including imported modules. The runner records the executable's
resolved path and SHA-256, its ordered argument list, all identity files, its own
binary and build identity, and the exact corpus SHA-256. Report rechecking
requires the same checker binary and unchanged files. The kit is an explicit
local input, independent of the IR kit embedded in the CLI.

The kit profile is `moonbit-model-stable-v1`. The compile request selects the
same frontend profile in `source.options.profile`, and the guest must record it
in its `morphir_moonbit_frontend` provenance. The kit refuses any other value.
The MoonBit guest retired the earlier `moonbit-model-bool-library-v1` profile
in finos/morphir-moonbit#181; this kit does not accept it.

Its fixed source contains
an identity function with mixed-case and underscore names, and a Boolean
constant. The stable frontend always declares the `morphir/moonbit-source`
package specification as a Library dependency, so the expected IR contains it.
The expected IR was recorded from the native and portable MoonBit guests of
finos/morphir-moonbit `main` and checked against the IR v4 type spelling. The
expected generated artifacts did not change. The shared corpus fixes their complete canonical IR semantics and
generated function bodies, signatures, names, manifests, and artifact inventory.
Function declaration order is unrestricted. Rich model payloads must have valid
canonical base64, exact length and SHA-256, the model annotation, complete IR,
bounded structure, original source names and locations, and exact compilation
context provenance. The symbols sidecar must preserve original metadata as Ion,
including decimal scale and ordered annotations, and bind source and generated
node identities. Original model bytes and envelope must survive generation.

Every case is required. The suite exercises description and negotiation,
compilation and generation, repeat calls, unknown rich Ion facts, malformed
payloads and requests with recovery, lossy JSON export refusal, independent plain
JSON model generation, legacy JSON generation, notifications, shutdown and exit.
Separate fresh processes exercise legacy-only, compile-only, and tightly bounded
negotiation. A request cannot widen negotiated bounds. The process transport
reuses MCK deadlines, stderr draining, frame limits and process-tree cleanup.

Reports retain every request and complete response, including the first failed
comparison. `report-check` reconstructs the required case order and requests,
validates every response envelope, rechecks models and artifacts against the
independent corpus, and verifies identities. A stored `qualified:true` flag does
not establish qualification. Exit 0 means every required observation qualified;
failures and operational errors return 1, and missing CLI arguments return 2.

This is bounded guest qualification. It does not qualify independent host
admission, all languages/backends, every Boolean frontend construct, cancellation,
progress, or trusted remote evidence. The broader host qualification remains
[#965](https://github.com/finos/morphir/issues/965).

## Python JSON Library profile

[`guest-python-json.json`](guest-python-json.json) selects the separate
`python-json-library-v1` executable profile. Use the same `guest-run` and
`report-check` commands above with this kit path. Run each standalone stdio and
Extism WASM artifact separately and retain both reports. A report qualifies the
exact host, arguments and identity files it records; a native run does not
qualify a WASM artifact.

The fixed `main.py` source defines `identity(flag: bool) -> bool` and
`always() -> bool`. Its package is `mck/python`, with public module `main` and
`typesOnly: false`. The kit independently fixes complete Library JSON IR for
`3.0.0` and `4.0.0`, and the exact generated `main.py` artifact. The v3 expectation
uses classic access/documentation wrappers, SDK Bool references and typed value
attributes. The v4 expectation uses canonical Library, ExpressionBody, Variable
and BoolLiteral forms. No implementation IR codec supplies expected results.
The profile accepts a canonical SemVer extension version, so qualification is
not tied to one Python package release.

The required cases cover:

- Static claims, exact `0.2.0-draft.1` and legacy `0.1` negotiation, refusal of a
  different draft, pre-initialization work, duplicate initialization, silent
  notifications, unknown methods, shutdown and clean exit.
- Exact JSON-RPC identity echo for unsigned `u64::MAX`, a Unicode string and an
  empty string. The existing MoonBit numeric request sequence stays unchanged.
- Legacy JSON compile/generate and JSON `compileModel`/`generateModel` for both
  IR versions. Generated source compiles back to the frozen semantic IR.
  Independently constructed envelopes exercise generation without depending on
  the compiler's output. Repeated model compilation must retain model identity
  and bytes.
- Complete operation/profile/codec/envelope/IR tuples. Fresh processes exercise
  compile-only admission, an unoffered IR version, each encoded-byte,
  decoded-byte, depth and node bound separately, and offers above the guest's
  limits. Selection must use each bilateral minimum. Request-local support
  cannot widen a selected bound, and a refused request permits later work.
- Invalid SHA-256, decoded length, base64, JSON, envelope version, IR version,
  operation/codec tuple and unknown critical members. Ion model input, Ion
  evidence and unavailable required guarantees must be refused. Valid Specs and
  Application distributions return structured failure diagnostics and no
  artifacts. Malformed Python and `typesOnly` functions return diagnostics and
  no model.

This profile qualifies the Python JSON Library subset. It makes no rich Ion,
source provenance or guarantee-preservation claim. The MoonBit profile above
continues to require every rich-model retention, metadata and artifact check.
Both profiles use the same `mep-guest` report suite, corpus digest, complete
observation replay, executable identity checks, frame/deadline bounds and
process cleanup. Synthetic replay tests verify adjudication only. Actual guest
qualification requires a successful executable report and independent
`report-check` using the unchanged checker binary and files.

## Generic JSON Library profile

[`guest-generic-json.json`](guest-generic-json.json) selects the
`generic-json-library-v1` profile. It accepts any extension identity, so a
guest shows conformance without claiming another extension's id. Use the same
`guest-run` and `report-check` commands. The requirements are in
`openspec/specs/mep/generic-guest-profile/spec.md`. The design is in the archived
change `openspec/changes/archive/2026-11-01-add-generic-mep-guest-profile`.

The kit fixes one package, `mck/generic` with module `main`, and two public
Bool constants, `ready = true` and `blocked = false`. It has one expected IR for
`3.0.0` and one for `4.0.0`. Each kit language gives its own documents for that
package and a malformed source. The first languages are
`morphir-fixture-flags`, `python` and `gleam`. A new language is a reviewed kit
change, and its source must compile to the same expected IR on a real guest.
Document URIs are relative to the source folder, for example `main.py` or
`acme/rules.py`. The kit refuses an absolute URI, a scheme, a `src/` prefix,
a backslash, and an empty, `.` or `..` segment.

The first case is `describe`. Its claims format must be `claimsVersion`
`0.1.0-draft.2` or the draft.1 `statementVersion` `0.1.0-draft.1`, with no
`critical` path other than that field. The runner selects the plan from the
claim:

- The language: the first kit language, in lexical order of its id, that the
  guest claims both as a frontend language and as a backend target.
- The IR versions: each of `3.0.0` and `4.0.0` that both the frontend and the
  backend claim. `3` and `3.0.0` are the same claim.
- The model tier: when the guest claims `0.2.0-draft.1`, each selected IR
  version for which it claims JSON `compileModel` and `generateModel` tuples.

When the claim selects no language or no IR version, the run fails. Every
selected case is required. `report-check` rebuilds the plan from the recorded
`describe` observation.

The legacy tier runs in one process with MEP `0.1`. For each IR version it
compiles the fixed source (`morphir.frontend.compile`), generates from the
result (`morphir.backend.generate`) and generates from the kit's expected IR.
After each generate case it compiles the generated files again. It also checks a malformed source, an
unknown method (`-32601`), `describe` stability, a request after shutdown
(`-32014`), silent notifications and a clean exit. The model tier runs in a
second process with `0.2.0-draft.1` and the selected JSON tuples. It compiles a
model, generates from it and from an independent model, compiles the files of
each of those generate cases again with `compileModel`, and refuses a bad
payload digest (`-32602`). The selected tuples must keep the host order within
each operation, and each compiled model must stay inside the negotiated byte,
depth and node limits. Request ids are numbers counted from 1 in each
process.

Outputs are compared by meaning. A compiled IR must equal the expected IR after
three rules only: JSON object member order is ignored; in IR 3 the order of the
`modules`, `types` and `values` lists is ignored; in IR 4, at an `outputType`
or a member of `inputTypes`, a `Reference` with an `fqname` and no or empty
`args` equals the FQName string. Warning and info
diagnostics are allowed on success; an `error` diagnostic is not. Generated
files must be text with unique relative paths. The files with a claimed file
extension of the language must compile again to the expected IR. The kit does
not fix generated bytes.

The expected IR was recorded from the published Python 0.4.2 guest. The SDK
fixture of finos/morphir-moonbit (`apps/morphir/fixtures/sdk-guest`) and the
published Gleam 0.4.0 guest compile the same source sets to the same IR under
these rules. WASM guests have no public stdio host yet
(finos/morphir-moonbit#297); run them through the native MoonBit CLI's internal
worker mode and pin the CLI and the module:

```bash
morphir mck mep guest-run \
  --kit spec/mep/mck/guest-generic-json.json \
  --expect-kit-sha256 <fixed-sha256> \
  --host /absolute/path/to/morphir \
  --host-arg extension --host-arg worker \
  --host-arg --abi --host-arg extism-kernel-v1 \
  --host-arg --module --host-arg /absolute/path/to/guest.wasm \
  --host-arg --build-identity --host-arg <morphir extension worker --help --json: result.buildIdentity> \
  --identity-file /absolute/path/to/morphir \
  --identity-file /absolute/path/to/guest.wasm \
  --report .dev/mep-generic.json
```

Use `--abi morphir-bytes-v1` for a core-Wasm guest such as Gleam.

This profile qualifies a small Bool library through JSON. It makes no claim
about Ion, rich models, guarantees, types, records or functions with
arguments; the MoonBit and Python profiles keep those checks.

## Model transport reference corpus

[`model-transport.cases.json`](model-transport.cases.json) records fixed examples
for the additive `compileModel` and `generateModel` contract. Its corpus contract
is `0.1.0-draft.1`, its MEP target is exactly `0.2.0-draft.1`, and the independent
model envelope is exactly `0.1.0-draft.1`. The unchanged JSON operations remain
available through legacy MEP `0.1`.

**The model-transport corpus contains reference cases.** The
existing contract test checks corpus identity, case inventory, and asset byte
lengths, digests, and literal base64 content. Positive JSON payloads also pass
the existing IR codec structural checks and the shared reference IR support
table. These checks do not implement MEP negotiation, host admission, a guest,
or an independent compatibility runner. Passing
those integrity checks does not establish support for the methods, the model
profile, IR `4.0.0`, or any guarantee. The bounded guest suite above is separate
from these reference cases. Broader host qualification remains
[#965](https://github.com/finos/morphir/issues/965).

The additive methods refine [#967](https://github.com/finos/morphir/issues/967):
IR has an explicit representation, Ion can pass without conversion, and JSON
remains supported. They preserve the legacy request/result fields instead of
replacing them. The complete operation/profile/codec/envelope/IR tuple replaces
independent lists that could imply unsupported combinations. No claim is made
that the current SDK or host implements the new draft.

IR 4 remains a draft for this work. The fixture assets use the accepted input
spelling `formatVersion: "4.0.0"`; the current canonical JSON writer emits the
integer `4`. The transport tuple's semantic `irVersion` is `"4.0.0"`. This PR
does not introduce IR `4.1.0`, add a prerelease suffix to `formatVersion`, change
the IR support table, or stabilize IR 4. Negative cases 0005 and 0031 use
`3.0.0` only to preserve their explicit mismatch with the admitted `4.0.0`.

## Reading a case

The examples isolate model transport. Unless a case changes that boundary,
assume the normal frontend language/source-count or backend target capability
has already been admitted. `hostOffer` and `guestSupport` are fixture projections
of the handshake's relevant transport members, not complete handshake messages.

Each stable case ID has a category, description, host offer, guest support, a
literal JSON-RPC request, and a fixed expected observation. `result`, when
present, is the operation result inside a JSON-RPC response. `projectionSource`
in case 0025 supplies the source model for the explicit export attempt; it is
fixture context, not an additional request member. `retainedAsset` identifies
bytes that an opaque retention path must preserve.

`expected.admission` applies to the boundary being illustrated: operation
dispatch, response acceptance, model decoding, guarantee admission, or explicit
projection. It is not an assertion that every rejection occurs before dispatch.
`expected.code` is a corpus observation label, not a newly assigned JSON-RPC
error number. An implementation maps observations to the protocol's existing
errors and diagnostics. Intentional malformed requests do not alter the valid
asset manifest.

| Cases | Boundary |
| --- | --- |
| 0001–0010 | Exact bilateral tuples, missing offers, operation identity, and draft matching |
| 0011–0014 | Both peers' encoded/decoded byte, depth, and node bounds |
| 0015–0017 | Decoded length, SHA-256, and base64 integrity |
| 0018–0020 | Successful compilation requires a model; failure forbids it, including null |
| 0021–0023 | Revision/context evidence and unknown required guarantees |
| 0024 | Opaque preservation of unknown enrichment and ordered annotations |
| 0025–0027 | Explicit lossy export refusal, legacy JSON, and negotiated lossless JSON |
| 0028–0029 | Valid successful and failed compilation results |
| 0030–0032 | Support is not proof; compile IR consistency; evidence model identity |
| 0033–0035 | Unknown critical child, exact evidence scope, and aggregate payload budget |

The `guarantees` lists describe identifiers a peer interprets. They do not
establish those guarantees. Every identifier under `urn:morphir:mep:fixture:` is
test vocabulary. The evidence bytes are deliberately ordinary fixture data,
not a proof format or a trusted authority. Even matching evidence still needs
the host's checking and trust policy in an implementation.

## Literal assets

All asset paths are relative to this directory. Each manifest entry binds the
file's exact bytes through `decodedByteLength`, lowercase SHA-256, and base64
`content`. Payload limits apply to the aggregate selected model, dependency and evidence
content in a request or response, not to the size of this reference corpus. `maxEncodedBytes` bounds the base64 content's ASCII bytes;
`maxDecodedBytes` bounds the bytes after base64 decoding. Parse bounds apply to
the decoded value. The binary fixture requires more than one node and depth
greater than one, so cases 0013 and 0014 do not depend on a precise full-tree
node count.

- [`fixtures/rich-model.ion`](fixtures/rich-model.ion) is the readable companion
  to [`fixtures/rich-model.ionb`](fixtures/rich-model.ionb). The latter contains
  genuine Ion binary, including its version marker and local symbol table.
- [`fixtures/plain-ir.json`](fixtures/plain-ir.json) is a small complete
  `4.0.0` Library distribution without enrichments. It illustrates a lossless
  `morphir-ir`/`morphir-json` payload.
- [`fixtures/legacy-ir.json`](fixtures/legacy-ir.json) is the equivalent `4.0.0`
  input for the unchanged legacy JSON generation operation.
- [`fixtures/guarantee-evidence.json`](fixtures/guarantee-evidence.json) is opaque
  test evidence used only to illustrate binding checks.

The rich model body is one `morphir_model`-annotated struct containing a complete
IR distribution, `enrichments`, and `provenance`. The IR member retains the
existing IR object structure. This is the model-profile body, not a redefinition
of the separate Ion IR spelling or a claim that an existing IR codec reads this
wrapper. The IR's `Library` variant remains owned by the IR distribution type.

The enrichment contains ordered `source_name::target_name` annotations, original
and target names, the exact integer `9007199254740993`, decimal `123.4500`, a
symbol, and an unknown annotated fact. Preservation keeps those values and the
provenance record. Ordinary Morphir JSON cannot silently replace this rich
payload; case 0025 expects the existing `data.lossy_conversion` diagnostic.

The binary fixture was written from the companion text and replayed through
`moonrockz/ion` **0.3.0**, using the repository's pinned MoonBit toolchain. Binary
replay was equal to the source Ion value, including annotations and decimal
scale. That is asset-generation evidence, not MEP runtime conformance. The
binary payload is **499 bytes**, with SHA-256
`49f87687c033a8ec39a7f42b93bb1c54b4856ceab0b05246d81ea0a8b27e10b1`.

Changes to a fixture's intended meaning require a reviewed corpus change. Do
not regenerate expected admission outcomes from the implementation under test.
