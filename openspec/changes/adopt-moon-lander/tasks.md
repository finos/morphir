# Tasks

## 1. Publish the Moon-Lander framework modules (morphir-ukvn.5.99.1)

- [ ] 1.1 Confirm with the Moon-Lander release that `moon-lander-core`, `moon-lander-logging`, `moon-lander-config`,
  `moon-lander-mediator`, `moon-lander-logging-hosting-async`, `moon-lander-hosting` and `moon-lander` are on
  mooncakes.io at one version; verify each resolves with `moon add moonrockz/<module>@<version>` in a scratch module
  outside this checkout
- [ ] 1.2 Record the published version and the release URL in design.html (open question 1) and remove that open
  question; verify with `openspec validate adopt-moon-lander --strict`

## 2. Add dependencies and record the adoption (morphir-ukvn.5.99.2)

- [ ] 2.1 Add the pure modules at the exact version to the `moon.mod` of `pkgs/morphir-engine` and the host modules
  to `apps/morphir`, `apps/morphir-workbench`, `apps/morphir-workbench-desktop`, `pkgs/morphir-host` and
  `pkgs/morphir-workbench-native`, following DEP-2; verify `mise run check` (or the repository's full gate) passes
  on native, js, wasm and wasm-gc with no new warnings
- [ ] 2.2 Group the Moon-Lander imports in one Renovate rule in `renovate.json`; verify with the Renovate config
  validator
- [ ] 2.3 Add a check that fails when an engine package imports a host module (DEP-2), wired into the existing lint
  task; verify it fails on a deliberate bad import and passes on the tree
- [ ] 2.4 Run a build-master review of the native release jobs for `moonbitlang/async` modules on Darwin and Windows;
  verify the review result is in the pull request
- [ ] 2.5 Write `docs/adr/0004-adopt-moon-lander.md` and add the CONTEXT.md terms from DOC-1; verify the docs site
  build and link check pass

## 3. Load configuration through Moon-Lander (morphir-ukvn.5.99.3)

- [ ] 3.1 Build a parity corpus from every `morphir*.toml` in tests and fixtures, and a test that compares effective
  values and origins from the old loader and the Moon-Lander loader on all four targets; verify it runs and reports
  each difference
- [ ] 3.2 Load through `moon-lander-config` conventions for `morphir` (CFG-1), reading `.yaml` and `.yml` primary
  and user files as a YAML layer below TOML (CFG-3, CFG-4), with the `config.yaml_beside_toml` warning and the
  host-only suppression list (`--suppress-warning`, `MORPHIR_DIAGNOSTICS__SUPPRESS`, `diagnostics.suppress`), keeping the `Unsupported configuration format` error for other extensions and
  the `Ambiguous configuration` error; verify the parity corpus passes for TOML files, and the precedence, discovery,
  ambiguity, YAML, YAML-beside-TOML warning, suppression, format and environment scenarios of the `application/configuration` spec pass as tests
- [ ] 3.3 Discover `morphir-workspace.json`, `morphir.json` and `morphir.json5` as a JSON layer below the YAML layer,
  with ambiguity checked per layer, the morphir-elm field mapping and the `config.json_keys_below_toml` warning
  (CFG-4); link the TOML, YAML and JSON/JSON5 parsers and parse both `.json` and `.json5` as JSON5 (CFG-3); verify the
  format-layer, manifest-field, `morphir-workspace.json`, JSON5, JSON5-syntax-in-`.json` and invalid-JSON scenarios of
  the `application/configuration` spec as tests, and that every `morphir.json` fixture gives the same project values
  as the current `legacy` reader
- [ ] 3.4 Add `--config <path>` for TOML, YAML, JSON and JSON5 files as a layer above the TOML layer, and rename the Scheme
  script option to `--config-script` with a usage error for a `.scm` path given to `--config`; update the uses in
  `apps/morphir/main.mbt`, `apps/morphir/arguments_wbtest.mbt`, `apps/morphir/scripts/test.ts` and
  `apps/morphir/README.md`; verify the selected-file and script-option scenarios with argv tests
- [ ] 3.5 Keep `workspace init`, `project add` and `project remove` writing TOML only (CFG-5): create `morphir.toml`
  beside JSON or YAML primary files with the full value of each written key, and extend `ensure_new_config` to every
  primary name; verify the written-format and JSON/YAML-workspace scenarios with scaffold tests and argv tests
- [ ] 3.6 Rebuild the workspace member walk in `pkgs/morphir-engine/workspace` on Moon-Lander values (CFG-2), with
  the same format layers, ambiguity rule and warnings for each member; verify the member-format scenarios and
  the existing workspace and member tests pass unchanged
- [ ] 3.7 Add the explicit discovery boundary and isolation to the CLI and the itest driver (`morphir-o6vm.10`);
  verify the isolated-discovery scenarios as tests, including a project under a temporary root with a parent
  `morphir.toml`
- [ ] 3.8 Use the same loader in the Workbench settings (`apps/morphir-workbench/workspace-projects/settings.mbt`) and
  the engine protocol overlay; verify the Workbench settings tests and the native/wasm-gc agreement scenario
- [ ] 3.9 Remove the old load, merge and environment code from `pkgs/morphir-engine/config` and the discovery paths
  from `pkgs/morphir-host/configuration.mbt`; verify the full gate and record the binary size of each CLI artifact
  before and after in the pull request
- [ ] 3.10 Update the configuration section of `apps/morphir/README.md` with JSON configuration, `--config`, the
  breaking `--config-script` rename and how to keep the old result for a workspace with both files; verify every
  documented command runs as written

## 4. Add leveled diagnostic logging (morphir-ukvn.5.99.4)

- [ ] 4.1 Add the `logging.level` key, `MORPHIR_LOGGING__LEVEL` and `--log-level` with the `warn` default and usage
  error for an unknown level; verify the level and setting scenarios of the `application/logging` spec as tests
- [ ] 4.2 Build the run's Logger (LOG-1) with a standard-error console sink on native and js and a text Logger on wasm
  and wasm-gc; verify with an argv test that `--json --log-level trace` keeps standard output a single JSON document
- [ ] 4.3 Add rolling files with the stem `morphir-diagnostics` under `.morphir/logs/` (`logging.file.*` keys); verify
  the file scenario and a retention test that leaves telemetry files in place
- [ ] 4.4 Log configuration loading, command start and end, and child process starts through the Logger, replacing
  ad hoc `@platform.stderr` diagnostics where they are not command output; verify the structured-record scenario
- [ ] 4.5 Prove that `--log`, `--log-file`, `--log-format` and `--otel-*` output is unchanged; verify the telemetry
  scenario with a byte comparison of Ion binary output with and without `--log-level`
- [ ] 4.6 Document logging in `apps/morphir/README.md`, including output channels; verify the documented commands

## 5. Dispatch through the mediator (morphir-ukvn.5.99.5)

- [ ] 5.1 Define a request type and sender per CLI command and the shared middleware (cancellation, timing and log
  scope, failure mapping) (MED-1); replace the string-compare chain in `apps/morphir/main.mbt`; verify every existing
  CLI test and argv test passes unchanged
- [ ] 5.2 Route `pkgs/morphir-engine/execution/workbench/boundary.mbt` through the synchronous mediator; verify the
  boundary tests and an unknown `op` refusal test give the same results as before
- [ ] 5.3 Route `pkgs/morphir-workbench-native/service.mbt` through the async mediator; verify the native service
  tests and the bridge acceptance suite pass unchanged

## 6. Run the CLI through the Moon-Lander host (morphir-ukvn.5.99.6)

- [ ] 6.1 Build the host with `@lander.cli("morphir", args)` and run it with `@console.run` and the logging bridge on
  native and js, and with `run_embedded` on wasm and wasm-gc (HOST-1); verify `--help` and a self-test on all four
  targets
- [ ] 6.2 Map failures to Morphir exit codes with `set_exit_code`, and cancellation to 130 and SIGTERM to 143 through
  `StopReason`; remove the `"Cancelled"` string compare; verify the exit-code scenarios of the `application/lifecycle`
  spec with argv tests that send real signals on native
- [ ] 6.3 Make the cancel file a host stop request and register the telemetry session and log session as hosted
  services; replace per-command `interruption_start`/`interruption_stop`; verify the cancel-file, child-process and
  cleanup-order scenarios
- [ ] 6.4 Keep JSON failure output on standard output and the WASI worksheet refusal; verify the JSON failure and
  hosts-without-signals scenarios
- [ ] 6.5 File each missing hosting feature as a Moon-Lander issue and link it in the pull request; verify none is
  worked around locally
- [ ] 6.6 Document exit codes and signals in `apps/morphir/README.md`; verify the documented table against the tests

## 7. Host the desktop Workbench services (morphir-ukvn.5.99.7)

- [ ] 7.1 Register the native Workbench services as hosted services, start the host when Proton starts and stop it
  with the `Embedder` reason from `on_shutdown` (HOST-2); verify the desktop shutdown scenario with a test that quits
  during a host execution
- [ ] 7.2 Use the configuration loader and the Logger from groups 3 and 4 in the desktop app; verify the desktop
  smoke test and that logs reach standard error
- [ ] 7.3 Document the desktop lifecycle in the Workbench README; verify the documented behavior with the smoke test

## 8. Import and export worksheets as notebooks (morphir-ukvn.5.99.8)

- [ ] 8.1 Add `moonrockz/notebooks` at the current Moon-Lander version and the pure package
  `pkgs/morphir-engine/worksheet/notebook` with the form, comment and observation mapping (NB-1); verify unit tests
  for forms, comment blocks, outputs and the round-trip scenario on all four targets
- [ ] 8.2 Add `morphir notebook export` (`--format`, `-o`, `--evaluate`) and `morphir notebook import` with `--json`
  results in the `morphir/command-result` envelope; verify every scenario of the `worksheets/notebook-interchange`
  spec with argv tests, including the invalid-notebook case that writes no file
- [ ] 8.3 Check the exported `.ipynb` with an independent nbformat validator in the test tooling; verify the
  validator accepts every exported fixture
- [ ] 8.4 Add Workbench export and open actions for Jupyter and DIB using the same package; verify the Workbench
  scenario in a browser test that compares the download with CLI output
- [ ] 8.5 Document notebooks in `apps/morphir/README.md` and the Workbench README, and record the profile name for
  `morphir-o6vm.11` as a bead comment; verify the documented commands

## 9. Integration checks across hosts (morphir-ukvn.5.99.9)

- [ ] 9.1 Run the full gate, the itest suites and the Workbench browser suites on all supported targets; verify all
  pass and record the results in the epic bead
- [ ] 9.2 Compare CLI artifact sizes and start-up time with the numbers before group 2; verify the comparison is in
  the epic bead and any growth above 10 percent has an issue

## Workflow follow-up

- Archive the change after review, following the archive guidance in `openspec/config.yaml`.
- Close `morphir-lnr` as superseded by the logging capability, with a link to this change.
