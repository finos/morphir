# Morphir MoonBit build context

Read root `AGENTS.md` and `.github/AGENTS.md`. This checkout carries the complete build-master skill, so contributors and hosted agents do not need a personal installation. Edit `.github/skills/build-master/`; `.agents/skills/`, `.claude/skills/`, and `.grok/skills/` contain discovery links.

## Find the execution owners

- `.github/workflows/ci.yml` owns routine CI and the `ci-ok` aggregate. Inspect the current dependency list and repository rules before asserting which checks block merging.
- `scripts/ci-changes.mbtx` selects work from changed components and dependencies. `scripts/ci-gate.mbtx` interprets selected results. Use `mise run test:ci` when changing this policy.
- `.github/workflows/qualification.yml` owns full installation/platform qualification and its candidate receipt. Read its callers and triggers before proposing another qualification job.
- `.github/workflows/ci-native.yml`, `.github/workflows/ci-installed.yml`, and `.github/workflows/ci-packaged.yml` contain reusable check categories. Read their contracts before extending them.
- `.github/workflows/headless-cli.yml` has an independent execution path. Trace its selectors and the application harness before assuming its checks or builds are unique.
- `apps/morphir/scripts/test.ts`, `.config/mise/config.toml`, and `scripts/ci-artifact.mbtx` help explain hidden compilation, packaging, actual-host tests, and artifact compatibility. Similar step labels do not establish duplicate execution.

This is a navigation map, not an assertion that all existing placements are optimal. Use current files and run evidence to decide.

## Repository constraints

Keep orchestration in standalone MoonBit `.mbtx` scripts. Reuse the tested selector and gate policy rather than adding inline shell orchestration. Direct application compiler and test invocations can remain declarative workflow steps.

Run the repository's required lint, MoonBit formatting, and validation checks before pushing. CI policy changes also require `mise run test:ci`. Use the canonical instructions for the exact current commands.

Keep human-reviewed specifications and implementation plans in the approved HTML format and shared beads workflow. A short review can return directly to its coordinator without creating a report. Scope, tracker updates, merges, releases, and deployment authority follow repository instructions and the user's existing authorization.
