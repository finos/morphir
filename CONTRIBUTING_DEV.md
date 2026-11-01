# Contributing to Morphir Moonbit

Thank you for your interest in contributing to Morphir Moonbit! This document provides guidelines and instructions for setting up your development environment and contributing to this monorepo.

## Development Environment Setup

### Prerequisites

1. **Install mise**: Follow the [official installation guide](https://mise.jdx.dev/getting-started.html)

2. **Install development tools**: Run `mise install` in the repository root to install all required tools:
   - MoonBit toolchain pinned in `.config/mise/config.toml`
   - Bun pinned in `.config/mise/config.toml`
   - yamllint
   - uv (Python package manager)

### First-Time Setup

```bash
# Clone the repository
git clone https://github.com/finos/morphir-moonbit.git
cd morphir-moonbit

# Install all development tools
mise install
```

On Linux x64, Linux ARM64 and Apple Silicon, mise completes the MoonBit archive
with the official installer, including matching core libraries and `moonx`.
To repair an installation made before this setup step was added, run
`mise install --force http:moonbit`. CI keeps a completion check for older caches.

**Note**: Git hooks are automatically installed when you enter the directory (via mise hooks). The pre-push hook runs lint, format check, and validation before allowing any push.

### Git Hooks (Automatic Setup)

### Git Hooks (Automatic Setup)

Git hooks are **automatically installed** when you enter the directory (mise hook). You can also manually run:

```bash
mise run setup:hooks
```

This installs a pre-push hook that automatically runs lint, format check, and validation before allowing any push. This ensures you catch issues locally before they fail in CI. The setup is idempotent and runs automatically, so you don't need to worry about it.

## Pre-Push Requirements

**⚠️ CRITICAL**: All changes must pass lint, format, and validation checks before pushing.

### Required Checks Before Push

1. **Linting** - YAML and Moonbit code style
2. **Format Check** - Moonbit code formatting
3. **Validation** - Package structure and configuration

### Running Checks

```bash
# Run all checks at once
mise run check

# Or run individual checks
mise run lint           # Linting
mise run lint:moonbit   # Format check
mise run validate       # Validation
```

The pre-push hook automatically runs these checks, but you can (and should) run them manually during development to catch issues early.

### Bypassing Checks (Not Recommended)

While you can bypass the pre-push hook with `git push --no-verify`, this is **strongly discouraged** as it will cause CI failures and block your PR from being merged.

## Monorepo Structure

This repository uses a monorepo structure with multiple Moonbit packages:

```
morphir-moonbit/
├── .config/mise/          # Mise configuration and tasks
├── pkgs/                  # Moonbit packages (workspace members)
│   ├── morphir-sdk/
│   ├── morphir-core/
│   └── morphir-moonbit-bindings/
├── moon.mod               # Root module configuration
└── moon.work              # Workspace manifest (member modules)
```

## Development Workflow

### Working with Code

1. **Make your changes** in the relevant package under `pkgs/`

2. **Format your code**:
   ```bash
   mise run format
   ```

3. **Check formatting**:
   ```bash
   mise run lint:moonbit
   ```

4. **Run tests**:
   ```bash
   mise run test
   ```

### Building

Build for specific targets:

```bash
# Build for WASI (server-side, CLI)
mise run build:wasi

# Build for browser (WASM-GC)
mise run build:browser

# Build for all targets
mise run build
```

### Running Tasks

All development tasks are managed through mise:

```bash
# List all available tasks
mise tasks

# Run a specific task
mise run <task-name>

# Examples:
mise run lint          # Run all linting
mise run lint:yaml     # Lint YAML files only
mise run format        # Format all code
mise run test          # Run all tests
```

## Code Style

- **Moonbit**: Follow standard Moonbit formatting (enforced by `moon fmt`)
- **YAML**: Follow yamllint rules defined in `.yamllint.yml`
- All code must pass linting before being merged

## Testing

- Every package should have corresponding test files
- Test files should be named `*_test.mbt`
- All tests must pass in CI before merging

## Continuous Integration

CI runs on pull requests, merge-queue commits and pushes to main. Lint, formatting and
configuration validation always run. Code changes keep four-target unit tests, portable
builds, CLI smoke tests and a Linux native CLI/MEP process check. Documentation-only
changes skip code checks; site inputs also build and test the site. The separate Site
workflow handles main deployment.

`scripts/ci-changes.mbtx` selects additional Linux acceptance from changed components.
Compiler, frontend, conformance, signed-provider, installed-lifecycle, telemetry and
Workbench checks have separate selections. Shared IR, engine, host, toolchain and unknown
inputs conservatively select every suite. MEP-adapter changes use the baseline native
process tests, while Workbench changes select their native ownership/grant checks.
Renames retain deleted paths. PR/merge-queue diffs use the merge base; main pushes compare
the actual before/after commits, including divergent pushes. Empty or unavailable push
diffs select every suite. Run `mise run test:ci` to test these rules and aggregate gates.

The **Full qualification** workflow (`.github/workflows/qualification.yml`) is reusable and
has no trigger of its own. Its callers choose the macOS mode with the `macos` input: `skip`,
`run` or `reuse`. It preserves the full Linux matrix, debug/release installed execution,
signed providers, telemetry, native workspace release build, compiler/frontend/conformance
and native Workbench checks. The five macOS jobs (`macos-setup`, `macos-native`,
`macos-installed`, `macos-supervision` and `macos-headless`, all on `macos-15`) run only
when the mode is `run`. On `macos-15`, `macos-native` runs the native CLI acceptance on this
run's darwin-arm64 executable and the npm CLI acceptance (`bun run --cwd apps/morphir test
js`), which includes the Extism worker check of the npm entry. Its `qualification-ok` job writes an Ion receipt, profile
`morphir-ci-qualification-v2`, bound to the exact candidate commit and workflow run. The
receipt records the `macos` mode.

Pull requests, merge-queue commits and pushes to main never get a macOS runner. `ci.yml`
calls full qualification with `macos: skip` when change selection requires it, and the
workflow refuses `run` and `reuse` on those events. `scripts/ci-platforms.mbtx` is a static
guard that fails when a job reachable from `pull_request`, `pull_request_target`,
`merge_group` or a branch push can get a macOS runner. `mise run test:ci` runs it. To run it
alone, use `mise run ci:platforms`. Process supervision runs on Linux and Windows for these
events; the headless CLI check runs on Linux and Windows for pull requests.

The **Nightly qualification** workflow (`.github/workflows/nightly-qualification.yml`) runs
every day at 03:23 UTC and calls full qualification for the macOS jobs. First, its
`evidence` job calculates the fingerprint of the macOS inputs
(`moonx scripts/ci-evidence.mbtx fingerprint`) and looks for evidence with that
fingerprint: an artifact named `macos-evidence-v1-<fingerprint>`. The job trusts the
evidence only when the GitHub API shows that the run that uploaded it:

- ran `.github/workflows/nightly-qualification.yml` in this repository, not in a fork,
  on the branch `main`, at a commit in the history of `refs/heads/main` (a run on a tag
  named `main` does not count);
- had the event `schedule` or `workflow_dispatch` and the conclusion `success`;
- was created at most 7 days ago, and that the artifact has not expired.

When it finds trusted evidence, the call uses `macos: reuse`. The macOS jobs skip, and the
receipt records the evidence reference. When it finds none, the call uses `macos: run`.
While a `macos-breach` issue is open, the job does not look for evidence and the call uses
`macos: run`, so older evidence cannot hide a newer failed run on the same inputs.

The job tries each GitHub API call again once. If the artifact listing, or the read of a
run that uploaded an artifact, fails again, the call uses `macos: run` and the job shows
a warning. If the open `macos-breach` issue cannot be read, the call also uses
`macos: run` with a warning. If only the check that a producing run's commit is on `main`
fails, the job refuses that evidence. An API error does not fail the night.

After a `run` pass on main, the `record` job uploads new evidence, which GitHub keeps for 8
days. A reuse run records no evidence. Thus the 7-day limit makes the macOS jobs run at
least once each week, also when no input changes, so that drift in the `macos-15` runner
image or in downloaded tools cannot stay hidden.

To run it by hand, dispatch it on main. `-f macos=evidence` (the default) reuses trusted
evidence when it can, and `-f macos=run` always runs the macOS jobs:

```sh
gh workflow run nightly-qualification.yml --ref main -f macos=evidence
gh workflow run nightly-qualification.yml --ref main -f macos=run
```

A nightly run that fails or is cancelled opens one GitHub issue labelled `macos-breach`,
titled `macOS qualification breach`. A failure of the `evidence` job or of the `record` job
is also a breach. The issue lists the run, the commit, the macOS mode and the jobs that
failed. A later failure comments on that issue. Only a run that passes with `macos: run`
closes it; a reuse run does not. The report job runs only on main. To run one macOS job on
a branch, for example the headless CLI check, dispatch `headless-cli.yml` with the runner
labels:

```sh
gh workflow run headless-cli.yml --ref <branch> -f runners='["macos-15"]'
```

Release contract: a release workflow (planned in bead `morphir-ukvn.5.88.3`) starts from a
tag push or `workflow_dispatch`. It calls `.github/workflows/qualification.yml` on the tag
commit with `macos: run`, from a job that grants `contents: read` and
`attestations: read`. Publication `needs` that call. It also checks that the v2 receipt has
`revision` equal to the candidate commit and `macos` equal to `run`. A scheduled nightly
run on main, nightly evidence or the receipt of another commit does not qualify a
candidate. A dispatch on the tag with `macos=run` does, because it runs macOS on that
commit; a dispatch with `macos=evidence` can reuse evidence and does not. For a manual
qualification of a candidate, dispatch the nightly workflow on the tag with
`gh workflow run nightly-qualification.yml --ref <tag> -f macos=run`, verify that the
run's `headSha` equals the candidate and retain its successful receipt.

```sh
gh run view <run-id> --json headSha,conclusion,url
```

For a release candidate, run both ordinary CI and full qualification on that same commit.
Workflow, CI-policy, setup-action, workspace and toolchain configuration changes also
select the full qualification workflow before merge, without the macOS jobs. It replaces
the focused native and installed jobs for that run, so artifacts and costly checks are not
produced twice.

Jobs start after change detection, while lint and formatting run in parallel. `ci-ok`
requires every selected job to succeed, including the aggregates inside reusable
workflows. Failed/cancelled producers and unexpectedly skipped selected jobs fail the
gate. Unselected jobs may skip. Full qualification is separate from the ordinary PR
gate. New PR commits cancel superseded PR runs; main and merge-queue runs finish.

CI and mise orchestration use pinned MoonBit `.mbtx` scripts. The `check` task is
`scripts/check.mbtx`; the other task names are declared in `.config/mise/config.toml`
and dispatch to standalone scripts. Compilers and existing application tests remain direct tool
invocations. CI rejects added/modified legacy task wrappers and non-MoonBit automation
under `scripts/`, while allowing their deletion during migration. The setup action caches
the pinned toolchain, including core and moonx. Repository automation regressions run
in `mise run test:ci` and the existing qualification setup matrix. Git's
pre-push entry point is a thin dispatcher to `scripts/pre-push.mbtx`; hook installation
also works in linked worktrees and preserves unrelated custom hooks.

Ubuntu 26.04 producers use pinned Zig 0.17.0 for native CLI release artifacts. Focused PR
checks produce Linux x64; the macOS jobs of full qualification also cross-build macOS arm64
and execute those exact bytes on macOS 15 in the nightly and release runs.
Default-C-compiler native workspace release builds remain in full qualification. Workbench
workers and workspace grants have separate parallel jobs, rather than extending every
installed CLI lifecycle job.

The focused and full native categories execute on Ubuntu 26.04. Their reusable workflow
also accepts Ubuntu 24.04, and every Linux consumer uses the requested runner and its
matching artifact name. The native gate requires the same selected producers and consumers
on either Linux version. Installed, packaged, headless and toolchain setup checks retain
their Ubuntu 24.04 coverage. macOS execution remains in nightly and release runs.

Released provider-tool acquisition runs in parallel with native compilation. CI downloads
the separately packaged service and test-fixture exporter instead of installing Rust or
compiling Cargo targets.
The provider release's pinned Ubuntu 24.04 label records its upstream qualification;
it is not the consumer's runner label. Its authenticated release identity stays unchanged
when the native category executes those Linux x64 binaries on Ubuntu 26.04.

Each executable artifact has a binary Ion catalog. Consumers verify the repository,
commit, workflow run, target platform, architecture and executable SHA-256. Cross-built
CLI catalogs also check the binary's ELF or Mach-O header, pinned compiler version and
core source identity. They retain the producer's compiler executable hash, runner image,
Zig version, target triple and build duration separately from the target identity. A
consumer's different-platform compiler executable does not have the producer's hash.
Same-host native artifacts and provider tools retain their exact context checks. Artifacts
are scoped to a workflow run, including reruns of individual jobs. They never reuse
trust state, signed fixtures, grants, project outputs or qualification receipts.

The annotated Ion lock at
`apps/morphir/fixtures/authenticated-provider/provider-release.ion` pins the release
commit and descriptor, archive and executable digests. Acquisition verifies GitHub
attestations against the upstream repository, release workflow, exact source commit
and tag before extraction. Both tools must match their qualified platform and protocol.
A failed verification ends the job; CI never silently builds a substitute from source.
The catalog also covers `release-admission.ionb`, which retains the lock, descriptor
and successful attestation results. Installed-provider evidence includes that receipt.

The installed-provider job still runs all qualification cases against both the npm and
native clients. Long phases stream their output and report elapsed milliseconds.
The `installed-provider-<os>` artifact retains `phase-timings.ionb`, the validated tool
catalogs, the qualification summary and audit evidence. Its summary records the actual
Rust compiler and service build mode.

To acquire the same released tools locally with an authenticated `gh` CLI:

```sh
moon run scripts/ci-provider-release.mbtx --self-test
moon run scripts/ci-provider-release.mbtx
```

Local qualification keeps its explicit source-build defaults:

```sh
MORPHIR_PROVIDER_RUST=/path/to/clean/accepted/morphir-rust mise run test:installed-provider
```

To reproduce CI reuse, first build from a clean MoonBit checkout with the pinned complete
toolchain and Node available. Keep all artifact directories outside tracked paths:

```sh
mise run build:ci-native -- linux-x64 # use darwin-arm64 on macOS
moon run scripts/ci-artifact.mbtx pack-cross native-cli .dev/ci/native linux-x64
moon run scripts/ci-provider-release.mbtx
MORPHIR_CI_NATIVE="$PWD/.dev/ci/native" MORPHIR_CI_PROVIDER_TOOLS="$PWD/.dev/ci/provider-tools" mise run test:installed-provider
```

`moon run scripts/ci-artifact.mbtx --self-test` checks artifact validation and rejection.
`moonx scripts/ci-native-build.mbtx --self-test` checks wrapper argument handling and target
restrictions. Cross-build wrappers follow [Smithy's implementation](https://github.com/moonrockz/smithy/tree/main/apps/zig-cross)
and remove host-only SIMD/backtrace objects, keeping MoonBit's scalar UTF runtime. Windows
cross-builds remain disabled because MoonBit resolves platform configuration from the
build host; see [moon#2320](https://github.com/moonbitlang/moon/issues/2320).
The required `ci-ok` aggregate includes selected producer/consumer workflow results.
Their nested gates require each selected producer and consumer to pass, so a failed
producer cannot be hidden by a skipped consumer. `qualification-ok` applies the same
rule to the complete platform matrix.

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes following the guidelines above
4. Run `mise run lint` and `mise run test` locally
5. Commit your changes with descriptive commit messages
6. Push to your fork
7. Open a Pull Request

### Pull Request Requirements

- All CI checks must pass
- Code must be formatted (run `mise run format`)
- Tests must be included for new functionality
- Documentation should be updated if applicable

## Adding New Packages

To add a new package to the monorepo:

1. Create a new directory under `pkgs/`
2. Add a `moon.mod` file with module metadata
3. Add a `moon.pkg` file with package configuration
4. Register the module in the root `moon.work` workspace manifest
5. Add source files (`*.mbt`) and test files (`*_test.mbt`)

Example `moon.mod`:

```moonbit
name = "finos/my-new-package"

version = "0.1.0"

import {
  "finos/morphir-core@0.1.0",
}

readme = "README.md"

repository = "https://github.com/finos/morphir-moonbit"

license = "Apache-2.0"

keywords = [ "morphir", "example" ]

description = "Description of the package"
```

Example `moon.pkg` (a library package is the default, so no `pkgtype` is needed):

```moonbit
import {
  "finos/morphir-core",
}
```

Then add the module to the root `moon.work` so it is resolved from source:

```moonbit
members = [
  "./pkgs/morphir-core",
  "./pkgs/my-new-package",
]
```

## Troubleshooting

### Tool Installation Issues

If `mise install` fails:

1. Check mise version: `mise --version`
2. Update mise: `mise self-update`
3. Clear cache: `mise cache clear`
4. Try installing tools individually: `mise install bun`, `mise install yamllint`, etc.

### Build Issues

If builds fail:

1. Ensure tools are installed: `mise list`
2. Check moonbit version: `moon version`
3. Clean build artifacts: `mise run clean` (or `rm -rf _build`)
4. Try building individual packages: `moon -C pkgs/<package-name> build`

### Test Failures

If tests fail:

1. Run tests for a single module: `moon -C pkgs/<package-name> test`, or the whole workspace with `moon test`
2. Check test output for specific error messages
3. Ensure all dependencies are properly installed

## Questions?

- Open an [issue](https://github.com/finos/morphir-moonbit/issues) for bugs or feature requests
- Email morphir@finos.org for general questions
- Check existing documentation in the repository

## Code of Conduct

Please note that this project is released with a [Contributor Code of Conduct](https://www.finos.org/code-of-conduct). By participating in this project you agree to abide by its terms.

## License

By contributing to Morphir Moonbit, you agree that your contributions will be licensed under the Apache License, Version 2.0.


## TypeScript and Bun

Use the pinned Bun 1.4.3 toolchain through mise. Each existing dependency root
keeps its own `bun.lock`; install with `bun install --frozen-lockfile`. The root
package provides shared types and declaration emission. Browser, Web Worker,
Node and Bun build scripts have separate strict TypeScript projects.

```sh
mise run check:typescript
mise run setup:workbench
mise run test:workbench
mise run test:embedding
```

`bun check --all` checks every project, including scripts and tests that no entry
point imports. `bun run test:types` proves that invalid types fail both whole
project checks and checked builds, and that Bun globals stay out of browser,
worker and Node projects. Build scripts use `Bun.build({ check: true })`.
Running TypeScript alone does not replace these checks.

Write handwritten UI and JavaScript tooling in `.ts` or `.mts`. Build the
portable runtime files with `bun run build:runtimes` before invoking Node hosts.
The emitted `.js` and `.mjs` paths preserve the installed CLI and embedding
contracts. Do not commit those generated files. MoonBit compiler output, JavaScript
FFI strings and JavaScript snippets executed in Node/browser acceptance tests
remain JavaScript. Runtime JSON/Ion validation is still required.

Published npm packages contain JavaScript. Consumers need Node, not Bun or
TypeScript. Acceptance tests deliberately run Node and the real npm CLI to check
that boundary. The embedding build uses TypeScript 7 only to emit declarations;
Bun supplies the whole-project checker and checked bundler.

Changed task automation lives in portable MoonBit `.mbtx` scripts. The Bun build
scripts implement JavaScript bundling; `scripts/typescript-tooling.mbtx` wires
installation, builds and compatibility tests into mise.
