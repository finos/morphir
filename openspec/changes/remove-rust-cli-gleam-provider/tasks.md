# Tasks

## 1. Provider registry and commands (bead morphir-ukvn.1.17)

- [x] 1.1 Remove the `morphir-gleam-binding` dependency, the built-in Gleam provider and the legacy selector alias, and port the registry, compile, pool and playground unit tests to the native Elm provider or installed fixtures; verified by `cargo test --locked -p morphir --lib`.
- [x] 1.2 Remove the `gleam` subcommand and the roundtrip-only project check, and regenerate the CLI reference, man page and completions; verified by `mise run docs:cli` with no further diff.

## 2. Tests, examples and docs (bead morphir-ukvn.1.17)

- [x] 2.1 Remove the Gleam tests and examples, and port the tests that cover other behavior; verified by `cargo test --locked --workspace`.
- [x] 2.2 Port the package examples to a native Elm model that stops after restore, and update the itest list fixture; verified by `morphir itest examples --filter package/` and `cargo test --locked -p morphir --test itest`.
- [x] 2.3 Point docs, the CHANGELOG and the examples catalog to finos/morphir-gleam and the MoonBit CLI; verified by `git grep -n -i "morphir gleam "` with no user-facing hits.

## 3. MEP contract tooling (decision MEP-1)

- [x] 3.1 Make `mep_contract` read the committed IR, remove the drift test, make `spec:mep` stop with a pointer and update `spec/mep/README.md`; verified by `mise run spec:mep-check` and `mise run spec:mep` exiting with the message.
- [x] 3.2 File bead `morphir-sugs` to restore generation and the drift check with the morphir-gleam extension; verified by `bd show morphir-sugs`.

## 4. Submodule and beads

- [x] 4.1 Move `ecosystem/morphir-gleam` to finos/morphir-gleam `main`; verified by `git submodule status ecosystem/morphir-gleam`.
- [x] 4.2 Close bead `morphir-ukvn.1.4` as superseded by finos/morphir-gleam#23, remove it as a blocker of `.1.8` and `.1.9`, and note the move on `morphir-4q8g.*` and `morphir-ukvn.5.64.28`; verified by `bd show`.
- [x] 4.3 Validate this change; verified by `openspec validate remove-rust-cli-gleam-provider --strict` and `mise run openspec:verify`.

## Workflow follow-up

- Follow AGENTS.md for review, merge approval, archive and closing bead `morphir-ukvn.1.17`.
