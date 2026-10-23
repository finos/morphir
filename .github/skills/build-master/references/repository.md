# Morphir MoonBit build context

Read root `AGENTS.md` and `.github/AGENTS.md`. This checkout carries the complete build-master skill, so contributors and hosted agents do not need a personal installation. Edit `.github/skills/build-master/`; `.agents/skills/`, `.claude/skills/`, and `.grok/skills/` contain discovery links.

## Find the execution owners

- `.github/workflows/ci.yml` owns routine CI and the `ci-ok` aggregate. Inspect the current dependency list and repository rules before asserting which checks block merging.
- `scripts/ci-changes.mbtx` selects work from changed components and dependencies. `scripts/ci-gate.mbtx` interprets selected results. Use `mise run test:ci` when changing this policy.
- `.github/workflows/qualification.yml` owns full installation/platform qualification and its candidate receipt. It is `workflow_call` only, so read its callers before proposing another qualification job: `ci.yml` calls it with `macos: skip`, and `nightly-qualification.yml` is the entry workflow for the macOS lanes.
- `.github/workflows/ci-native.yml`, `.github/workflows/ci-installed.yml`, and `.github/workflows/ci-packaged.yml` contain reusable check categories. Read their contracts before extending them.
- `.github/workflows/headless-cli.yml` has an independent execution path. Trace its selectors and the application harness before assuming its checks or builds are unique.
- `apps/morphir/scripts/test.ts`, `.config/mise/config.toml`, and `scripts/ci-artifact.mbtx` help explain hidden compilation, packaging, actual-host tests, and artifact compatibility. Similar step labels do not establish duplicate execution.

This is a navigation map, not an assertion that all existing placements are optimal. Use current files and run evidence to decide.

## Scarce runners

macOS runners and some Windows runners are scarce for this repository. Every macOS label counts. Treat larger, ARM64 and other non-standard Windows labels the same way. Standard `windows-latest` jobs are less scarce, but they set up slowly and are subject to cold-start timing, so plan each new one. Contributors send every decision that adds, moves or reselects such a job to the build-master (see `.github/AGENTS.md`).

Maintainer decision (2026-10-23): macOS does not belong in pull-request or merge-queue CI. macOS coverage moves to nightly, manual or release execution with fingerprinted evidence, so a run is skipped when trusted evidence already covers the same inputs. Bead `morphir-ukvn.5.90.11` tracks that change.

The rule now holds. No job reachable from `pull_request`, `pull_request_target`, `merge_group` or a branch `push` may get a macOS runner, and `moonx scripts/ci-platforms.mbtx` enforces it. `mise run test:ci` runs the guard, and `mise run ci:platforms` runs it alone. Do not add an exception. `ci.yml` calls `qualification.yml` with `macos: skip`; its five macOS jobs (`macos-setup`, `macos-native`, `macos-installed`, `macos-supervision`, `macos-headless`, all on `macos-15`) run only when a caller passes `macos: run`. The nightly entry (`nightly-qualification.yml`, 03:23 UTC, or `gh workflow run nightly-qualification.yml --ref main -f macos=run`) does that, and its `report` job keeps one `macos-breach` issue titled `macOS qualification breach`. A release workflow must call `qualification.yml` with `macos: run` on the tag commit and check the v2 receipt for `revision` equal to the candidate and `macos` equal to `run`. Nightly results and evidence never qualify a candidate. `CONTRIBUTING_DEV.md` has the full contract.

Only the entry workflows in the qualification graph (`ci.yml`, `nightly-qualification.yml`, `headless-cli.yml`) set `concurrency`, schedules and write permissions; `qualification.yml` sets no workflow-level `concurrency`. One exception: `headless-cli.yml` is both an entry workflow (pull request, dispatch) and a callee of `qualification.yml`, and it keeps its workflow-level `concurrency`. When called, its group includes `github.run_id` and it does not cancel, so it is harmless. To run it on macOS by hand, use `gh workflow run headless-cli.yml -f runners='["macos-15"]'`.

### Platform attestation trailer

A committer who built and tested a change on a platform can add one `Tested-on:` Git trailer per platform to the commit message, next to `Signed-off-by:`. Give the operating system, version and architecture, then the commands that ran. For example:

```text
Tested-on: macOS 15 arm64; mise run lint, mise run validate, bun run --cwd apps/morphir-workbench test
Tested-on: Windows 11 arm64; node apps/morphir/build-provider/test-supervision.mts
```

Copy the trailers into the PR description, because a squash merge keeps only the reviewed message. The trailer is a hint for review and for platform-lane planning. It is not evidence, and no gate, selector or evidence lookup may read it as a pass. The maintainer develops mainly on macOS and also on Windows ARM64, so these two platforms often have this kind of attestation.

Evidence from 2026-10-23: about 40 jobs waited for macOS runners while about 13 ran. Most of them came from the full qualification lanes that `ci.yml` calls when change selection sets `full`; those calls now skip the macOS jobs. One merge-queue entry was removed with `checks_timed_out` while its macOS jobs waited, and the queue rebuilt the entries behind it.

## Repository constraints

Keep orchestration in standalone MoonBit `.mbtx` scripts. Reuse the tested selector and gate policy rather than adding inline shell orchestration. Direct application compiler and test invocations can remain declarative workflow steps.

Run the repository's required lint, MoonBit formatting, and validation checks before pushing. CI policy changes also require `mise run test:ci`. Use the canonical instructions for the exact current commands.

Keep human-reviewed specifications and implementation plans in the approved HTML format and shared beads workflow. A short review can return directly to its coordinator without creating a report. Scope, tracker updates, merges, releases, and deployment authority follow repository instructions and the user's existing authorization.
