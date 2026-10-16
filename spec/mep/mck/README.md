# MEP model transport reference cases

[`model-transport.cases.json`](model-transport.cases.json) records fixed examples
for the additive `compileModel` and `generateModel` contract. Its corpus contract
is `0.1.0-draft.1`, its MEP target is exactly `0.2.0-draft.1`, and the independent
model envelope is exactly `0.1.0-draft.1`. The unchanged JSON operations remain
available through legacy MEP `0.1`.

**These are reference cases, not executable host or guest qualification.** The
existing contract test checks corpus identity, case inventory, and asset byte
lengths, digests, and literal base64 content. It does not implement negotiation,
host admission, a codec, a guest, or an independent compatibility runner. Passing
those integrity checks does not establish support for the methods, the model
profile, IR `4.1.0`, or any guarantee. Executable host/guest cases and delivery
through the existing native MCK runner remain [#965](https://github.com/finos/morphir/issues/965).

The additive methods refine [#967](https://github.com/finos/morphir/issues/967):
IR has an explicit representation, Ion can pass without conversion, and JSON
remains supported. They preserve the legacy request/result fields instead of
replacing them. The complete operation/profile/codec/envelope/IR tuple replaces
independent lists that could imply unsupported combinations. No claim is made
that the current SDK or host implements the new draft.

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
  `4.1.0` Library distribution without enrichments. It illustrates a lossless
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
`bf9757365d1d30c44385aa72e950e90f66eb53d66d2b3c9b42b67204fbef0c8a`.

Changes to a fixture's intended meaning require a reviewed corpus change. Do
not regenerate expected admission outcomes from the implementation under test.
