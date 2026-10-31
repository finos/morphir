# Proposal

## Why

The Gleam extension moved to finos/morphir-gleam (finos/morphir-gleam#23) and
is released there as `extension/gleam/v0.4.0`, a core-Wasm guest for the
MoonBit CLI. The Rust CLI in `crates/morphir` is being sunset, but it still
links the old `morphir-gleam-binding` crate through the `ecosystem/morphir-rust`
submodule and registers it as the built-in provider `morphir-gleam`. Two copies
of one extension drift apart, and a separate change removes the crate from
finos/morphir-rust. Damian Reeves approved this removal on 2026-10-31.

## What Changes

- **BREAKING** Remove the built-in Gleam provider `morphir-gleam` and its
  legacy selector alias `morphir-gleam-binding` from the Rust CLI provider
  registry. The CLI then has no default built-in provider. The native Elm
  provider `morphir-elm-native` stays built in and opt-in.
- **BREAKING** Remove the `morphir gleam compile|generate|roundtrip`
  subcommand, its help, man page, completions and CLI reference pages.
- Remove `examples/gleam/*` and the Gleam tests. Port tests that cover
  behavior that is not Gleam-specific to the native Elm provider or to
  installed test providers.
- The package examples publish a native Elm model and stop after restore. The
  frozen generated Gleam goldens go.
- `mise run spec:mep` stops with a pointer to finos/morphir-gleam, because the
  CLI can no longer compile `spec/mep/contract/src/mep.gleam`. The
  `mep_contract` tests check the committed `spec/mep/generated/mep.ir.json`.
  Damian Reeves chose this on 2026-10-31; bead `morphir-sugs` tracks the
  return of regeneration and the drift check.
- Move the `ecosystem/morphir-gleam` submodule pin to finos/morphir-gleam
  `main`. This proposal explicitly covers that update. `ecosystem/morphir-rust`
  does not move.
- Docs point Gleam users to finos/morphir-gleam and the MoonBit CLI.
- Gleam stays the language of the MEP and IR spec models (`spec/mep`,
  `spec/ir`), and the website keeps its Gleam syntax highlighting.

## Capabilities

### New Capabilities

- `cli/builtin-providers`: which language providers the Rust CLI ships built
  in, how a command selects them, and which commands have a language-specific
  form.

### Modified Capabilities

None. `openspec/specs/` has no capabilities.

## Tracking

- Bead `morphir-ukvn.1.17` owns this change.
- Bead `morphir-ukvn.1.4` (A3, "built in by pin") is closed as superseded by
  finos/morphir-gleam#23.
- Bead `morphir-sugs` restores MEP contract generation and the drift check with
  the morphir-gleam extension.

## Impact

- `crates/morphir`: provider registry, `main.rs` subcommands, compile
  preparation (the roundtrip-only project check), the playground and provider
  pool tests, and the integration tests.
- `Cargo.toml`/`Cargo.lock`: the `morphir-gleam-binding` path dependency and
  the `gleam-core` dependency tree leave the build.
- `docs/cli`, `docs/man`, `completions`, user guides and examples.
- `.config/mise/config.toml` (`spec:mep`), `spec/mep/README.md`,
  `tools/spec-mep.ts` (deleted).
- Users of `morphir gleam ...` or of the implicit Gleam provider must use the
  Gleam extension on the MoonBit CLI.
