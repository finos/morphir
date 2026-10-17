---
order: 35
---
# Mise Tasks Reference

This document provides a reference for all available mise tasks in the Morphir Moonbit monorepo.

## Task Categories

### Linting Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run lint` | Run all linting tasks | All |
| `mise run lint:yaml` | Lint YAML files | All |
| `mise run lint:moonbit` | Check Moonbit code formatting | All |

### Formatting Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run format` | Format all Moonbit code | All |

### Build Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run build` | Build all packages for all targets | All |
| `mise run build:wasi` | Build all packages for WASI target | All |
| `mise run build:browser` | Build all packages for browser (WASM-GC) target | All |
| `mise run build:js` | Build all packages for JavaScript | All |
| `mise run build:workbench` | Build the shared Rabbita browser frontend and runtime worker | All |
| `mise run build:native` | Build native release executables | All |

### Test Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run test` | Run tests for all packages | All |
| `mise run test:workbench` | Test the local pipeline, connected v1 protocol, loopback proxy and browser workflows | All |
| `mise run test:workbench-live-host -- --host-bin /absolute/path/to/morphir` | Test authenticated connected v1 workflows against an installed Rust UI host | All |
| `mise run test:workbench-native-session` | Test desktop session authority and revocation without CEF | All |
| `mise run test:workbench-native-workers` | Qualify real owned native workers, exact values, bounded I/O, cancellation and shutdown without CEF | macOS/Linux |
| `mise run test:workbench-native-client-mck` | Qualify production client draft.9 scenarios in Node/Chromium with debug/release cores and independent report checks | Bun, Node, Chromium and explicit parent runner/kit |
| `mise run test:workbench-native-owner-mck` | Qualify production owner draft.10 traces in native debug/release with independent report checks | Bun and explicit parent runner/kit |
| `mise run test:workbench-native-workspaces` | Qualify real read-only grants, traversal/link/replacement refusals, original-byte chunks and revocation without CEF | macOS/Linux |
| `mise run test:workbench-capability-policy-mck` | Opt-in exact draft.12 capability-policy qualification through the shared Rust runner in Node/Chromium/native debug/release; requires explicit runner/kit and Workbench Chromium dependencies | All |
| `mise run test:conformance` | Compare versioned independent Ion expectations, live Scheme and explicitly pinned optional Rust; retain separate coverage receipts | All |
| `mise run test:cli` | Run CLI target and npm package smoke tests | All |
| `mise run test:moonbit-frontend` | Compare original Boolean MoonBit, Scheme and generated libraries across four targets in debug and release; requires pinned `MOON_HOME` and retains identities | All |
| `mise run test:supervision` | Verify process-tree cleanup, cancellation, deadlines and bounded diagnostics on Linux, macOS and Windows | All |
| `mise run test:embedding` | Install embedding dependencies and Chromium, then test Node, installed npm and browser hosts | All |

### Utility Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run check` | Run all checks (lint + test + build) | All |
| `mise run clean` | Clean build artifacts | All |
| `mise run validate` | Run all validation checks | All |
| `mise run validate:packages` | Verify package structure is valid | All |
| `mise run list-tasks` | List all available mise tasks | All |

### Setup Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run setup:workbench` | Install workbench npm dependencies and Chromium; `--ci` adds Linux system dependencies | All |
| `mise run setup:hooks` | Install git hooks for pre-push validation (idempotent, auto-runs on directory entry) | All |

### Site Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run setup:site` | Install site build dependencies and Chromium for the smoke test | All |
| `SITE_MAIN=1 mise run build:site` | Build the project site into `_site/` (`SITE_MAIN=1` fails on draft pages) | All |
| `mise run dev:site` | Serve `_site/` at http://127.0.0.1:4173/morphir-moonbit/ and rebuild on content changes | All |
| `mise run check:site` | Check links, titles, the Atom feed and forbidden paths in the built `_site/` | All |
| `mise run test:site` | Site unit tests, highlight tests and the browser smoke test against `_site/` | All |

### Beads Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run beads:plan -- <command>` | Store superpowers specs, plans and ledgers in beads and render them back, with `bd-plan` fetched from finos/morphir at a pinned commit (see [AGENTS.md](../AGENTS.md)) | All |

## Task Structure

Tasks are organized in the `.config/mise/tasks/` directory:

```
.config/mise/tasks/
├── lint/
│   ├── _default           # Main lint task (bash)
│   ├── _default.ps1       # Main lint task (PowerShell)
│   ├── yaml               # YAML linting (bash)
│   ├── yaml.ps1           # YAML linting (PowerShell)
│   ├── moonbit            # Moonbit format check (bash)
│   └── moonbit.ps1        # Moonbit format check (PowerShell)
├── format/
│   ├── _default           # Format task (bash)
│   └── _default.ps1       # Format task (PowerShell)
├── build/
│   ├── _default           # Build all (bash)
│   ├── _default.ps1       # Build all (PowerShell)
│   ├── wasi               # WASI build (bash)
│   ├── wasi.ps1           # WASI build (PowerShell)
│   ├── browser            # Browser build (bash)
│   ├── browser.ps1        # Browser build (PowerShell)
│   ├── js                # JavaScript build (bash)
│   ├── js.ps1            # JavaScript build (PowerShell)
│   ├── native            # Native release build (bash)
│   └── native.ps1        # Native release build (PowerShell)
├── test/
│   ├── _default           # Test task (bash)
│   ├── _default.ps1       # Test task (PowerShell)
│   ├── cli                # CLI smoke tests (bash)
│   └── cli.ps1            # CLI smoke tests (PowerShell)
├── validate/
│   ├── _default           # Run all validations (bash)
│   └── _default.ps1       # Run all validations (PowerShell)
├── check                  # Run all checks (bash)
├── check.ps1              # Run all checks (PowerShell)
├── clean                  # Clean artifacts (bash)
├── clean.ps1              # Clean artifacts (PowerShell)
├── setup/
│   ├── hooks              # Setup git hooks (bash)
│   └── hooks.ps1          # Setup git hooks (PowerShell)
├── beads/
│   ├── plan               # Run bd-plan from finos/morphir (bash)
│   └── plan.ps1           # Run bd-plan from finos/morphir (PowerShell)
├── list-tasks             # List all tasks (bash)
└── list-tasks.ps1         # List all tasks (PowerShell)
```

Newer tasks are MoonBit scripts in `scripts/`, declared in `.config/mise/config.toml`. For example,
`validate:packages` runs `moonx scripts/validate-packages.mbtx`.

## Common Workflows

### First-Time Setup

```bash
# After cloning the repository
cd morphir-moonbit
mise install
```

**Note**: The `setup:hooks` task runs automatically when you enter the directory (via mise hooks), so git hooks are set up automatically. This is idempotent and can be run multiple times safely.

### Pre-Push Validation (Automatic)

The pre-push hook automatically runs before every `git push`:

1. **Linting** (`mise run lint`)
2. **Format Check** (`mise run lint:moonbit`)
3. **Validation** (`mise run validate`)

If any check fails, the push is blocked with a clear error message.

**Bypass (not recommended)**: `git push --no-verify`

### Before Committing

```bash
# Run all checks
mise run check
```

### Quick Development Cycle

```bash
# Make changes...

# Format code
mise run format

# Check formatting and lint
mise run lint

# Run tests
mise run test
```

### Build for Specific Target

```bash
# Build only for WASI
mise run build:wasi

# Build only for browser
mise run build:browser
```

### Clean and Rebuild

```bash
# Clean all build artifacts
mise run clean

# Rebuild everything
mise run build
```

## CI/CD Integration

The lint, format-check, and configuration-validation workflows delegate to mise
tasks. The build and test jobs install the MoonBit toolchain directly through
the official installer and run `moon build` / `moon test`, because the mise
`http:moonbit` tool provides the compiler only and does not bundle the
`moonbitlang/core` standard library needed to compile.

### Main CI Workflow (`.github/workflows/ci.yml`)

- **Lint Job**: Uses `mise run lint`
- **Format Check Job**: Uses `mise run lint:moonbit`
- **Build Job**: Builds release artifacts for `wasm`, `wasm-gc`, `js`, and `native`, then runs CLI smoke tests for each target. The JavaScript job also packs, installs, and runs the npm package.
- **Test Job**: Installs MoonBit and runs `moon test`
- **Validate Configuration Files Job**: Uses `mise run list-tasks` and `mise run validate` on every run
- **ci-ok Job**: Fails if any other job failed or was cancelled. It is the only required check

### Docs and site changes

The **Detect code changes** job runs first. It runs `moonx scripts/ci-changes.mbtx BASE HEAD`, which lists the
changed files and prints two flags:

- `code=false` when every changed file is documentation or project-site work: `docs/**`, `site/**`,
  `apps/morphir-site/**`, the site workflows, and every other `*.md` file except `*.mbt.md`, which holds MoonBit
  tests. The long jobs (process supervision, embedding, build, installed lifecycle, native telemetry and test) are
  then skipped, and `ci-ok` counts them as passed. Lint, format check and configuration validation always run.
- `site=true` when a site input changed: docs, site sources, the site and workbench apps, `pkgs/`, app READMEs,
  `moon.work`, `.config/mise/` or the CI and site workflows. The **Site** job then calls
  `.github/workflows/site-build.yml`, which builds, checks and tests the site. `ci-ok` covers it, in pull requests
  and in the merge queue.

A rename counts as a deletion and an addition. A manual run runs every job. A push to `main` runs every job except
the site build, because the Site workflow builds and deploys `main`. The job runs
`moonx scripts/ci-changes.mbtx --self-test` before it uses the rules.

### Merge queue

Pull requests to `main` merge through a merge queue. Click **Merge when ready** (or run
`gh pr merge <number> --squash`), and GitHub tests the PR on top of `main` and the PRs ahead of it in the queue
(the `merge_group` trigger). The PR merges only when `ci-ok` passes on that combination. When you add a job to
`ci.yml`, add it to the `needs` list of `ci-ok`.

## Adding New Tasks

To add a new task:

1. Create a standalone MoonBit script in `scripts/<name>.mbtx`.
2. Pin each import version; use `moonbitlang/async` for processes, files and stdio.
3. Declare the mise task in `.config/mise/config.toml` with `moon run scripts/<name>.mbtx` or `moonx scripts/<name>.mbtx`.
4. Update this documentation. `scripts/beads-check.mbtx` is the reference example.

Older task categories use bash and PowerShell pairs. Migrate a task to MoonBit
when changing it, as required by `.github/AGENTS.md`.

For task categories (like `lint` or `build`), the main task should be named `_default`.

## Tips

- Use `mise tasks` to list all available tasks
- Use `mise run <task> --help` for task-specific help (if implemented)
- Tasks can call other tasks using `mise run <task-name>`
- Environment variables from `.config/mise/config.toml` are available in all tasks

### IR fixtures

`mise run ir:fixtures` regenerates portable MoonBit tests from the vendored IR JSON corpus and formats the workspace. Pass `-- --morphir /path/to/morphir --morphir-elm /path/to/morphir-elm` to refresh from the pinned commits in local clones. See [the IR module](../pkgs/morphir-ir/README.md) for coverage and migration limits.

`mise run test` runs library tests on `wasm`, `wasm-gc`, `js` and `native`, followed by the CLI smoke tests.

### Workbench

`mise run setup:workbench`, `mise run build:workbench`, and `mise run test:workbench` prepare, build and verify the shared browser frontend. The JavaScript build job runs the browser workflow in Chromium. The optional Proton host has its own workspace to keep CEF out of default builds; see [desktop setup](../apps/morphir-workbench-desktop/README.md).

### E2 installed lifecycle and native telemetry

- `setup:llvm`: explicitly acquire hash-pinned compiler/core archives into a new
  `MORPHIR_LLVM_HOME` and write `MORPHIR_LLVM_PIN`; darwin/arm64 only. Default
  stable toolchain remains unchanged.
- `test:installed-lifecycle`: installed npm acceptance for
  `MORPHIR_REQUIRED_TARGETS` (default `js,wasm-gc,native`), JSON/Ion text/binary,
  debug/release, output modes, local sinks and deliberate mismatch rejection.
  Includes installed MoonBit source lowering to Ion and four Boolean rows against
  original compiler, Scheme and generated execution on each required lane. Source
  receipts and instrumentation-neutrality evidence are in `moonbit-source/`.
  Installed library receipts are in `moonbit-library/`. Naming qualification in
  `moonbit-naming/` compares 20 independently authored source rows and three
  pre-change checkpoint rows per target/mode against the original compiler,
  Scheme and generated execution. Direct consumers verify 26 rows per lane in
  readable and legacy modes, including exact target requests through a simulated
  explicit-capability host. Checks cover quiet structured warnings, both Ion
  resumptions, opaque metadata, JSON loss guards and preserved publication after
  strict or unavailable-provider failure. That lifecycle task uses simulated provider capabilities. The separate
  `test:installed-provider` task exercises real signed restoration. For focused diagnosis, run
  `node apps/morphir/scripts/test-installed-lifecycle.ts --naming-only` with the
  same environment. The required task always runs the complete lifecycle.
  Set `MOON_HOME`; LLVM additionally requires home/pin. Set
  `MORPHIR_INSTALLED_RECEIPTS` to retain evidence.
- `setup:native-otel`: build the optional host adapter from every accepted archive
  hash, outside the portable workspace. Set `MOON_HOME` and optionally
  `MORPHIR_OTEL_OUTPUT`. Requires Node and Python 3 for verified archive setup.
- `test:native-telemetry`: installed CLI OTLP HTTP/JSON capture, correlation,
  metrics, flush failure and paired overhead baseline. Requires
  `MORPHIR_OTEL_BINARY`, `MORPHIR_OTEL_PIN`, `MOON_HOME`; set
  `MORPHIR_TELEMETRY_RECEIPTS` for artifacts. Runs separately from portable tests.

These tasks use standalone MoonBit scripts. The native adapter and supported
hosts/transports are documented in [its guide](../apps/morphir-otel/README.md).

`test:installed-provider` qualifies the packed npm CLI and native executable
against a clean, explicit `MORPHIR_PROVIDER_RUST` checkout at the pinned shared
revision. Set `MOON_HOME`; optionally set `MORPHIR_PROVIDER_RECEIPTS` for binary
Ion receipts and their JSON inspection view. It provisions fresh disposable test
trust per case and verifies independent generated API calls, authentication
refusals, context boundaries, publication preservation and audit evidence.
See [provider operations](PROVIDER_OPERATIONS.md#reproduce-installed-qualification)
for setup, exact scope and remaining qualification work.

`mise run test:workbench-live-host -- --host-bin /absolute/path/to/morphir` verifies single-use launch authentication, native Gleam compilation/generation and workspace-model opening through the loopback proxy against a real Rust host. Supply a host with native Gleam available; see [Workbench verification](../apps/morphir-workbench/README.md#verification) for setup and version evidence. This optional check is separate from the default test suite.


### TypeScript qualification

`mise run check:typescript` installs every Bun dependency root from its frozen
lockfile, checks all four TypeScript projects, runs the intentional type-error
and environment-isolation gates, and emits portable runtime JavaScript. Existing
Workbench, CLI, compiler, supervision and embedding tasks use the same portable
`scripts/typescript-tooling.mbtx` entry point. Append `--ci` to setup tasks when
Chromium system dependencies must also be installed.
