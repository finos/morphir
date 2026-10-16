# Workbench native session state

Pure state for the private Proton desktop bootstrap. It admits the trusted main
window/app-origin/page context supplied by the native host, negotiates the exact
bridge version, and binds opaque identities to that page. Navigation revokes a
binding; shutdown prevents reopening it. The default descriptor has no operations.
A host can explicitly enable jobs discovery after qualifying its worker service.
Every business command still needs native caller/session admission. Filesystem
operations and the public Morphir native mapping remain outside this module.

This module has no Proton or platform dependencies. The portable workspace
tests it on JavaScript, native, Wasm and Wasm GC. The isolated desktop workspace
imports the same implementation for its typed Proton command handlers.

Run `mise run test:workbench-native-session` from the repository root for the
focused native tests. Actual renderer provenance, command grants and lifecycle
integration are covered by packaged Proton acceptance, not this pure model.
