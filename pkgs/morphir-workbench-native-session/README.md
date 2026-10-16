# Workbench native session state

Pure state for the private Proton desktop bootstrap. It admits the trusted main
window/app-origin/page context supplied by the native host, negotiates the exact
bridge version, and binds opaque identities to that page. Navigation revokes a
binding; shutdown prevents reopening it. The default descriptor has no operations.
A host can explicitly enable jobs discovery after qualifying its worker service.
Every business command still needs native caller/session admission. Filesystem
operations and activation of the public Morphir native mapping remain separate.

This module has no Proton or platform dependencies. The portable workspace
tests it on JavaScript, native, Wasm and Wasm GC. The isolated desktop workspace
imports the same implementation for its typed Proton command handlers.

Run `mise run test:workbench-native-session` from the repository root for the
focused native tests. Actual renderer provenance, command grants and lifecycle
integration are covered by packaged Proton acceptance, not this pure model.

## Native request framing

The portable `request` package decodes the public native `0.1.0-draft.1`
request bytes before any future dispatch. It checks whole-frame and workspace
command byte limits, strict UTF-8, bounded duplicate-aware whole JSON, the closed
request shape, and whole nested model/JSON argument documents. It preserves
source strings and original number tokens. Workspace sequence/offset checks use
exact decimal integrality, preventing rounded fractions and underflow from
passing integer bounds. Request copies cannot mutate the admitted value.

Exact offline Workbench MCK draft.7 exercises this decoder through the existing
explicit adapter. Frame acceptance grants no authority, admits no function and
executes nothing. Ion input remains opaque at this boundary. Trusted caller and
session binding, actual OS grants, response validation and packaged lifecycle
qualification remain separate. The existing private Proton handlers are not
changed to advertise the public native profile.
