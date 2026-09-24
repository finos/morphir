# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- The draft Ion IR codec covers v3 dependency specifications and every v4 distribution kind and node the draft spells: specs and application distributions with entry points, every value expression and pattern, custom and derived types, and external and incomplete bodies (finos/morphir-rust#248). v4 attributes, Morphir annotations and document literals are refused rather than dropped. `morphir ir migrate --target-version v3 --output-layout vfs --output-format ion` writes a v3 Ion tree, and `generate -i` reads one; the JSON and YAML trees stay v4 only ([#970](https://github.com/finos/morphir/issues/970)). `ionVersion` stays `0.1.0-draft.1` ([#946](https://github.com/finos/morphir/issues/946)).

## [0.4.0-beta.6] - 2026-09-24

### Added
- Early-access local Library authoring and publication (#945): the CLI compiles a Gleam model into a verified dependency-free classic V4 Library, signs its release with an explicit local Ed25519 seed, and publishes it to an explicitly initialized local registry. Publication requires caller-signed TUF metadata and an exact predecessor, and runs on macOS only; other platforms await qualification. A separate project can initialize public trust, resolve, restore, generate and compile the published Library without a signing key. See the `hello` example in `examples/package/local-library-publish`.
- The CLI identifies itself to extensions with `"kind": "cli"` in `initialize.host`, on every initialization path, independently of its name label (#954, finos/morphir-rust#235).
- Draft Amazon Ion IR format, `ionVersion` `0.1.0-draft.1`, for IR v3 and v4 ([#946](https://github.com/finos/morphir/issues/946)). `ir.format = "ion"` writes `morphir-ir.ion`, one datagram of annotated elements with S-expression values. With `ir.layout = "document-tree"` it writes a tree whose root is `manifest.ion`. Each tree file holds the same elements, and the path supplies the package, module and name. The draft spelling can still change before a release. The compatibility kit's profiles stay `json` and `yaml`. The design is in `docs/design/draft/ir/ion.md` and the kb note `morphir-ir/ion-ir-format.md`.

### Changed
- The CLI sends every frontend the current compile envelope, `sources: { root, documents }`. Process and WASM frontends no longer receive the legacy top-level `documents` with `options.sourceRootUri`, and `compile_wire_request` is gone. A process or WASM frontend released before `sources` existed no longer compiles with this CLI: that is `extension/python/v0.2.0` and earlier, `extension/rust/v0.1.0`, and `morphir-scala-elm` `v0.5.0-M08` and earlier. Use `extension/python/v0.3.0`, `extension/rust/v0.2.0`, `morphir-scala-elm` `v0.5.0-M09` and the Elm extension `v0.3.1` or later (#921).
- The published extension pins move to frontends that accept the `sources` compile envelope as well as the legacy top-level `documents`: `extension/python/v0.3.0`, `extension/rust/v0.2.0` and `morphir-scala-elm` `v0.5.0-M09`. With the Elm extension `v0.3.1`, which already reads both, every pinned frontend can take `sources`, so the CLI can stop sending the legacy envelope (#921). `INSTALLING.md` names the Python `v0.3.0` bundle.

## [0.4.0-beta.5] - 2026-09-23

### Added
- `morphir extension repository publish --bundle` accepts a version-2 process bundle: `release.json`, one raw executable per platform and each one's `.sha256` file. Publish checks every digest and statement before running anything, runs the artifact for this platform to check its capabilities, and writes index records that keep each declared statement and record whether it was probed. Archives, mixed WASM and process bundles, and platform ABIs the index cannot represent are refused (kb `morphir-extensions` decision 0003, #921).
- `morphir extension install` probes the selected process artifact before it commits: it runs `describe`, or a session when the extension does not implement it, and refuses the install when the answer disagrees with the declared statement, leaving nothing behind. `--no-probe` skips the probe. Install and `extension list` show the capability kinds and whether the statement was probed (kb `morphir-extensions` decision 0003, #921). An install from a version-1 index record keeps the version-1 catalog shape, so an older CLI can still read a shared Morphir home.

### Changed
- Extension formats follow the capability-statement compatibility rules (kb `morphir-extensions` decision 0004): the bundle descriptor, index record and installed catalog ignore unknown members unless they are listed as critical, carry SemVer schema versions, and old records still load. An extension's `requires.host` is checked against this CLI's version. The `morphir-rust` pin moves to `689df2a` (finos/morphir-rust#223, #224, #225).
- Every Elm provider reads an explicit package name in a selection of files with both `.` and `/` as segment separators, and reports one normal form: `--package-name My.Package`, or a borrowed manifest named `Documentation.Decoration`, now works with every Elm provider and names `my/package` or `documentation/decoration`. The IR package path does not change. The pins move to `morphir-rust` `adf03d8`, `extension/elm/v0.3.1` and `morphir-scala-elm` `v0.5.0-M08` (kb `morphir-extensions` decision 0005).
- The MEP draft assigns `-32014` (not initialized) to a request that is not allowed before `morphir.initialize` or after shutdown, and a statement built from a `describe` fallback session holds only what the session reports (kb decision 0006).

## [0.4.0-beta.4] - 2026-09-23

### Added
- The native package MVP profile runs 70 required local Library cases across fresh trust, metadata refresh, full-lock resolve and restore, scoped update, and refusal paths. `morphir mck package mvp-run` writes one versioned prerelease JSON report; `mvp-report check` independently verifies the complete inventory, and `mvp-report render` writes a standalone offline HTML view.
- Published CLI acceptance on all six native targets runs the downloaded beta.4 binary against those 70 cases and both signed local Library examples under operating-system network denial. It retains the JSON/HTML reports, example logs, and negative checking evidence alongside the unchanged 80 integrity and 78 resolution cases.
- `morphir compile --input` accepts files from any language whose provider declares their suffix, and repeats: several files from one directory compile together. The provider synthesizes the project through workspace discovery, naming the package and exposing every selected module; `--package-name` is required for more than one file (#917).
- `morphir generate --from-partial-compile` consumes a compile of selected files. Such a compile is marked in its task record, and an implicit `generate` refuses it otherwise, because its IR need not match the project's declared exposure.

### Changed
- There is one compile route. The CLI's single-file Elm route, its Elm module-header scanner and its `morphir-<language>` default are gone: the language comes from `--language`, the configuration or the suffix a provider declares, and every restriction comes from a declared capability, with refusals naming the provider. A compile of selected files negotiates the IR version with its provider, so `--ir-version 4` now works with a provider that serves it; without the flag it keeps the oldest release the provider serves. A provider that does not declare `frontend.multiDocument` is refused a multi-file selection before it is invoked; a project compile still submits its whole source set.
- `morphir gleam roundtrip` with only files as input and no `--config` or `--project` is refused before compiling, because its generate half needs a project.
- The published Elm extension pin moves to `extension/elm/v0.3.0`, which serves workspace discovery.
- The published `morphir-scala-elm` pin moves to `v0.5.0-M07`, which serves workspace discovery, so its CI check compiles a single file again (finos/morphir-scala#1070).
- Package integrity and resolution CI now use the native Morphir CLI against independent TypeScript and Rust adapters. TypeScript adopts qualified beta.3 for its installed-adapter checks; the replaced package runner, runner APIs and temporary parity tooling are retired. Independent package implementations, draft.3 helpers and frozen acceptance evidence remain.

## [0.4.0-beta.3] - 2026-09-21

### Added
- `morphir mck package run --kit <path> --adapter <exe>` executes the existing package integrity and deterministic resolution contracts. It preserves all 80 draft.1 and 78 draft.2 cases, corpus hashes and draft reports. Both independent adapters pass with zero required skips. Package managed-kit acquisition and HTML rendering are not part of this command.
- Packaged and published CLI acceptance now includes both package suites through fixed adapter recordings, complete ordered report comparisons and explicit copied package inputs. The existing six-target published-release workflow runs these checks with operating-system network denial. Live adapter parity remains a separate interoperability gate.
- The global `--no-banner` flag, `MORPHIR_NO_BANNER` environment variable and `[cli] banner = false` configuration suppress the help/version banner. Precedence is flag, environment, then configuration.

### Changed
- IR consumers now use the native CLI, and the replaced TypeScript IR runner APIs and future runner binaries have been retired. Adapters, codec tests and historical assets remain available. Package runner retirement follows qualified release adoption under [#852](https://github.com/finos/morphir/issues/852); the existing TypeScript package gates remain available during that migration.
- Project compilation resolves configuration once during session startup and passes it to the compiler, preserving explicit project/config selection and single-file compilation rules.

### Fixed
- MCK adapter deadlines cover blocked stdin writes and shutdown as well as response reads, preventing a non-reading adapter from hanging the runner.
- Published-release qualification accepts the CLI version banner and retains Linux evidence after network-isolated execution. Windows release checkouts enable long paths before fetching fixtures.
- `morphir-opa` (and its `regorus` dependency) is now behind a `rego` Cargo feature on `morphir`, enabled by default. A Windows contributor whose Visual Studio install lacks the "MSVC v143 - VS 2022 C++ x64/x86 Spectre-mitigated libs (Latest)" component can build, test, and lint with `cargo build --no-default-features -p morphir` instead of hitting a `msvc_spectre_libs` build-script panic; the only loss is `morphir eval`'s Rego provider and itest's Rego-backed assertions. Documented in [INSTALLING.md](INSTALLING.md) and [DEVELOPING.md](DEVELOPING.md) (#886)

## [0.4.0-beta.2] - 2026-09-20

### Added
- Native IR compatibility tooling through `morphir mck`, backed by the reusable `morphir-mck` library. `check`, `coverage`, and `schema check` validate cases, vocabulary coverage, schemas, JSON and protocol examples, and accepted or rejected IR fences offline without Node, Bun, Git, or external schema validators.
- `morphir mck run --adapter <exe>` drives an explicit implementation adapter against the embedded kit, a checkout, or a verified vendored snapshot. It supports case filters, strict skip handling, bounded adapter sessions, and process-tree cleanup on failure, timeout, or cancellation.
- Consolidated `2.0.0-draft.1` JSON reports include driver, kit, and adapter provenance with the case results. `morphir mck report check` validates a report against the selected kit and an allowed-failing baseline; `report render --format html` produces a self-contained offline HTML view. The report contract remains a draft.
- `morphir mck kit status`, `kit vendor`, and `kit update` identify and manage pinned kit snapshots. Embedded and local sources work offline; GitHub acquisition requires a full commit revision. The `mck-kit.lock.json` manifest records source identity, per-file SHA-256 hashes and kit digests. Managed snapshots reject missing, altered, or extra files; updates stage and verify replacement contents before installation.
- Release archives for all six supported targets must pass the native MCK smoke gate before publication. The gate extracts the packaged CLI, uses a fresh directory and empty tool-runtime path, and exercises vendoring, authoring checks, an explicit native replay adapter, report adjudication, and HTML rendering.

### Changed
- Parent IR validation, coverage, execution, and reporting gates now use the native CLI. TypeScript tooling remains available for migration parity, package suites, and consumers awaiting IR-4 adoption. Vocabulary generation and protocol-copy parity remain checked against the pinned TypeScript source. See [the migration sequence](spec/mck/migration.md).

### Fixed
- Interrupted kit downloads report how many bytes arrived and preserve the underlying error. Timeouts have an explicit diagnostic; acquisition limits and cleanup behavior are unchanged.

## [0.4.0-beta.1] - 2026-09-18

First beta of the Rust Morphir CLI. This release follows `0.4.0-alpha.7`; no `0.4.0-alpha.8` was
released, and the changes planned for it ship here.

### Changed
- **Breaking — IR document-tree layout**: `morphir migrate --output-layout vfs`, and project-mode `morphir compile` with `[ir] layout = "document-tree"`, write the layout the [document-tree page](docs/spec/ir/schemas/v4/document-tree-files.md) specifies and MCK cases document-tree-0001 to 0009 pin: `manifest.<ext>` at the root carrying `pathBudget` and listing dependencies by name, `pkg/<package path>/<module path>/module.<ext>` beside `<stem>.type.<ext>` and `<stem>.value.<ext>`, and each dependency under `deps/<package path>/@/<module path>/`. An `Application`'s dependencies now have a home in the tree instead of being refused. A tree written by an earlier release is refused with `morphir::ir::document_tree::missing_member` and the guidance `this tree predates 0.4.0-beta.1; regenerate it with morphir migrate`; the transport's own `name_mismatch` and `module_path_mismatch` codes are replaced by `morphir::ir::document_tree::invalid_distribution_shape`. See [Document-tree layout in 0.4.0-beta.1](docs/spec/ir/schemas/migration-guide.md#document-tree-layout-in-040-beta1) (decisions 0012 and 0015; finos/morphir-rust#160)
- **IR v4 legacy spellings**: the `legacy_spelling` window stays open in this release. Files with the older member names still decode with a warning. A later release refuses them; rewrite affected files with `morphir migrate` before then.
- **Python extension**: use the `extension/python/v0.2.0` bundle with this release. The `extension/python/v0.1.0` bundle requires `exposedModules` in every compile request and refuses a project that configures none with `missing field exposedModules`
- Update Rust dependencies, including `cucumber` 0.23, `getrandom` 0.4, `tokio-tungstenite` 0.30, `usage-lib` 6.9 and `uuid` 1.26 (#638, #752, #845)

### Added
- **Native Elm provider (opt-in)**: `morphir compile --extension morphir-elm-native` compiles a project's Elm type declarations to IR v3 or v4 with the built-in native Elm frontend from finos/morphir-rust#173; `--input File.elm --extension morphir-elm-native` compiles one file. With no `--extension`, Elm still resolves to the `morphir-elm` process extension. The native provider is types-only: value declarations are skipped with a warning (#848)
- **Frontend provider in configuration**: `[frontend.<language>] extension` selects the frontend provider for a project, for example `[frontend.elm] extension = "morphir-elm-native"`, so `--extension` is not necessary on every run. Precedence is the `--extension` flag, then the configured id, then the language's default provider. A blank or non-string value is a configuration error that names the key, and an id that does not provide the language is refused. Single-file compilation reads the key only with `--config` or `--project` (#854)
- **Incremental compile cache**: for a provider that advertises `frontend.incremental`, the CLI stores module results under `.morphir/cache/compile/<extension>/<package>/` and sends them back as the `baseline` of the next compile, so unchanged modules are not recompiled. A corrupt or mismatched cache is ignored. `--no-cache` skips the read and the write (#848)
- **Rust extension**: project-mode `morphir compile` discovers `.rs` sources, so the installed `morphir-rust` WASM bundle (finos/morphir-rust `extension/rust/v0.1.0`) compiles the documented Rust subset to IR v3 or v4 and generates Rust. Earlier releases installed the bundle but refused compilation with `Unknown language: rust`. CI publishes, installs and runs the bundle through the CLI (#840)
- The development Python extension supports typed function calls, same-package function imports, unary `Callable` annotations and captured lambdas in IR v3 and v4. Packaged CLI tests cover compilation, generation and workspace model loading for these functions.
- Project compilation honors `[ir].format_version` and `--ir-version` for v3 or v4. The new Python extension bundle supports v3 compilation and generation; v3 artifacts use JSON/YAML single-file storage.
- **Document-tree input spellings**: a `manifest.yml` root is recognised and read as a YAML document tree alongside `manifest.yaml` (it is never written back as `.yml`). `morphir generate -i` and every other path that probes a directory now ask the transport which manifests count, so the two agree

### Fixed
- `morphir extension repository init <name>` accepts a bare relative path such as `repo`; it failed with `failed to access : No such file or directory` (finos/morphir-rust#175)
- Project-mode `compile` and `generate` honor `--project` and resolve sources from the selected member. Configured module exposure reaches the frontend, including private Python modules. Connected workspace model loading follows compile records and their JSON/YAML file or document-tree artifacts, including output-root overrides; a failed compile cannot reopen a stale installed model.
- Reading or rewriting a document tree never follows a symlink or junction, so neither can reach outside the tree root; a manifest that is itself a link is refused with `morphir::ir::detection::linked_manifest` rather than reported as a missing manifest

## [0.4.0-alpha.7] - 2026-09-17

### Added
- **Python extension bundles**: `morphir extension repository publish` preserves frontend languages and backend targets in the Python extension's release descriptor. Install the separately released `morphir-python` WASM bundle to compile the supported Python ADTs, fixed tuples and conditional functions to IR v4 and generate Python. CI verifies publication, installation and offline compilation/generation through the CLI.

### Changed
- Update `morphir-rust` to `b4566e5`, adding Python extension packaging and frontend-aware publication (finos/morphir-rust#158), plus fixed tuples, conditional function bodies and arbitrary-precision integer literals (finos/morphir-rust#157). The Python extension is built and installed separately.
- **IR format-version support tables**: format-version support tables are intervals (`[3.0.0,3.1.0),[4.0.0,4.1.0)`); a later patch of a supported minor is read, a later minor is refused with `unsupported_format_version_minor`, which replaces `unsupported_format_version_revision` (decision 0016)
- **IR v4 legacy spellings**: the member names and shapes the Rust CLI wrote before the v4 vocabulary settled (`attrs`, `argumentType`/`arg`, `result`, `thenBranch`/`elseBranch`, `subject`/`fieldName`, `valueName`/`valueDefinition`/`inValue`, the single-target `ExternalBody`, and a few pre-decision structural shapes) decode with a `legacy_spelling` warning starting in 0.4.0-alpha.7 and are refused in a later release. See [Files written by CLIs before 0.4.0-alpha.7](docs/spec/ir/schemas/migration-guide.md#files-written-by-clis-before-040-alpha7) for the full table and the `morphir migrate` command that rewrites affected files.
- **YAML output style**: `morphir migrate`, and project-mode `morphir compile` with `[ir] format = "yaml"`, write the v4 YAML profile's canonical style — flow sequences where no mapping appears inside them, quoting only where a plain spelling would change meaning, member order as the encoder writes it, one trailing newline. Single-file `morphir compile` always writes classic v3 JSON regardless of `[ir]`. Files written by earlier versions still read. See [YAML output style](docs/spec/ir/schemas/migration-guide.md#yaml-output-style) (finos/morphir-rust#153)
- **YAML diagnostics**: the YAML codec's private `morphir::ir::yaml::*` names are replaced by the conformance kit's codes (`duplicate_key` and `duplicate_format_version` become `duplicate_member`; `alias_not_allowed`, `unsupported_tag` and `merge_key_not_allowed` become `unsupported_yaml_feature`; `multiple_documents` becomes `invalid_yaml`; `non_finite_number` becomes `invalid_literal`; `ambiguous_scalar` is gone because an unquoted timestamp-like scalar is a string). See the rename table in the migration guide (finos/morphir-rust#153)

### Fixed
- `morphir config show` printed serde_json's internal number representation instead of `format_version = 3`
- The install ledger wrote backslash paths on Windows, so a second `morphir install` treated its own output as foreign content

## [0.4.0-alpha.6] - 2026-09-03

First alpha of the Rust Morphir CLI with run-time extensions. The previous
alpha, 0.4.0-alpha.5, only moved the release pipeline to the Rust binary.

### Added
- **Extensions**: `morphir extension` manages Morphir Extension Protocol (MEP) providers. `install`, `update`, `uninstall`, `list`, and `search` acquire verified process and WASM extensions from configured repositories with SHA-256 content verification, exact lock files, and offline activation (#729, #765, #770)
- **Extension repositories**: `morphir extension repository` adds, lists, enables, disables, inspects, verifies, and removes repositories, and `init` plus `publish` author a local repository from a release bundle (#765, #770)
- **WASM backends**: `morphir generate` routes to installed WASM backends. Apache Avro (`avro`), OpenAPI (`openapi`), and JSON Schema (`json-schema`) targets are served by the `morphir-avro` and `morphir-openapi` extensions released from finos/morphir-rust. Backend options come from `[codegen.<target>]` in `morphir.toml` and repeatable `--option KEY=VALUE` flags (#745, #766)
- **Compile providers**: `morphir compile` compiles Elm through an installed Morphir Elm or Morphir Scala process extension, selectable with `--provider` (#726, #733, #736)
- **Gleam**: the Gleam backend ships as a built-in provider
- **Migrate**: `morphir migrate` converts Morphir IR between format versions, with YAML as the primary output format (#720, #732)
- **Knowledge base**: `morphir kb` checks, scaffolds, indexes, syncs, and renders Open Knowledge Format bundles (#722)
- **Desktop**: `morphir desktop` acquires, installs, and launches verified Morphir Desktop packages, including unsigned local packages, with correlated launch logs (#741, #746, #773, #777, #779, #782, #784)
- **Playground**: `morphir playground` serves the vendored Playground client over the Morphir Playground protocol and reuses one extension session across invocations (#778, #783)
- **Web workbench**: `morphir ui` serves the connected web workbench with workspace navigation and the Insight and XRay views (#756, #757, #790)
- **Cache**: `morphir cache status` and `morphir cache clean` inspect and prune the content-addressed store (#753)
- **Home**: `MORPHIR_HOME` relocates the Morphir home directory (#712)
- **Config**: secret values can come from commands and the system keyring (#710)
- **Out directory**: every task writes under `.morphir/out` and records a task result; `-o` installs the declared outputs into the requested directory (#789)

### Changed
- **Breaking:** compile and generate always write under the workspace out root (`<workspace>/.morphir/out/<module>/<task>.dest`) and write a `<task>.json` result record. `-o` now installs the task's declared outputs to the given directory after the run instead of redirecting the task; on the single-file Elm compile path, `-o` used to take a file path and write the IR there directly, and now takes a directory like every other command. `--out-dir` and `MORPHIR_OUT_DIR` relocate the root. Config: `[workspace].output_dir` is now `[workspace].out_dir` (default `.morphir/out`), `[project].output_directory` is removed, `[ir].mode` is replaced by `[ir].layout` and `[ir].format` (`ir.mode` still works for one release as a deprecated alias, with a warning). Generate reads compile output through the record, so `[ir]` YAML and document-tree storage now flow through to backends, and `generate -i` also accepts a compile-output directory in addition to an IR file or a document-tree directory. The single-file Elm compile path still always writes classic v3 JSON regardless of `[ir]`; it now warns when a given `--config`'s `[ir].layout` or `[ir].format` asks for something else, since those settings do not apply to it. `output_path` in a command's JSON result is the task's canonical `.dest` directory for every command, not an artifact file inside it. (#789)
- Morphir IR v4 name canonicalization and initialism encoding follow the accepted conformance corpus (#744)
- The v3 and later `formatVersion` contract is defined and enforced (#738)
- The CLI reference under `docs/cli` is generated from the CLI usage spec and checked in CI (#714)

### Fixed
- Installed extensions no longer fail at initialize when the display name in the repository record differs from the name the guest reports. `extension repository publish` derived "Morphir Openapi" from the identifier while the guest reports "Morphir OpenAPI", so every published OpenAPI bundle failed with "initialization metadata disagreed with discovery". A release bundle may now declare its `name` in `release.json`

### Removed
- `morphir-live` is retired. The web workbench in `morphir ui` replaces it (#739, #740)

### Infrastructure
- Release workflow builds the CLI for six targets and uploads only assets whose checksum changed (#703, #704)
- CI builds the Morphir Elm and Morphir Scala process extensions and runs the installed-extension integration tests against them; it now also builds the Avro and OpenAPI WASM guests and runs the WASM backend tests (#754)

## [0.4.0-alpha.5] - 2026-08-25

### Changed
- The release pipeline now packages the Rust `morphir` CLI for Linux, macOS, and Windows on x86_64 and aarch64 (#703, #704)

## [0.4.0-alpha.4] - 2026-01-13

### Added
- **CLI Logging Integration**: Structured logging now available throughout CLI (#555)
  - Global logging flags: `--log-level`, `-v/--verbose`, `-q/--quiet`, `--log-file`
  - Log level resolution: CLI flags > Environment variables > Config file > Defaults
  - `GetLogger()` function for commands to access configured logger
  - `validate` command updated as reference implementation
- **Pipeline Logging Support**: Logger propagation through pipeline execution (#555)
  - Added `Logger` field to `pipeline.Context`
  - `WithLogger()` method for immutable logger propagation
  - Default noop logger when not configured

### Changed
- Upgraded charmbracelet/lipgloss to v2.0.0-beta.3 (#556)
  - Updated all imports to `github.com/charmbracelet/lipgloss/v2`
  - Using `compat.AdaptiveColor` for backward-compatible adaptive colors
  - Theme colors now use `lipgloss.Color()` with `color.Color` interface
- Updated all internal module dependencies to v0.4.0-alpha.3

### Infrastructure
- Enhanced release validation with module consistency checks (#554)
  - Validates all modules have corresponding `go mod tidy` entries in `.goreleaser.yaml`
  - Checks that hook scripts referenced in `.goreleaser.yaml` exist
- Added new Go module checklist documentation in DEVELOPING.md (#554)

### Fixed
- Workspace setup now resilient to unpublished module versions
  - `go work sync` failures no longer block workspace setup
  - Enables CI to work with release PRs that bump cross-module versions
- External consumption test now handles cross-module release changes
  - Detects release branches and allows expected cross-module dependency failures
  - Provides clear messaging when code uses unreleased internal module features

## [0.4.0-alpha.3] - 2026-01-13

### Added
- **Structured Logging**: New `pkg/logging` module with zerolog wrapper (#549)
  - Logger type with functional options pattern (`WithLevel`, `WithFormat`, `WithFile`)
  - Multi-writer support for simultaneous stderr and file logging
  - Configurable log levels (trace, debug, info, warn, error, fatal, disabled)
  - Text format (colored, human-readable) and JSON format for log aggregation
  - Log files written to `.morphir/logs/` directory
  - `Noop()` logger for testing and disabled logging scenarios

### Changed
- Removed `-v` short flag from `--version` command (reserved for future `--verbose` flag)
- Use `morphir --version` or `morphir version` for version information

### Infrastructure
- Migrated mise tasks to TypeScript/Python with pinned tool versions (#548)
  - Tasks now use Bun for TypeScript execution
  - Improved cross-platform compatibility
  - Better error handling and output formatting

### Fixed
- Updated charmbracelet/lipgloss dependency to v2 (#546, #547)

## [0.4.0-alpha.2] - 2026-01-13

### Added
- **Decoration System**: New decoration infrastructure for metadata enrichment
  - `morphir decorate` CLI command for applying decorations
  - Type registry for decoration types with validation
  - BDD tests for decoration workflows
- **Toolchain Integration Phase 2**: Major expansion of toolchain adapters
  - **Go Toolchain Adapter**: Complete Go code generation support (#529)
    - `morphir golang make` command to generate Go modules from IR
    - `morphir golang build` command for full IR→Go pipeline
    - IR to Go module/workspace generator (#515)
    - Comprehensive tests and fixtures (#524)
  - **WIT Toolchain Adapter**: WebAssembly Interface Types Phase 2 (#526)
  - **morphir-elm Integration**: NPX backend for morphir-elm tooling (#530)
    - Integration tests validating morphir-elm interoperability (#534)
  - **Toolchain Enablement Design**: Framework for toolchain discovery and enablement (#538)
- **Workflow Planning System**: New workflow orchestration capabilities (#533)
  - Workflow plans with dependency resolution
  - Workspace doctor command for environment validation (#531)
- **Website Improvements**:
  - Upgrade Docusaurus from 2.4.3 to 3.9.2 (#523)
  - Contributing companies panel (#514)
  - Restructured documentation hierarchy for newcomers (#379)

### Fixed
- Decorations CI issues (#541)
- Docusaurus config for morphir.finos.org deployment (#517)

### Changed
- Updated lipgloss dependency to v2 (#512)
- Updated npm to v19 (#444)
- Updated TypeScript to ~5.9.0 (#525)
- Updated doublestar to v4.9.2 (#490)

### Infrastructure
- Added golangci-lint to mise tools
- Comprehensive documentation improvements and tooling (#527)
- Security dependency updates for website

## [0.4.0-alpha.1] - 2026-01-08

### Added
- **WIT Pipeline** (CLI Preview): WebAssembly Interface Types support for Morphir
  - `morphir wit make` command to compile WIT files to Morphir IR
  - `morphir wit gen` command to generate WIT from Morphir IR
  - `morphir wit build` command for full WIT→IR→WIT pipeline
  - JSONL batch processing mode for streaming/CI workflows (`--jsonl` flag)
  - Type mapping infrastructure with diagnostics for lossy transformations
  - WIT parser adapter and emitter with round-trip support
  - BDD tests with scenario outlines for comprehensive coverage
- **Virtual File System (VFS)**: New `pkg/vfs` module for filesystem abstraction
  - Core VFS implementation with virtual paths (`VPath`)
  - Traversal helpers for entry tree manipulation
  - Shadowing support for overlaying file systems
  - Sandbox policy hooks for write operations
  - Path manipulation helpers
- **Task Execution Engine**: New `pkg/task` module for build orchestration
  - Task/target execution with dependency tracking
  - Pipeline integration for task configuration
  - `morphir task list` command to display configured tasks
- **Pipeline Enhancements**: Major improvements to `pkg/pipeline`
  - Core pipeline types and composition framework
  - Validation step with improved diagnostics
  - Comprehensive unit tests for composition and error handling
- **Document Processing**: New `pkg/docling-doc` module
  - Functional document processing with efficient builder pattern
  - BDD tests integrated into release process
- **Jupyter Notebook Support**: New `pkg/nbformat` module
  - Support for reading and processing `.ipynb` files
- **IR Visitor Framework**: New visitor pattern for Morphir IR
  - Type and Pattern traversal helpers
  - Extensible visitor infrastructure
- **Type Mapping Infrastructure**: New `pkg/bindings/typemap` module
  - Registry for bidirectional type mappings
  - Support for multiple binding targets (WIT, Protocol Buffers, etc.)

### Changed
- Migrated task runner from Justfile to `mise` tasks across scripts, docs, and CI
- Removed outdated morphir-elm subtree and related Elm code
- Upgraded Docusaurus from 2.0.0-beta.15 to stable 2.4.3
- Updated lipgloss dependency to v2

### Documentation
- Added CLI Preview documentation for v0.4.0-alpha.1
- Improved code coverage documentation and module tracking
- Added module and package documentation for `pkg/models`

### Infrastructure
- Comprehensive code coverage and test reporting in CI/CD
- Node.js 24 configured for Docusaurus website builds
- Updated GitHub Actions (checkout v6, artifact actions, create-issue-from-file v6)
- Security dependency updates for website

## [0.3.3] - 2026-01-05

### Added
- **`morphir about` command**: Display version, platform information, and embedded changelog
  - Shows version, git commit, build date, Go version, and platform details
  - `--changelog` flag displays full embedded CHANGELOG.md with colorful markdown rendering by default
  - `--no-color` flag and `NO_COLOR` environment variable support for plain text output
  - `--json` flag for programmatic access to version information
  - Embedded CHANGELOG synced automatically during build process
  - Glamour-powered markdown rendering with automatic dark/light theme detection
- **Install script enhancements**: Support for installing specific versions
  - `install.sh <version>` and `install.ps1 <version>` now accept version argument
  - Still defaults to latest release if no version specified
  - Downloads pre-built binaries from GitHub releases (no Go required)

### Fixed
- **Release script CI wait logic**: Improved automation and reliability
  - Now actively polls and waits for CI to complete (10 minute timeout)
  - Shows progress indicators during wait
  - Prevents releases when CI is still running or failed
  - Reduces manual intervention needed for releases

### Changed
- **Build process**: CHANGELOG.md now automatically synced to cmd directory
  - Added `sync-changelog` mise task with dependency tracking
  - GoReleaser hooks updated to include changelog sync
  - `.gitignore` updated to exclude generated `cmd/morphir/cmd/CHANGELOG.md`

## [0.3.2] - 2026-01-05

### Fixed
- **CRITICAL**: Remove replace directives from source code for go install compatibility
  - Removed all `replace` directives from cmd/morphir/go.mod
  - Removed all `replace` directives from pkg/tooling/go.mod
  - Removed all `replace` directives from tests/bdd/go.mod
  - `go install github.com/finos/morphir/cmd/morphir@v0.3.2` now works correctly
- Documented workflow trigger limitations for re-pushed tags

### Added
- **morphir-developer skill**: Comprehensive development workflow assistant
  - go.work management and verification
  - Branch/worktree setup with issue tracking
  - Pre-commit checks and best practices
  - Integration with beads and GitHub issues
  - TDD/BDD workflow guidance
- **Release automation script**: `scripts/release.sh` for automated releases
  - Complete pre-flight checks
  - Automated tag creation and pushing
  - Workflow triggering and monitoring
  - Post-release verification
  - go install compatibility testing
- **Workspace setup scripts**: Dynamic go.work configuration
  - `scripts/setup-workspace.sh` for Linux/macOS
  - `scripts/setup-workspace.ps1` for Windows
  - Automatically discovers all Go modules
  - Used by CI and local development
- **CI enhancements**: go.work setup for all build/test jobs
  - All CI jobs now use go.work for local module resolution
  - External consumption test for release PRs
  - Verifies module versions are correct before release

### Changed
- Development workflow: Use `go work` for local development instead of replace directives
- Release process: Source code in tags no longer contains replace directives
- Release process: Automated with `scripts/release.sh` for consistency
- CI workflow: All jobs now set up go.work automatically
  - Ensures consistent behavior between local dev and CI
  - Release PRs get additional external consumption test

## [0.3.1] - 2026-01-05

### Fixed
- Complete module version references for all internal dependencies
  - Updated pkg/tooling/go.mod to reference v0.3.0 for pkg/config and pkg/models
  - Updated tests/bdd/go.mod to reference v0.3.0 for pkg/models
  - Fixed release workflow to handle existing tags with `-f` flag
- Release workflow now supports manual re-triggering for failed releases

## [0.3.0] - 2026-01-04

### Added
- **Interactive TUI Framework**: Full-featured terminal UI with vim-style navigation
  - Modern terminal interface using Bubbletea and Lipgloss
  - Vim-style keybindings (h/j/k/l navigation, gg/G, Ctrl+d/u)
  - Three-panel layout: sidebar, content viewer, and status bar
  - Markdown rendering support with syntax highlighting
  - Collapsible sections and tree navigation
  - Demo application showcasing TUI capabilities
- **Markdown Rendering**: Rich markdown support in terminal
  - Headings, lists, code blocks with syntax highlighting
  - Links, emphasis (bold, italic), blockquotes
  - Horizontal rules and inline code
  - Configurable color themes
- **Enhanced Validation**: Improved `morphir validate` command
  - Better error reporting and diagnostics
  - JSON output support for programmatic use
  - Validation of Morphir IR structure
- **Layered Configuration System**: Complete configuration management with multiple sources
  - TOML file support (`morphir.toml`, `.morphir/morphir.toml`)
  - XDG-compliant path resolution for global config (`~/.config/morphir/`)
  - System-wide configuration (`/etc/morphir/morphir.toml`)
  - User override file (`.morphir/morphir.user.toml`, gitignored)
  - Environment variable overrides with `MORPHIR_*` prefix
  - Priority-based merging (env > user > project > global > system > defaults)
- **Workspace Management**: Discovery and initialization of Morphir workspaces
  - `morphir workspace init` command with `--hidden` and `--name` flags
  - Automatic workspace discovery walking up directory tree
  - Standard directory structure (`.morphir/out/`, `.morphir/cache/`)
- **Configuration CLI Commands**:
  - `morphir config show` - Display resolved configuration
  - `morphir config path` - Show configuration file locations and status
  - `--json` flag on all commands for programmatic access
- **Schema Validation**: Configuration validation with errors and warnings
  - Validates log levels, formats, paths, numeric ranges
  - Distinguishes fatal errors from non-fatal warnings
- **New Packages**:
  - `pkg/config` - Public configuration API with immutable types
  - `pkg/tooling/workspace` - Workspace discovery and initialization
  - `pkg/tooling/markdown` - Markdown rendering for terminal output
  - `cmd/morphir/internal/tui` - Reusable TUI framework components
- **Documentation**:
  - Comprehensive configuration guide (`docs/configuration.md`)
  - TUI framework documentation and examples
  - Package documentation (`doc.go` files)
  - Example configurations (`examples/morphir.toml`, `examples/morphir.minimal.toml`)
  - Updated README with Configuration section
  - New DEVELOPING.md and INSTALLING.md guides
- **Release Infrastructure**:
  - GoReleaser configuration for automated releases
  - GitHub Actions CI workflow for format, lint, test, and build checks
  - GitHub Actions release workflow for automated releases on tags
  - Release preparation scripts with multi-module tagging support
  - `go install` support with proper module structure
- **Development Tools**:
  - Installation scripts for Linux/macOS and Windows (PowerShell)
  - Development setup scripts
  - Changelog suggestion script
  - Enhanced Justfile with new development targets

### Changed
- `morphir workspace init` now fully functional (was stubbed)
- Migrated morphir-go codebase into main morphir repository
- Updated module paths from `github.com/finos/morphir-go` to `github.com/finos/morphir`
- Enhanced build system with workspace-based development support
- Improved CLI architecture for better extensibility

### Fixed
- Module path resolution for `go install` compatibility
- Replace directives handling in multi-module workspace

## [0.1.0] - 2026-01-01

### Added
- Initial Go monorepo structure with `go.work` workspace
- CLI application built with Cobra and Bubbletea
- Root command that launches interactive TUI
- `workspace init` command (stubbed implementation)
- `validate` command for validating Morphir IR (stubbed implementation)
- Library modules: `models`, `tooling`, `sdk`, `pipeline`
- Build orchestration with Justfile
- Cross-platform scripts directory with bash and PowerShell versions
- OS detection infrastructure for Windows, Linux, macOS support
- Development build targets (`build-dev`, `install-dev`)
- CI check script for running all validation tasks
- AGENTS.md with development guidelines and project principles
- CLI development guidelines for stdout/stderr separation and JSON output support
- Functional programming principles and TDD/BDD practices documentation

### Changed
- Updated to Go 1.25.5
- Refactored Justfile with proper OS detection and readable formatting
- Improved command registration consistency

### Fixed
- Duplicate help command registration in CLI

[Unreleased]: https://github.com/finos/morphir/compare/v0.4.0-beta.6...HEAD
[0.4.0-beta.6]: https://github.com/finos/morphir/compare/v0.4.0-beta.5...v0.4.0-beta.6
[0.4.0-beta.5]: https://github.com/finos/morphir/compare/v0.4.0-beta.4...v0.4.0-beta.5
[0.4.0-beta.4]: https://github.com/finos/morphir/compare/v0.4.0-beta.3...v0.4.0-beta.4
[0.4.0-beta.3]: https://github.com/finos/morphir/compare/v0.4.0-beta.2...v0.4.0-beta.3
[0.4.0-beta.2]: https://github.com/finos/morphir/compare/v0.4.0-beta.1...v0.4.0-beta.2
[0.4.0-beta.1]: https://github.com/finos/morphir/compare/v0.4.0-alpha.7...v0.4.0-beta.1
[0.4.0-alpha.4]: https://github.com/finos/morphir/compare/v0.4.0-alpha.3...v0.4.0-alpha.4
[0.4.0-alpha.3]: https://github.com/finos/morphir/compare/v0.4.0-alpha.2...v0.4.0-alpha.3
[0.4.0-alpha.2]: https://github.com/finos/morphir/compare/v0.4.0-alpha.1...v0.4.0-alpha.2
[0.4.0-alpha.1]: https://github.com/finos/morphir/compare/v0.3.3...v0.4.0-alpha.1
[0.3.3]: https://github.com/finos/morphir/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/finos/morphir/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/finos/morphir/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/finos/morphir/compare/v0.2.1...v0.3.0
[0.1.0]: https://github.com/finos/morphir/releases/tag/v0.1.0
