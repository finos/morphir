# Changelog

This file records the changes that users of the Morphir CLI and its npm package must know about: breaking
changes first, with the reason and the migration. The commit history has the full list of changes.

## Unreleased

### BREAKING: the extension helper routes are removed

The CLI runs extensions on its own worker host since the `host-extensions-as-workers` change. The old helper
routes needed a pinned Node runtime and helper modules, or a Rust adapter built from a finos/morphir checkout.
They are now removed, so the CLI has one extension host to maintain and to qualify.

- The npm package no longer contains `build-provider/extension.mjs` (the `core-wasm-process` helper) or
  `build-provider/extism.mjs` (the `extism-wasm` helper), and its launcher no longer sets
  `MORPHIR_EXTENSION_HELPER`.
- The Rust adapter `apps/morphir/native-services` no longer has the `describe`, `compile` and `generate`
  operations or the `extism.*` operations. It keeps the local repository and installation operations.

**Migration:** run `morphir extension describe`, `compile` or `generate` with a contract `0.2.0` pin. The
section "Migrate a pin" of [the extension documentation](apps/morphir/docs/extension.md#migrate-a-pin) shows
each old pin and its replacement, and the section "BREAKING: the helper routes are removed" lists each removed
part and what to use. `--services-pin`, `--services-helper` and `build-provider/native-services.mjs` stay for
the local repository commands.
