# Proposal

## Why

The Morphir CLI and Workbench need application services that are not part of Morphir itself: layered
configuration, logging, a host that starts and stops work and maps signals to exit codes, message dispatch between
the parts of an application, and notebook formats. Today each is built by hand in this repository:

- Configuration: `pkgs/morphir-engine/config`, `pkgs/morphir-engine/workspace` and
  `pkgs/morphir-host/configuration.mbt` hold a TOML loader, merge, provenance and file discovery of our own.
- Logging: there is no logger with levels. `--log` writes typed telemetry observations to `.morphir/logs`, and other
  diagnostics go to standard error by direct writes.
- Lifecycle: `apps/morphir/main.mbt` maps a `"Cancelled"` error message to exit code 130 by a string compare. Each
  command starts and stops SIGINT handling itself. SIGTERM is not handled.
- Dispatch: the CLI selects a command through a chain of string compares on the command name. The native Workbench
  service and the engine Workbench boundary each route requests by an `op` string.
- Notebooks: there is no notebook format. Scheme worksheets can be evaluated, but they cannot be shared as notebooks.

`moonrockz/moon-lander` is an application framework for MoonBit, like .NET hosting and configuration, that supplies
all of these as separate modules: `moon-lander-config`, `moon-lander-logging`, `moon-lander-hosting`,
`moon-lander-mediator` and `notebooks`. It names finos/morphir-moonbit as its first consumer. If we adopt it, we stop
maintaining these services ourselves, and the CLI and Workbench get new framework features (host lifecycle events,
rolling log files, configuration environments and workspaces) as Moon-Lander releases them.

## What Changes

- Adopt the Moon-Lander modules as dependencies of the CLI (`apps/morphir`), the Workbench
  (`apps/morphir-workbench`, `apps/morphir-workbench-desktop`) and the packages that serve them. Take each module from
  mooncakes.io at an exact pinned version, like the other `moonrockz` dependencies. Moon-Lander releases up to `0.5.0`
  published only `notebooks` and `openrpc`; release `0.6.0` published the framework modules and is the exact version
  used for the initial dependency phase. The migration now pins published `0.8.0`, which retains the approved
  configuration, host-control, diagnostic-object and lossless-DIB additions and the logging bridge fixes for
  parent-owned signals and ordered hosted-session draining, plus four-target async mediator composition and
  foreign-callback-safe polling of the same hosted stop state. Its completion callback reports the real outcome and
  selected exit code after finalization, including stops before the first service hook. Each migration group starts when its
  module is on the registry.
- Configuration: load Morphir configuration through `moon-lander-config` and its conventions, with the TOML, JSON
  and JSON5 parsers, and YAML. Keep the current TOML file names, locations, environment-variable mapping and provenance. Add an
  explicit discovery boundary for isolated hosts. Retire the private loader and merge.
- Configuration in JSON: discover `morphir.json` and `morphir.json5` as workspace configuration that `morphir.toml`
  overrides, instead of ignoring `morphir.json` when `morphir.toml` exists. Both are parsed as JSON5. A JSON file takes the canonical keys and
  the morphir-elm manifest fields (`name`, `sourceDirectory`, `exposedModules`).
- Configuration in YAML: read `morphir.yaml` and `morphir.yml` instead of refusing them. In one directory the format
  layers are JSON, then YAML, then TOML, and a later layer wins; two files of one layer are an ambiguity error. YAML
  beside TOML is allowed but gives a warning. Members use the same rules as the workspace root.
- `morphir-workspace.json` becomes a JSON configuration file, below `morphir.json` in the JSON layer.
- Configuration profiles: enable the policy published in Moon-Lander 0.6.0. Add repeatable `--profiles`,
  `--no-profiles`, `MORPHIR_PROFILES`, base-file defaults/includes/groups, and profile files between member
  configuration and user overrides. Preserve profile control origins through the JSON/YAML/TOML layers.
  The existing frontend `--profile` keeps its meaning.
- Configuration warnings have codes that the host can suppress with `--suppress-warning`,
  `MORPHIR_DIAGNOSTICS__SUPPRESS` or `diagnostics.suppress` in the system or global user file.
- TOML stays the default format: commands that create or change configuration write `morphir.toml` only. A change
  to a workspace with only JSON or YAML files creates `morphir.toml` beside them, with the full value of each key it
  writes. Removing a root project declared in a lower JSON or YAML primary refuses without writing files and names
  the declaring file; an empty TOML table cannot delete that lower declaration.
- `--config <path>` selects a TOML, YAML, JSON or JSON5 configuration file whose values override `morphir.toml`.
- **BREAKING**: the Scheme configuration script option `--config` becomes `--config-script`. A `.scm` path given to
  `--config` fails with a message that names the new option.
- Logging: add leveled, structured diagnostic logging through `moon-lander-logging`, written to standard error and
  optionally to rolling files under `.morphir/logs/`. JSON Lines uses a named `properties` object: the last occurrence
  wins, and `duplicateProperties` retains every value of repeated names in order. Use the upstream opt-in format
  once published. Keep the `--log` telemetry observations and their formats as they are. Log output never goes to
  standard output.
- Lifecycle: run the CLI commands through `moon-lander-hosting`, with one cancellation path for SIGINT and SIGTERM,
  stop hooks that run in reverse order, logs that are drained before exit, and the current exit codes kept. The
  desktop Workbench runs its native services as hosted services under the Proton event loop.
- Dispatch: route CLI commands and Workbench operations through typed `moon-lander-mediator` senders, with shared
  middleware for cancellation, timing and logging, in place of string compares. This is internal; command names,
  operation names and results do not change.
- Notebooks: add import and export between Scheme worksheets and Jupyter (`.ipynb`) and .NET Interactive (`.dib`)
  notebooks through `moonrockz/notebooks`, in the CLI and in the Workbench. Jupyter exports can preserve evaluation
  results. DIB exports preserve source only; `--evaluate` with DIB is a usage error, because DIB stores no outputs.

## Capabilities

### New Capabilities

- `application/configuration`: how the CLI and Workbench find, merge and report Morphir configuration, including
  precedence, provenance, configuration profiles, environment variables and isolated discovery.
- `application/lifecycle`: how a CLI or Workbench run starts, is cancelled or stopped, cleans up, and chooses its exit
  code.
- `application/logging`: leveled diagnostic logging, its settings, its outputs and its separation from command
  results.
- `worksheets/notebook-interchange`: converting Scheme worksheets to and from Jupyter and DIB notebooks, with their
  evaluation results.

### Modified Capabilities

None. No capability has a main spec in `openspec/specs/` yet.

## Decisions

The maintainer confirmed these on 2026-10-28:

- The framework modules are consumed from mooncakes.io. We coordinate with the Moon-Lander project to publish them;
  no git, path or vendored copy is used in the meantime.
- One change covers the adoption and a phased migration, with one task group per capability.
- Worksheets become importable and exportable as notebooks.
- TOML is the default and the only written format. A write to a workspace with only JSON or YAML files adds
  `morphir.toml` beside them.
- YAML configuration is enabled, from `.yaml` and `.yml` files. `morphir.toml` supersedes YAML as it supersedes JSON:
  JSON, then YAML, then TOML, where a later layer wins.
- JSON and JSON5 configuration are enabled. `morphir.json` is processed as configuration below `morphir.toml`;
  `morphir.toml` overrides its values unless `--config` selects the JSON file, which then overrides `morphir.toml`.
  JSON files take canonical keys and the morphir-elm manifest fields; `morphir.json5` is discovered like
  `morphir.json`.
- `--config` selects a configuration file. The Scheme script option is renamed to `--config-script`.
- Configuration profiles are enabled in this release, as approved on 2026-10-28. They use Moon-Lander's
  activation and group rules, remain separate from frontend profiles, and do not enable environment files or
  local overrides.
- Diagnostic JSON properties are nested under `properties`, as approved on 2026-10-28. The last occurrence of a
  repeated name wins; optional `duplicateProperties` preserves all occurrences, including the winner, in original
  per-name order. Values keep their JSON types, and records without repeated names omit `duplicateProperties`.
- On 2026-10-30 the maintainer approved refusing root-project removal when a lower JSON or YAML primary declares
  the project. The refusal identifies that file and leaves configuration and source files unchanged.
- On 2026-10-30 the maintainer approved releasing the MoonBit discovery controls independently of the separate
  Rust CLI itest driver. `morphir-o6vm.10` remains open for that companion work; its completion is not a prerequisite
  for this release. All MoonBit isolation and boundary scenarios remain required here.
- On 2026-10-30 the maintainer approved an additive `utc_milliseconds` operation in the GC host adapter for UTC
  diagnostic logging. It uses the existing response envelope. Missing or invalid clocks fail clearly when logging
  is enabled; help and logging-off runs do not require the clock. Existing MEP and worker payloads remain unchanged.
- On 2026-10-30 the maintainer approved GC cancel-file registration so host-owned stdin waits can observe the
  selected path. The registration is cleared after the run, including startup failures, and the existing host stop
  state retains an observed request after the marker disappears. Existing worker messages and shared buffers stay unchanged.
- On 2026-10-30 the maintainer confirmed that this release includes a qualified Moonx entry. Its compiler/runtime,
  filesystem, JSON, failure and help/version qualification is part of release delivery; a help-only stub or silent
  deferral does not satisfy that scope.
- On 2026-10-30 the maintainer approved a Node-backed Moonx entry with an explicit Node prerequisite. The entry
  reuses the packaged Node CLI without a separate npm installation and preserves its bounded filesystem operations,
  publication guarantees, opaque argument arrays, byte streams, JSON schemas and cancellation behavior. Release
  qualification covers the supported minimum and pinned MoonBit runtimes, plus the actual archive and public registry.
- On 2026-10-30 the maintainer approved keeping native installation at `moon install finos/morphir@VERSION --bin DEST`
  and selecting the portable entry with `moonx finos/morphir/moonx@VERSION`. The `moonx` entry is a subpackage of
  the same published CLI module. Its Node prerequisite does not apply to native built-in commands. The maintainer
  also approved an optional upstream Moon-Lander compatibility module for correct signal forwarding without waiting
  for a `moonbitlang/async` release, with frozen-source provenance, retained tests and public-consumer qualification.
  The upstream API request is tracked separately in `moonbitlang/async#706`.
- On 2026-10-30 the maintainer approved a Windows-only Moonx signal limitation. With the supported stock
  Moonrun runtimes, Ctrl+C reaches the Node child as Ctrl+Break: the child reports the delivered Quit with 131,
  while the launcher retains its actual Windows cancellation status. This release documents and qualifies that
  behavior without inferring or relabeling the original signal. POSIX Moonx retains original SIGINT/SIGTERM
  delivery and 130/143 results. Finite results, owned-child cleanup, forced reaping and byte transport remain
  required on Windows. Native and npm entry contracts are unchanged. The stock runtime gap is tracked in
  `moonbitlang/moon#2419`; its fix is not a prerequisite for this release.
- The work lands in as few pull requests as needed: one pull request for the migration here, with a separate pull
  request only for a group that is blocked while the rest is ready.

## Later work

- Protocol definitions for MEP and the Workbench protocols in Smithy, through `moonrockz/smithy`, building on the
  MEP Smithy model in `tests/fixtures/mep-smithy/`. `moonrockz/openrpc` is not used for these protocols.
- Configuration inspection commands (`config get/show/path`, `morphir-ukvn.5.64.16`) built on the new loader.
- Notebook cells in other languages than Scheme, and running notebooks as test scenarios.

## Beads

- **Tracked by**: `morphir-ukvn.5.99` (epic, child of Track 5 `morphir-ukvn.5`)
- **Related**:
  - `morphir-ukvn.5.64` (the primary CLI and Workbench campaign that this change serves)
  - `morphir-ukvn.5.64.16` (configuration inspection; builds on the loader adopted here)
  - `morphir-o6vm.10` (separate Rust CLI itest-driver isolation companion; remains open and does not gate this release)
  - `morphir-o6vm.11` (shared notebook profile; the notebook model chosen here must stay compatible with it)
  - `morphir-lnr` (old request for structured CLI logging with levels; superseded by the logging capability)

## Impact

- New dependencies: `moonrockz/moon-lander-core`, `moon-lander-config`, `moon-lander-logging`,
  `moon-lander-logging-hosting-async`, `moon-lander-hosting`, `moon-lander-mediator` and `moonrockz/notebooks`, pinned
  in the `moon.mod` files of the apps and packages that use them.
- Code that is replaced: `pkgs/morphir-engine/config` (load and merge), the discovery parts of
  `pkgs/morphir-engine/workspace` and `pkgs/morphir-host/configuration.mbt`, the error-to-exit-code mapping in
  `apps/morphir/main.mbt`, the per-command interruption calls, and the `op` routing in
  `pkgs/morphir-workbench-native/service.mbt` and `pkgs/morphir-engine/execution/workbench/boundary.mbt`.
- Code that is kept: `pkgs/morphir-toml-edit` (format-preserving edits), the telemetry observations and
  `apps/morphir-otel`, MEP framing, and the platform I/O of `pkgs/morphir-host`.
- Targets: the CLI builds for native, js, wasm (WASI) and wasm-gc. Moon-Lander hosting runs on native and js; on wasm
  and wasm-gc the CLI keeps a synchronous path over the pure configuration core.
- New CLI surface: `--suppress-warning <code>`, `--config <file>`, `--config-script <file>` (renamed from `--config`), `--log-level`, and
  `notebook export` and `notebook import`, each with `--json` output.
- Documentation: `apps/morphir/README.md`, the Workbench README, `CONTEXT.md` terms for the new concepts, and a new ADR
  that records the adoption.
