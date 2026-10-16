# Workbench native session state

Pure state for the private Proton desktop bootstrap. It admits the trusted main
window/app-origin/page context supplied by the native host, negotiates the exact
bridge version, and binds opaque identities to that page. Navigation revokes a
binding; shutdown prevents reopening it. The bootstrap offers no native jobs,
filesystem operations or public Morphir execution profile.

This module has no Proton or platform dependencies. The portable workspace
tests it on JavaScript, native, Wasm and Wasm GC. The isolated desktop workspace
imports the same implementation for its typed Proton command handlers.

Run `mise run test:workbench-native-session` from the repository root for the
focused native tests. Actual renderer provenance, command grants and lifecycle
integration are covered by packaged Proton acceptance, not this pure model.
