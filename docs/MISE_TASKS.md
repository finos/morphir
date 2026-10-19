---
order: 35
---
# Mise Tasks Reference

This document provides a reference for all available mise tasks in the Morphir Moonbit monorepo.

## Pinned compiler and core

The compiler remains `0.10.15+943464bfa`. The repository separately pins the official
core commit `a951c067f909286603efada85c379197d589dc61`, which fixes incorrect parsing
of long decimal integers on Wasm GC. The source archive, SHA-256 and complete source
digest are recorded in [the core pin](../tools/moonbit-core-pin.json).

`mise install` and entering an activated mise shell acquire and verify the corrected
core under `.dev/toolchains/`. `MOON_CORE_OVERRIDE` selects it for ordinary `moon`
and `moonx` commands. In a shell without mise activation, use `mise exec -- moon …`.
The project selects mise's pinned compiler directory as `MOON_HOME`. Setup updates
its Mooncakes registry before compiling the portable selector, including on a fresh
installation. Windows first runs the minimal compiler/core bootstrap explicitly.
The setup does not replace the core in a shared `MOON_HOME`. An absent or altered
workspace core fails validation. The separate LLVM qualification keeps its own
compiler/core pair.

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
| `mise run workbench:artifact-source-check` | Verify the pinned upstream artifact decoder, Unicode data and licenses; also runs before Workbench builds/tests | All |
| `mise run build:native` | Build native release executables | All |

### Test Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run test` | Run tests for all packages | All |
| `mise run test:workbench` | Test the local pipeline, connected v1 protocol, loopback proxy and browser workflows | All |
| `mise run test:workbench-live-host -- --host-bin /absolute/path/to/morphir` | Test authenticated connected v1 workflows against an installed Rust UI host | All |
| `mise run test:workbench-artifacts` | Test exact generated file and ZIP bytes through a real installed SDK process and the connected UI | All |
| `mise run test:workbench-artifact-client-mck` | Qualify production artifact client traces in Bun, Node and Chromium against an explicit shared draft28 client kit | All |
| `mise run test:workbench-native-session` | Test desktop session authority and revocation without CEF | All |
| `mise run test:workbench-native-workers` | Qualify real owned native workers, exact values, bounded I/O, cancellation and shutdown without CEF | macOS/Linux |
| `mise run test:workbench-native-client-mck` | Qualify production client draft.17 scenarios in Node/Chromium with debug/release cores and independent report checks | Bun, Node, Chromium and explicit parent runner/kit |
| `mise run test:workbench-native-owner-mck` | Qualify production owner draft.18 traces in native debug/release with independent report checks | Bun and explicit parent runner/kit |
| `mise run test:workbench-native-policy-mck` | Qualify exact native checking-policy boundary draft.20 in Node/native and owner draft.22 in native debug/release with independent report checks | Explicit parent runner/kit |
| `mise run test:workbench-native-policy-client-mck` | Qualify exact native checking-policy client draft.21 in Node/Chromium with debug/release cores and independent report checks | Bun, Node, Chromium and explicit parent runner/kit |
| `mise run test:workbench-native-workspaces` | Qualify real read-only grants, traversal/link/replacement refusals, original-byte chunks and revocation without CEF | macOS/Linux |
| `mise run test:workbench-capability-policy-mck` | Opt-in exact draft.12 capability-policy qualification through the shared Rust runner in Node/Chromium/native debug/release; requires explicit runner/kit and Workbench Chromium dependencies | All |
| `mise run test:workbench-capability-execution-mck` | Opt-in exact draft.19 immutable Scheme execution traces in Node/Chromium/native debug/release; requires explicit parent runner/kit and Workbench Chromium dependencies. Actual isolated-worker acceptance is separate | All |
| `mise run test:conformance` | Compare versioned independent Ion expectations, live Scheme and explicitly pinned optional Rust; retain separate coverage receipts | All |
| `mise run test:cli` | Run CLI target and npm package smoke tests | All |
| `mise run test:moonbit-frontend` | Compare original Boolean MoonBit, Scheme and generated libraries across four targets in debug and release; requires pinned `MOON_HOME` and retains identities | All |
| `mise run test:supervision` | Verify process-tree cleanup, cancellation, deadlines and bounded diagnostics on Linux, macOS and Windows | All |
| `mise run test:embedding` | Install embedding dependencies and Chromium, then test Node, installed npm and browser hosts | All |
| `mise run test:assembly` | Generate a real multi-module Morphir library, assemble its source SDK/pinned core graph, persist binary Ion artifacts and consume them in fresh hosts | Pinned MoonBit, Bun and Node |
| `mise run test:wasm-hosts` | Opt-in MoonBit component boundary checks in Wasmtime, jco/Node and Chromium; optional pinned native Wasmoon checkout. See [scope and evidence](../tests/wasm-host/README.md) | Platforms with the pinned tool releases and Chromium |

### Utility Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run check` | Run all checks (lint + test + build) | All |
| `mise run check:core` | Verify corrected-core source bytes, provenance and exact decimal parsing | All |
| `mise run clean` | Clean build artifacts | All |
| `mise run validate` | Run all validation checks | All |
| `mise run validate:packages` | Verify package structure is valid | All |
| `mise run list-tasks` | List all available mise tasks | All |

### Setup Tasks

| Task | Description | Platform |
|------|-------------|----------|
| `mise run setup:workbench` | Install workbench npm dependencies and Chromium; `--ci` adds Linux system dependencies | All |
| `mise run setup:core` | Acquire, verify and bundle the immutable corrected core in this workspace | All |
| `mise run setup:wasm-hosts` | Install the optional component qualification dependencies and Chromium | Platforms supported by Playwright |
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
tasks. On Linux x64, Linux ARM64 and Apple Silicon, the mise `http:moonbit`
postinstall runs the official installer for the pinned release, including the
matching `moonbitlang/core` standard library and `moonx`. Local `mise install`
and CI therefore use the same complete Unix toolchain. CI's setup action also
repairs older cached installations before running `moon build` / `moon test`.
Full qualification checks uncached mise installs on all three Unix platforms.

### Main CI Workflow (`.github/workflows/ci.yml`)

- **Lint** runs YAML lint once. **Validate Configuration Files** lists the task configuration and runs `mise run validate:packages`. Local `mise run validate` still includes YAML lint.
- **TypeScript** installs frozen dependencies, checks all projects and proves invalid types fail checked builds once on Linux. `setup-typescript` accepts `build-runtimes: 'false'` for static consumers; runtime consumers retain JavaScript emission by default.
- **Build** retains Wasm, Wasm GC and JavaScript release CLI smoke tests and JavaScript Workbench checks. **Test** retains Wasm, Wasm GC, JavaScript and native workspace tests. Native qualification retains the separate native CLI artifact and MEP process checks.
- **Process supervision** retains Linux, macOS and Windows execution whenever selected. Installed and signed-provider qualification retain their platform, trust and debug/release checks.
- **ci-ok** requires every selected job to succeed and refuses any failed or cancelled dependency. A selected job that is missing or skipped fails the gate.

### Component selection

`mise run ci:changes` uses exact event revisions. The tested rules in `scripts/ci-changes.mbtx` select each job and produce the aggregate gate's required-job list from the same selection.

| Changed inputs | Independently selected baseline jobs | Other retained checks |
| --- | --- | --- |
| Workbench app, native Workbench packages and Workbench scripts | TypeScript | Build/test backends, native CLI/MEP, installed Workbench, site when its inputs change |
| Workbench sample generator or generated sample inputs | TypeScript, Elm/Scheme freshness | Workbench and backend checks |
| Host embedding directory | TypeScript, embedding including Chromium | Build/test backends, native CLI/MEP; site for documentation changes |
| MoonBit MEP directory or extension app | TypeScript | Build/test backends, native CLI/MEP |
| MoonBit generator, bindings, SDK or frontend | TypeScript, Elm/Scheme | Build/test backends, native CLI/MEP, selected transitive acceptance and site |
| Native telemetry adapter/scripts | TypeScript | Build/test backends, native CLI/MEP, telemetry and site when affected |
| Shared IR, engine, host, tooling, locks or unknown code paths | All baseline jobs | Conservative acceptance dependency rules |
| Documentation or site only | TypeScript when a site input changes | Site, lint, format and package validation |

Shared inputs and combinations union their dependencies. Renames count both the old and new paths, including code moved to documentation. A manual run selects everything. Main pushes use a two-commit diff and PR/merge-queue events use the merge base. An unreachable push base selects everything. The separate Site workflow owns main deployment.

CI policy, shared setup, workspace and mise toolchain changes still exercise full qualification. The known site workflows exercise the site build without native qualification. Further workflow narrowing requires a tested mapping. Scheduled full runs, uncached Linux x64/ARM64 and macOS toolchain installs, installed OS matrices and exact-candidate release qualification remain in `qualification.yml`.

### CI measurements and rollback

Run `mise run ci:measure -- RUN_ID --logs > .dev/ci-measurement.json` on a completed run. It uses authenticated `gh`, paginates all jobs in the exact run attempt, and records per-job queue seconds, execution seconds, per-OS runner occupancy, individual step costs and cache log observations. Missing logs mean unknown cache state. GitHub retains successful jobs on retries and resets their creation timestamps. The command marks those results as retained, leaves their original queue delay unknown, and excludes them from the current attempt's execution totals. Effective totals include retained results for workload comparisons. Save each attempt before retrying and sum current-attempt execution totals to measure cumulative runner cost. These seconds are unweighted and are not billed minutes. Queue sums overlap, and run elapsed time includes dependency waits. The API does not expose a complete dependency DAG; use the final jobs and workflow dependencies to inspect the critical path.

Compare the same workload and dependency locks, report warm/cold/unknown cache observations, and distinguish elapsed time from runner occupancy. Do not turn one pair of runs into a general percentage claim. Optimization evidence and the HTML coverage report are stored in beads epic `morphir-ukvn.5.65`.

Bun/package download caches and additional JavaScript artifact transfers require a measured benefit. Keep frozen installs on misses. Never cache trust decisions, signing state, mutable fixtures or qualification receipts. Existing native artifact admission verifies source, run, target, compiler/core and dependency identity; absent or incompatible artifacts fail closed. The scheduled installation checks remain uncached.

For a material regression, revert the affected optimization commit. Restore broad baseline job conditions and their required-job selection together, or revert the complete selector slice. Keep the TypeScript job ID in `ci-ok`; restoring its OS matrix does not require a protection change. Keep the runtime-setup default enabled. Reverting these optimizations must preserve the qualification workflow and exact-candidate gate.

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
