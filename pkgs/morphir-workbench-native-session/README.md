# Workbench native session state

Pure state for the Proton desktop owner. Its internal bootstrap admits the trusted main
window/app-origin/page context supplied by the native host, negotiates the exact
bridge version, and binds opaque identities to that page. Navigation revokes a
binding; shutdown prevents reopening it. The default descriptor has no operations.
A host can explicitly enable jobs discovery after qualifying its worker service.
Every business command still needs native caller/session admission. Filesystem
operations belong to the composing native owner. That owner builds the public
descriptor from actual services after admission and awaited cleanup.

This module has no Proton or platform dependencies. The portable workspace
tests it on JavaScript, native, Wasm and Wasm GC. The isolated desktop workspace
imports the same implementation for its typed Proton command handlers.

Run `mise run test:workbench-native-session` from the repository root for the
focused native tests. Actual renderer provenance, command grants and lifecycle
integration are covered by packaged Proton acceptance, not this pure model.

## Native request framing

The portable `request` package decodes the public native `0.1.0-draft.1`
request bytes before production owner dispatch. It checks whole-frame and workspace
command byte limits, strict UTF-8, bounded duplicate-aware whole JSON, the closed
request shape, and whole nested model/JSON argument documents. It preserves
source strings and original number tokens. Workspace sequence/offset checks use
exact decimal integrality, preventing rounded fractions and underflow from
passing integer bounds. Request copies cannot mutate the admitted value.

Exact offline Workbench MCK draft.7 exercises this decoder through the existing
explicit adapter. Frame acceptance grants no authority, admits no function and
executes nothing. Ion input remains opaque at this boundary. Trusted caller and
session binding, actual OS grants and packaged lifecycle qualification remain
separate. The bundled Proton host and renderer use this decoder through the
native owner. Public conformance advertisement still waits for independent
reply/client/owner lifecycle MCK and packaged-target qualification.

## Native reply boundary

The portable `response` package admits the public native draft.1 reply from
complete UTF-8 bytes. It rejects malformed encoding, BOMs, duplicate members,
excessive parsing budgets, unknown fields and mismatched originating operations.
Whole replies fit 1 MiB and grant offers fit 512 KiB, including their wrappers.
It validates all 13 operation payloads, shares descriptor admission with the job
client, binds optional expected sessions and checks initial submission identity
and receipt agreement. The receipt cursor still owns retained-job transitions.

Grant admission requires unique project IDs. Labels and error messages use the
published Unicode character limits; nested jobs retain their UTF-16 limits.
Workspace chunks use exact integers and canonical padded base64, with at most
196,608 decoded bytes. Capture totals, offsets and retirement still require the
stateful workspace client and owner. A reply copy cannot mutate admitted data.

`success` validates and reserves the complete reply envelope before publication.
`failure` takes closed `Code` and `Effect` types and emits fixed public messages,
omitting internal errors, paths and source. The owner chooses `NoEffect` or
`UnknownEffect` at its actual effect boundary. An encoding failure after an owner
action does not establish that no action occurred.

The binding must correlate each completion with its exact invocation, including
concurrent calls with equal operations. It must also recheck the current native
page around asynchronous authority boundaries. This codec cannot establish
framework provenance, immutable captures or confirmed worker exit. Portable and
compiled-client tests are implementation checks; independent reply/lifecycle MCK
and fresh packaged-target qualification remain pending. The bundled host and
renderer use these codecs together; public conformance advertisement remains
gated on that independent evidence.
