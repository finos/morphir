# Tasks

Tracking: GitHub [#1153](https://github.com/finos/morphir/issues/1153) (Decisions on [#1146](https://github.com/finos/morphir/issues/1146)). No bead exists; the shared Dolt conflict blocked creation and no task id is cited. Do not run `bd dolt push` on Windows.

## 1. Source pin and release orchestration

- [x] 1.1 Pin finos/morphir-dotnet as `ecosystem/morphir-dotnet` (first `7c263485547598085ea83d7d12bf6328056affba`, then #590 candidates `8c15df5` and `51be09f`, now its merged `main` commit `0885f17264856521f0218151693c2b08810790ec`, still marked as a delivery candidate) and record it in `.config/cli-release.json`; verified by `bun run tools/cli-release.ts verify-source` and the source-pin tests in `tools/cli-release.test.ts`.
- [x] 1.2 Check the expected deployments, platforms and legacy platforms against the pinned `build/Helpers/ReleaseProfiles.cs`; verified by `bun test tools/cli-release.test.ts`.
- [x] 1.3 Rewrite `release.yml`: `v*` tags (decided 10 November 2026) newer than every existing one, builds through the source's `cli-offering.yml` at the pinned commit, per-platform launch qualification, legacy aliases from the Native AOT executable, a manifest, one create step that refuses an existing release; verified by the routing tests in `tools/cli-release.test.ts` and `python3 -B -m unittest discover -s tests/ci`.
- [x] 1.4 Qualify by launching the produced executable, apphost, `dotnet-morphir` and `dotnet morphir`, with macOS packaged input recorded as pending triage; verified by the qualification tests in `tools/cli-release.test.ts`.
- [ ] 1.5 Run the release workflow as a dry run (DRY-1), when the maintainer allows a tag and a dispatch; verified by the uploaded evidence, which must show `publishable: false` while any gate blocks. No fork, tag or dispatch has been made.
- [x] 1.6 Wire the build to `cli-offering.yml` at the candidate pin, with the commit identical in the gitlink, the config, `uses` and `ref`, and publication refused while `source.candidate` is set; verified by the routing and candidate tests in `tools/cli-release.test.ts`.
- [x] 1.7 Fix the review findings on #1155: paths resolved before subprocesses change directory, hidden qualification reports uploaded, assets collected recursively into an exact list that fails on missing or repeated artifacts, zip read on every platform, `--version` compared before `+`; verified by the regression tests in `tools/cli-release.test.ts` (a real packed executable qualified from an unrelated working directory with relative paths).
- [x] 1.9 Close the review of #1155 at `7bd446e`: restore the signed tool release metadata gate's application check in `morphir-dev-tools`; isolate both tool installs and tie every kept package copy to the artifact (TOOL-1); gate publication on the source's own release (PUB-1); bind the run, the checkout, the pin and each artifact's origin (BIND-1); add the dry run (DRY-1); match qualifications exactly; correct the prerequisites; retire `demo:desktop`; update the remaining commands that ran the deleted CLI; verified by `mise run ci:validate-tool-release-metadata`, `bun test tools/cli-release.test.ts` (including a real `dotnet tool install` against a conflicting feed and cache, and real zip extraction) and `python3 -B -m unittest discover -s tests/ci`.
- [x] 1.10 Install the tool package through the source's `.github/scripts/install-tool-package.ps1` at the pin, in tool-path and `-Local` mode with a `-ResultFile` each; launch only from each result's invocation, folder and environment; keep the parent's independent raw SHA-256 check of every stored copy; replace the interim install and its tripwire. Verified by `bun test tools/cli-release.test.ts`: the real helper against a conflicting feed and a warm cache in both modes, a tampered copy refused by the parent's own hashing, and refused result shapes.
- [ ] 1.8 Accept a final source release pin and remove `source.candidate` only after the source version/tag, forward-only parent version and actual release qualification gates pass; verified by `verify-source` and 1.5 repeated. #590's merge alone does not satisfy this task.
- [x] 1.11 Move the delivery tuple (gitlink, config, `uses`, `ref`) to merged #590 commit `0885f17264856521f0218151693c2b08810790ec`, retaining the candidate marker and the independent contract-test pin. Verified by source ancestry, unchanged helper/routing interface inspection, `verify-source` and lightweight release tests.

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
- [x] 4.4 Normally merge parent `main`, preserving #1147's .NET corpus job/filter/gates and Rust acquisition checker deletion, #1152's versioning policy and #1151's VERIFY-B/LAUNCH-A decisions. Reconcile ownership and gate accounting without changing retained Cargo dependency versions. Verified by `bun test tools/check-toolchain-contracts.test.ts tools/check-toolchain-corpus.test.ts`, workflow tests and lockfile comparison.

## Workflow follow-up

- Fresh independent review and CI are owned by the root thread, as #1153 asks. No local cargo/dotnet build, test or restore is run during this refresh without the root's CPU2 slot; the helper's real tool-install regression and task 2.4 remain unrun here.
- The user guides and examples that describe Rust CLI commands need rewriting against the .NET CLI; `test:examples` stays unavailable until then.
- `openspec/config.yaml` still says the repository owns "the Rust CLI"; it is protected here. Proposed ownership wording for its owner: "finos/morphir is the ecosystem umbrella repository, owning official Morphir CLI delivery (builds, qualification and releases of the .NET CLI from finos/morphir-dotnet, pinned as ecosystem/morphir-dotnet), the documentation website, shared specifications and ecosystem integration. Follow AGENTS.md and CONTRIBUTING.md. Keep domain logic pure and immutable, preserve versioned contracts and keep one runner per kit: morphir-mck for the retained gates and the .NET runner for new kits."
- Tags are `v<version>` (maintainer decision, 10 November 2026). The version comes from the pinned CHANGELOG and is not decided here. The publication gate refuses any version not newer than every existing `v*` tag, so the first .NET release cannot regress below `v0.4.0-beta.12` or reuse `0.4.0-alpha.4`; the source release must carry a version that passes, and nothing here bumps it.
- Command availability: the deleted Rust CLI's `package`, `metadata`, `decoration`, `eval`, `itest`, `ui`, `desktop`, `playground`, `diagnostics`, `cache`, `schema`, `transform`, `kb` and IR `migrate` have no .NET equivalent at the pin (`docs/getting-started/morphir-cli.md#command-availability-after-the-move`); the pages that rely on them are marked.
- The unarchived `remove-rust-cli-gleam-provider` change describes the deleted CLI; its owner decides whether to withdraw or archive it.
- Archive this change once 1.5, 1.8 and 2.4 are done.
