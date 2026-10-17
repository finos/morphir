# Native qualification expectations

These parent-owned files record expected behavior for the exact
`morphir/workbench/native` `0.1.0-draft.1` contract. These original fixture files
are **unexecuted data**. Executable request expectations are published separately
in exact [MCK draft.7](../../../mck/draft.7/README.md). Structural response
fixtures and additional runtime expectations are exercised by exact
[MCK draft.8](../../../mck/draft.8/README.md), using the shared Rust runner and
explicit implementation adapters. The abstract lifecycle traces remain pending.
These files' presence,
valid JSON syntax, and the separate schema fixtures establish no implementation,
transport, operating-system, or packaged-platform qualification. No additional
runner is defined here.

## Raw rejection cases

`raw.json` contains independent rejection expectations. Each case has an `id`,
`encoding`, `source`, `expected`, and concrete `reason`.

- For `utf8`, encode `source` as UTF-8 without changing escapes or whitespace.
  The string is the complete request frame, not an object to parse and reserialize.
- For `hex`, decode each pair of hexadecimal digits to one byte. Do not pass the
  bytes through a replacement-character decoder before the admission boundary.
- A `generate.prefix` instruction means prepend `repeat`, repeated exactly
  `count` times, to `source` before UTF-8 encoding. It keeps the byte-budget case
  small in version control. Those prefix bytes count toward the frame limit.

Every case expects rejection before an execution claim or filesystem grant is
created. Duplicate names compare their decoded JSON spelling. Model and JSON
argument source strings need their own duplicate-aware, whole-document decoding;
rejecting duplicates in the outer request alone is insufficient. Opaque model
examples illustrate decoding obligations and do not claim a runnable function.

## Abstract lifecycle traces

`lifecycle.json` contains fixed abstract traces. The step vocabulary describes
test-driver actions and required effects, not new wire operations:

- `trusted_context` supplies native-owned window, origin and page identity out of
  band. Renderer-supplied fields cannot produce or override this context.
- `call` names a public operation. `session` resolves a captured session ID;
  `payload` supplies its operation arguments. The common profile and version are
  those at the document root. `identity` resolves the full captured immutable job
  identity. `fixture: "Q"` means an admitted immutable model, public entry and
  argument submission supplied by a future host qualification fixture.
- `capture` names a symbolic session, picker, grant, job, or call correlation for
  later steps. These labels are not literal wire identifiers. `P1` denotes an
  available project returned in the current grant's inventory.
- `host_event` describes a controlled native event, delivery schedule, transport
  fault, or hostile incoming response. `hostPath` is supplied by the simulated
  trusted picker, never a renderer command. `read_all_chunks` abbreviates reads
  at consecutive admitted offsets until the declared byte count is exhausted.
- `expect` contains fixed assertions. Assertions about a response describe its
  admitted contents or error code/effect. They do not imply that lost responses
  become visible to the client. A `held-before-admission` call has no effect until
  its later `deliver_held_call` event.

Q, P1, hashes and actual OS contexts must become explicit independent assets
before executable qualification is claimed. The traces deliberately cover
response-operation correlation and cross-field identity equality that JSON Schema
cannot establish. Frozen jobs draft.1 and terminal draft.5 rules still govern job
receipts; these traces do not replace their existing shared MCK cases.

Future execution belongs in the existing shared Rust MCK engine through an
explicit adapter. Native caller provenance, real OS picker behavior, filesystem
containment, process exit and application shutdown also need packaged acceptance
evidence for each advertised operating system and architecture. Synthetic
contexts or a passing abstract trace cannot supply that evidence.
