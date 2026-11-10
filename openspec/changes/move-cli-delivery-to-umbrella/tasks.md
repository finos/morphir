# Tasks

Tracking: GitHub [#1153](https://github.com/finos/morphir/issues/1153) (Decisions on [#1146](https://github.com/finos/morphir/issues/1146)). No bead exists; the shared Dolt conflict blocked creation and no task id is cited. Do not run `bd dolt push` on Windows.

## 1. Source pin and release orchestration

- [x] 1.1 Pin finos/morphir-dotnet as `ecosystem/morphir-dotnet` (first `7c263485547598085ea83d7d12bf6328056affba`, now the marked candidate `8c15df59ce902c3ec06bb2df0c8ab4a88445a39d` of draft #590) and record it in `.config/cli-release.json`; verified by `bun run tools/cli-release.ts verify-source` and the source-pin tests in `tools/cli-release.test.ts`.
- [x] 1.2 Check the expected deployments, platforms and legacy platforms against the pinned `build/Helpers/ReleaseProfiles.cs`; verified by `bun test tools/cli-release.test.ts`.
- [x] 1.3 Rewrite `release.yml`: `cli/v*` tags only, builds through the source's `cli-offering.yml` at the pinned commit, per-platform launch qualification, legacy aliases from the Native AOT executable, a manifest, one create step that refuses an existing release; verified by the routing tests in `tools/cli-release.test.ts` and `python3 -B -m unittest discover -s tests/ci`.
- [x] 1.4 Qualify by launching the produced executable, apphost, `dotnet-morphir` and `dotnet morphir`, with macOS packaged input recorded as pending triage; verified by the qualification tests in `tools/cli-release.test.ts`.
- [ ] 1.5 Run the release workflow end to end on GitHub against a disposable `cli/v*` tag in a fork, without publishing in finos/morphir; verified by the qualification JSON and manifest of that run.
- [x] 1.6 Wire the build to `cli-offering.yml` at the candidate pin, with the commit identical in the gitlink, the config, `uses` and `ref`, and publication refused while `source.candidate` is set; verified by the routing and candidate tests in `tools/cli-release.test.ts`.
- [x] 1.7 Fix the review findings on #1155: paths resolved before subprocesses change directory, hidden qualification reports uploaded, assets collected recursively into an exact list that fails on missing or repeated artifacts, zip read on every platform, `--version` compared before `+`; verified by the regression tests in `tools/cli-release.test.ts` (a real packed executable qualified from an unrelated working directory with relative paths).
- [ ] 1.8 After finos/morphir-dotnet #590 merges, move the pin, `uses` and `ref` to the merged `main` commit and remove `source.candidate`; verified by `verify-source` and 1.5 repeated.

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
- `openspec/config.yaml` still says the repository owns "the Rust CLI" and should "use the shared native Morphir MCK runner"; it is protected here. Proposed replacement for its first two sentences, for its owner: "finos/morphir is the ecosystem umbrella repository, owning official Morphir CLI delivery (builds, qualification and releases of the .NET CLI from finos/morphir-dotnet, pinned as ecosystem/morphir-dotnet), the documentation website, shared specifications and ecosystem integration. Follow AGENTS.md and CONTRIBUTING.md. Keep domain logic pure and immutable, preserve versioned contracts and use the shared MCK runner, morphir-mck."
- The tag prefix `cli/v*` is a proposal for review, and the version comes from the pinned CHANGELOG. The first .NET release would number below the last Rust release; it must not jump silently to clear the Rust numbers.
- Command availability: the deleted Rust CLI's `package`, `metadata`, `decoration`, `eval`, `itest`, `ui`, `desktop`, `playground`, `diagnostics`, `cache`, `schema`, `transform`, `kb` and IR `migrate` have no .NET equivalent at the pin (`docs/getting-started/morphir-cli.md#command-availability-after-the-move`); the pages that rely on them are marked.
- The unarchived `remove-rust-cli-gleam-provider` change describes the deleted CLI; its owner decides whether to withdraw or archive it.
- Archive this change once 1.5, 1.8 and 2.4 are done.
