# Tasks

Tracking: GitHub [#1153](https://github.com/finos/morphir/issues/1153) (Decisions on [#1146](https://github.com/finos/morphir/issues/1146)). No bead exists; the shared Dolt conflict blocked creation and no task id is cited. Do not run `bd dolt push` on Windows.

## 1. Source pin and release orchestration

- [x] 1.1 Pin finos/morphir-dotnet as `ecosystem/morphir-dotnet` at `7c263485547598085ea83d7d12bf6328056affba` and record it in `.config/cli-release.json`; verified by `bun run tools/cli-release.ts verify-source` and the source-pin tests in `tools/cli-release.test.ts`.
- [x] 1.2 Check the expected deployments, platforms and legacy platforms against the pinned `build/Helpers/ReleaseProfiles.cs`; verified by `bun test tools/cli-release.test.ts`.
- [x] 1.3 Rewrite `release.yml`: `cli/v*` tags only, per-platform `PackRelease` builds, launch qualification, legacy aliases from the Native AOT executable, a manifest, one create step that refuses an existing release; verified by the routing tests in `tools/cli-release.test.ts` and `python3 -B -m unittest discover -s tests/ci`.
- [x] 1.4 Qualify by launching the produced executable, apphost, `dotnet-morphir` and `dotnet morphir`, with macOS packaged input recorded as pending triage; verified by the qualification tests in `tools/cli-release.test.ts`.
- [ ] 1.5 Run the release workflow end to end on GitHub against a disposable `cli/v*` tag in a fork, without publishing in finos/morphir; verified by the qualification JSON and manifest of that run.
- [ ] 1.6 Choose the final delivery pin after finos/morphir-dotnet #590 (MCK dispatch, `cli-offering.yml`) is merged, and optionally move the build steps to that workflow; verified by `verify-source` at the new pin and 1.5 repeated.

## 2. Standalone MCK runner

- [x] 2.1 Move the MCK command layer and its tests to `crates/morphir-mck-cli` (`morphir-mck`), with the command tree, adapters, frozen expectations and exit codes unchanged and JSON member order stated; verified by `cargo test --locked -p morphir-mck-cli`.
- [x] 2.2 Point the MCK and package tasks and tools at `morphir-mck`; verified by `bun test tools/package-ci.test.ts tools/package-mck-command.test.ts tools/run-mck-gate.test.ts` and `tools/cli-release.test.ts`.
- [x] 2.3 State the delegation rule in `spec/mck/cli-contract.md`; verified by review against `specs/mck/standalone-runner/spec.md`.
- [ ] 2.4 Confirm the .NET CLI's `morphir mck` delegates to `morphir-mck` once the source-side dispatch lands; verified by running the same gate through both spellings.

## 3. Internal development tool and gate accounting

- [x] 3.1 Move `kb` and the library-level gates to `crates/morphir-dev-tools` (`morphir-dev`); verified by `cargo test --locked -p morphir-dev-tools`.
- [x] 3.2 Retire the product gates by name and make `test:examples` and `migrate:validate` stop with a pointer; verified by `tools/cli-release.test.ts` (no task runs the deleted CLI) and the gate table in `design.html`.
- [x] 3.3 Move the YAML profile fixtures the website gate reads to `tests/fixtures/ir-yaml-profile`; verified by `mise run website:test-ir-storage-profiles`.

## 4. Deletion and ownership

- [x] 4.1 Delete `crates/morphir`, `integration-tests`, `morphir-decoration`, `morphir-evaluator`, `morphir-opa`, the generated CLI reference and the unused workspace dependencies; verified by `cargo clippy --locked -p morphir-mck-cli -p morphir-dev-tools --all-targets -- -D warnings` and a lockfile that only removes packages.
- [x] 4.2 Replace the CI jobs of the Rust CLI with `rust-dev-tools`; verified by `python3 -B -m unittest discover -s tests/ci`.
- [x] 4.3 Update ownership in `AGENTS.md` (outside the Contract Versioning block), `ecosystem/AGENTS.md`, `INSTALLING.md`, `DEVELOPING.md`, the kb skill and `add-deployment-and-acquisition`; verified by `openspec validate move-cli-delivery-to-umbrella --strict` and `openspec validate add-deployment-and-acquisition --strict`.

## Workflow follow-up

- Fresh independent review of both repository implementations, as #1153 asks.
- The user guides and examples that describe Rust CLI commands need rewriting against the .NET CLI; `test:examples` stays unavailable until then.
- `openspec/config.yaml` still calls the Rust CLI the repository's product; it is outside this change's authorized files.
- The unarchived `remove-rust-cli-gleam-provider` change describes the deleted CLI; its owner decides whether to withdraw or archive it.
- Archive this change once 1.5, 1.6 and 2.4 are done.
