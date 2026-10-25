# Morphir CLI

The CLI discovers Morphir workspaces, resolves TOML configuration, runs Scheme/IR pipelines and publishes artifacts through a host adapter.

## Run from this repository

On a fresh MoonBit installation, initialize the dependency registry first:

```sh
mise exec -- moon update
```

```sh
mise exec -- moon run apps/morphir --target native -- run path/to/workspace --all
mise exec -- moon run apps/morphir --target js -- workspace path/to/workspace --json
```

Or build and run a standalone executable:

```sh
mise exec -- moon build apps/morphir --target native --release
./_build/native/release/build/morphir/morphir/morphir.exe run path/to/workspace --all
```

On Windows, the generated native C file requires MSVC's
[`/bigobj` option](https://learn.microsoft.com/en-us/cpp/build/reference/bigobj-increase-number-of-sections-in-dot-obj-file?view=msvc-170).
Before running the native source commands above in PowerShell, set
`$env:CL = "/bigobj $env:CL"`. The native CLI acceptance script sets this option
for its Windows build subprocess and preserves existing `CL` options.

## npm package

```sh
mise exec -- bun run --cwd apps/morphir build
node apps/morphir/bin/morphir.js --help
node apps/morphir/bin/morphir.js run path/to/workspace --all
```

The package is named `@morphir/morphir`. After installing a packed or published package, invoke `morphir`. Installation does not require the MoonBit toolchain.

`morphir mck` delegates kit inspection, offline checks, suite execution and report
commands to an explicitly pinned prebuilt canonical backend. See the
[MCK guide](docs/mck.md) for provisioning, supported hosts, output and cancellation.

`morphir extension describe|compile|generate` runs an explicitly pinned MEP extension in a fresh
guest process. Bindings include the saved core-Wasm guest in a pinned Node host and an explicit
native process through the shared Rust host. Local repository and bundle lifecycle commands
use the shared distribution library;
see the [extension guide](docs/extension.md) for pins, reports, limits and cancellation.

`morphir compile` exposes embedded rich compilation without an extension host:

```sh
morphir compile path/to/project --language moonbit --provider finos/morphir-moonbit-frontend --profile moonbit-model-stable-v1 --json
morphir compile path/to/elm-project --language elm --provider finos/morphir-elm --profile library-origins --json
```

The command reuses `run` discovery, frontend registration, planning, model admission and
atomic publication. `--input` is an alternative to the positional directory/file path;
`--project` selects a workspace member; `--file` or `--directory` asserts the selection kind.
`--package` sets the model package identity. `--output` is a workspace-relative output root
containing `compile.dest`, with the same member layout as `run`.

Ion binary is the default. `--model-format ion-text` retains readable metadata and origins.
`--model-format morphir-json` performs the existing checked export and refuses lost metadata;
the Elm `library` profile supports plain JSON, while `library-origins` retains source origins.
Only draft IR version `4`, `4.0.0` or `4.0.0-draft` is accepted by `--version`. Types-only,
unregistered providers/profiles and provider-specific flags are refused. These commands retain
the existing frontend capability limits; they do not imply arbitrary imports or numeric support.

Compile JSON has `profile: "morphir/command-result"`, `contractVersion: "0.1.0"`,
`command: "compile"`, `state`, `exitCode` and `diagnostics`. Success includes `result` with
provider facts, artifacts and publication receipts. Failure includes `error: {code, message}`
and no `result`. Source/validation failures exit 1, cancellation exits 130 and parser syntax
errors retain exit 2. Help uses the existing CLI JSON help schema and writes no artifacts.
Diagnostics use stderr; stdout contains one JSON result. Existing `run` and `generate` success
schemas are unchanged.
On process-capable hosts, compile logs default to `.morphir/logs/frontend.ionb`.
`--log-file` and `--log-format` use the existing telemetry sink contract. Portable
hosts without process/clock support keep compilation available without default file logging.

## WASM and WASM-GC

```sh
mise exec -- moon build apps/morphir --target wasm --release
node pkgs/morphir-host/runners/wasm.mjs \
  _build/wasm/release/build/morphir/morphir/morphir.wasm run path/to/workspace --all
```

For WASM-GC, change both target/path occurrences from `wasm` to `wasm-gc`. WASI uses only Preview 1 imports and preopens the current directory; discovery cannot ascend outside that preopen. WASM-GC uses the documented `morphir_host_v1` embedding interface. See [host adapters](../../pkgs/morphir-host/README.md) for configuration mounts and runtime details.

## Commands

```sh
morphir workspace [path] --json
morphir project list [path]
morphir project list [path] --frontend scheme --target ir-json --json
morphir project list [path] --target scheme --target ir-json --json-lines
morphir run [path] --project Core
morphir run [path] --project packages/core
morphir run [path] --all
morphir run path/to/file.scm --file
morphir run path/to/source-directory --directory
morphir run [path] --config transforms.scm --backend scheme
morphir run [path] --dry-run
```

Paths are relative to the current directory. Without a selection, the CLI chooses the enclosing member, configured default member, root project or sole member. A workspace with several members and no default requires `--project` or `--all`. A file path selects only that file. A directory within a project's sources selects that directory; `--directory` explicitly selects a directory even if it is a project root.

`--backend scheme` works on MoonBit and Elm projects. Next to each `<unit>.scm` it writes `<unit>.symbols.10n`, a binary Ion sidecar that keeps the unit's metadata, and it comments each `define` with its source name and position, so it reports no `backend.metadata_dropped`. Elm projects carry declaration origins with `frontend.profile = "library-origins"`; the default `library` profile carries none.

Options include `--frontend`, `--frontend-provider`, `--frontend-profile`, `--backend`, `--output`, `--config`, `--json` and `--dry-run`. Dry run resolves scripts and prints planned sources/destinations without reading source contents or publishing outputs. Exit statuses are 0 success, 2 invalid invocation/configuration, 1 execution/publication failure and 130 cancellation.

`project list` lists every discovered project in workspace order, including the enclosing workspace when invoked from a member. A standalone project produces one entry. Each entry has its project name, relative path, effective frontend and target. Target names are the configured backend identifiers from `pipeline.backend`, defaulting to `ir-json`; frontend defaults to `scheme`. Workspace and member Scheme scripts are applied after manifest configuration, and `--config` adds a final script. Listing can report language choices whose compiler plugins are not installed. It reads configuration without reading source contents or publishing artifacts.

For `project list`, `--frontend` and `--target` filter these effective choices using exact, case-sensitive names. Repeated values match any value within that filter; frontend and target filters must both match when combined. Filters do not override configuration. No matches produce an empty list with exit status 0. Invalid project configuration produces diagnostics and exit status 2, including when filters exclude that project. Text output has `NAME`, `PATH`, `FRONTEND` and `TARGET` columns. JSON output contains `projects`, `diagnostics` and `successful`.

Argument parsing uses `moonbitlang/core/argparse` command definitions built from one
Morphir command table, with a Morphir check for empty values, duplicate policy and option conflicts. `morphir --help` and command-specific help such as
`morphir toolchain run --help` are generated from those definitions. JSON help keeps
its command/option inventory and adds a `usage` string. Parse failures retain the
JSON or JSON-lines error envelope and exit status 2.

The parser consumes caller-supplied arguments without reading the process
environment or exiting. Native, JS, Wasm and Wasm GC remain supported. The
standalone Wasm executable retains only `wasi_snapshot_preview1` imports;
it does not require additional MoonBit runtime bindings.

Options accept `--name value` and `--name=value`. Project-list frontend/target
filters, pipeline components and execution dependencies retain their order.
Pipeline options keep their existing last-value behavior; execution and toolchain
single-value options reject duplicates. Empty option values remain invalid.
The host and engine still validate option values and execution policies.

For `toolchain run` and `toolchain exec`, everything after `--` is forwarded
unchanged to the child program. Help/output flags, empty arguments, Unicode and
additional `--` tokens in that segment belong to the program. Morphir does not
interpret them. Other commands reject a program-argument segment.

## Structured output

Every command, including help and dry runs, supports `--json` and `--json-lines`. These flags can appear before or after the command and cannot be combined. `--json` emits one JSON document. `--json-lines` emits one JSON object per line, each with a `type` and `data` field. Diagnostics on stderr do not affect JSON parsing on stdout. A diagnostic has `code` and `location` (`startLine`, `startColumn`, `endLine`, `endColumn`) when the engine knows the problem.

```sh
morphir --json project list . --frontend scheme
morphir workspace . --json-lines
morphir run . --all --json-lines
morphir run . --dry-run --json-lines
morphir project list --help --json
```

| Command | JSON Lines record types |
| --- | --- |
| Help | `help` |
| `workspace` | `workspace` metadata, then `project` entries |
| `project list` | `project` entries, `diagnostic` entries, then a `result` summary |
| `run --dry-run` | `frontend` and `boundary` selections, `source` and `destination` paths, then a `plan` summary |
| `run` | `frontend`, `boundary`, `accepted`, `diagnostic`, `artifact` and `committed` entries, then a `result` summary |
| Invocation or configuration failure | `error` |

Project entries contain `name`, `relativePath`, `frontend`, `target` and `error`. A project with invalid configuration has null language fields. Project-list result summaries contain `successful` and `projectCount`; run result summaries contain `successful`, `processed` and `publicationError`. Failed transformations are reported as diagnostics followed by an unsuccessful result. Existing JSON documents for workspace discovery and pipeline execution retain their fields.

## Workspace example

```toml
[workspace]
members = ["packages/*"]
exclude = ["packages/experimental"]
default_member = "packages/core"
out_dir = ".morphir/out"

[frontend]
language = "scheme"

[ir]
format_version = 4
```

A member's `packages/core/morphir.toml`:

```toml
[project]
name = "Core"
source_directory = "src"
```

The CLI also finds `.morphir/morphir.toml` and `.config/morphir/config.toml`. Multiple primary candidates are errors. YAML candidates are detected and reported as unsupported. `morphir.json` is the morphir-elm project file and is read as an Elm project (see [Elm projects](#elm-projects)); other languages, Scheme included, use `morphir.toml`. `morphir-workspace.json` remains supported; canonical configuration takes precedence with a warning.

Configuration layers are defaults, system, global user, workspace primary, member primary, workspace/member user overrides, environment and CLI. Global configuration and shared workspace defaults exclude project identity and workspace-root settings when applied to a member. Tables merge recursively and arrays replace. Generic TOML encoding preserves unknown values semantically. Workspace scaffolding uses the lossless editor to preserve comments, formatting and untouched values.

Create a workspace and add projects with the same scaffolding used by the Workbench:

```shell
morphir workspace init
morphir project add packages/quotes --name Quotes --language scheme
morphir project add packages/pricing --name Pricing --language scheme
morphir run
morphir run --project packages/quotes
morphir project remove packages/pricing
```

`workspace init --project Quotes --language scheme` creates a root project as well as the workspace. Each project has its own configuration and starter source; multiple projects can use the same language. Elm project names use capitalized module segments, such as `Shop.Orders`. Omit `--language` on `project add` to inherit the workspace language. `--profile` chooses a source profile.

At the workspace root, `run` builds every project, or `workspace.default_member` when set. From a member directory it builds the owning project. `--all` explicitly selects all projects; `--project .` selects the root project. A virtual workspace has no root project until `[project]` is added.

`project remove PATH` removes membership and keeps the files. A glob-selected member is excluded. Add `--delete` to remove its folder too; deleting the workspace root is refused. Changes refuse symlinks, stale configurations and existing source files. An exclusive `.morphir-workspace-edit.lock` holds staging and backups until changes succeed; a rollback failure preserves it for manual recovery. TOML edits to dotted keys and arrays of tables currently return an explicit diagnostic.

These commands support human, `--json` and `--json-lines` output. JSON Lines emits a `workspace-edit` result with `writes`, `directories`, `deletes` and `warnings`. `workspace` lists discovery results; build flags such as `--all` and `--dry-run` belong to `run` and are refused by `workspace`.

Discovery responses use protocol version `"0.1.0"`, with warnings in `diagnostics`, including missing literal members and duplicate project names. The request decoder still accepts numeric version `1` for compatibility. The shared corpus is in `pkgs/morphir-engine/workspace/fixtures/upstream.json`.

Workspace and project `morphir.config.scm` files supply pipeline configuration and transforms. An explicit `--config` script runs last; explicit CLI language/provider/profile/backend choices are reapplied afterward. Scripts cannot access filesystem, processes or network implicitly.

Outputs go to `.morphir/out/<member-path>/compile.dest/<source-stem>.ir.json`. Each source produces an independent distribution. Project-wide linking and dependency resolution are separate compiler work. The legacy text frontends/backends are `scheme` and `ir-json`. The explicitly registered `moonbit` and `elm` source frontends use the typed checkpoint or generation pipeline below; requested unregistered frontends fail explicitly. JSON output supports IR versions 1 through 4 through existing lossless migration codecs. Unsupported layouts and serialization formats fail validation.

Conventional project/module spelling such as `Core` and `Main.scm` is converted to canonical IR names. `project.module_prefix` qualifies modules; `project.exposed_modules` controls module visibility.

No outputs are published if any selected project's transformation fails. A publication I/O failure can leave earlier task destinations committed; the JSON result identifies them. See the host documentation for locking and recovery.

## MoonBit source models

The CLI explicitly registers the [source frontend](../../pkgs/morphir-moonbit-frontend/README.md)
through the separate [engine adapter](../../pkgs/morphir-engine/moonbit/README.md).
For a `src/Main.mbt` file containing `pub fn eligible(active : Bool, vip : Bool) -> Bool { active && !vip }`:

```toml
[project]
name = "Pricing"
source_directory = "src"
module_prefix = "App"
[frontend]
language = "moonbit"
[pipeline]
backend = "checkpoint"
```

```sh
morphir run . --dry-run --json
morphir run . --json-lines
morphir run . --backend moonbit --validation source-only --json
```

Checkpoints default to binary Ion. `--checkpoint-format ion-text` keeps the rich
envelope readable. Source-only generation publishes library sources and binary Ion
symbol metadata without a compiler provider. Required build validation uses the
existing explicit provider configuration documented below.

The source language is `moonbit`. Provider `finos/morphir-moonbit-frontend` offers
the default `moonbit-model-stable-v1` profile and opt-in
`moonbit-model-experimental-v1`. Stable accepts typed Bool/String/Int32 libraries.
Experimental adds new numeric/Decimal capabilities pending installed qualification.
Select either channel without changing the language:

```toml
[frontend]
language = "moonbit"
provider = "finos/morphir-moonbit-frontend" # optional when there is one provider
profile = "moonbit-model-stable-v1"
```

```sh
morphir run . --frontend moonbit --frontend-profile moonbit-model-stable-v1 --dry-run
morphir run . --frontend-provider finos/morphir-moonbit-frontend --frontend-profile moonbit-model-stable-v1 --json
```

Both channels accept multiple typed functions, Bool, String and Int32. Experimental
also accepts expanded signed/unsigned integers, BigInt, Float/Double, audited SDK
math, Integer conversions and checked Decimal.
String ordering compares UTF-16 length first, then lexical code units for ties;
`"b" < "aa"` is true. Length and surrogate-aware owned slices are supported.
Public String inputs and outputs enforce well-formed UTF-16 and a 1,048,576-unit
bound. Functions can use immutable bindings, lexical shadowing and direct acyclic
same-file calls, including forward and zero-input calls. Function documentation
stays in IR and generated MoonBit/Scheme output.

Only stable and experimental are selectable. Boolean seed and intermediate
profile IDs are retired; update saved source configurations to the appropriate channel.
Existing checkpoints preserve their recorded provenance. The library is a finite
qualified subset, with imports, recursion, mutation and indirect calls excluded.
Installed numeric qualification is tracked separately.

Each `.mbt` file remains
an independent unit; this option does not link files. An all-private library has no
public execution entry. Stable is the default for configuration that omits a profile.

The provider publishes its supported profiles and configured validation budgets.
A provider must offer the selected language and profile. Multiple providers for a
language require `--frontend-provider`; planning does not guess by registration
order or profile name. `--frontend-provider` and `--frontend-profile` apply to
`run` commands. TOML configuration uses `frontend.provider`
and `frontend.profile`; Scheme uses `(frontend-provider "...")` and
`(frontend-profile "...")`. Explicit CLI choices win after scripts. `project list
--frontend moonbit` remains a language filter. Source profile constraints do not
apply to Ion or Morphir JSON codec inputs.

Logical IDs retain source-relative spelling, such as `nested/Main`; Morphir
package/module names use canonical spelling. Native Ion origins, annotations and
provenance survive checkpoints, generation and an unchanged `json-identity`
component. JSON checkpoints refuse to discard those origins. Existing Morphir JSON
inputs and semantic IR serialization remain supported. Rich source units reject
`ir-json` and transforms without metadata lineage; `scheme` accepts them with a warning.

Dry-run selects files without parsing or reading their bodies, opening log sinks,
or publishing output. MoonBit human output reports the selected language, provider,
profile, supported and excluded behavior, limits and evidence. JSON documents include
`frontends`; JSON Lines emits `frontend` records. Existing fields `source`, `unitId`,
`frontend`, `profile`, `dependencies` and `outputContract` remain. Additive fields are
`language`, `provider`, `defaultProfile`, `availableProfiles`, `capabilities` and
`evidence`. `defaultProfile` is true when the selected profile is the default, even
when chosen explicitly. Capabilities include `summary`, `supported`, `excluded`,
`maxDocuments`, `incremental` and `limits`. `maxDocuments` is `null` when a unit has
no document limit; human output then prints `documents per unit: no limit`.
Dependency pins remain in their own structured field. `local-acceptance` denotes
repository evidence, not MCK verification or a claim that arbitrary MoonBit code is
supported. These source descriptions are separate from IR capability vocabulary.

Execution reports stable `moonbit_frontend.*` diagnostic codes and available parser
spans, with provider/profile context. A failed source unit prevents task publication
and preserves existing task output. The rich unit and its compiler limits are fixed
when the plan is made, so later plugin registrations cannot change its execution.

## Elm projects

The CLI registers the Elm frontend of [`finos/morphir-elm`](../../pkgs/morphir-elm/README.md) by default, so an
unchanged morphir-elm project compiles with `morphir run`. A `morphir.json` file selects the provider; no
`morphir.toml` is needed:

```shell
morphir run path/to/elm-project
```

The `morphir.json` fields map as the [engine README](../../pkgs/morphir-engine/README.md#morphirjson-is-an-elm-project) describes: `name` is
the package name (`project.name`), `sourceDirectory` is the source directory (default `src`), and `exposedModules`
is required and gives `project.exposed_modules`. The project uses the `elm` frontend and the `checkpoint` backend
with the `morphir-json` format. The default output is the Morphir IR JSON of the package, at
`.morphir/out/compile.dest/<package path>.json` (for `Parity.Modules`: `parity/modules.json`).

Choose a generator with `--backend elm` or `--backend moonbit --validation source-only`:

```shell
morphir run path/to/elm-project --backend moonbit --validation source-only
```

The `ir-json` backend is for untyped frontends. The CLI refuses it for Elm with `frontend.typed_backend_required`.

`dependencies`, `localDependencies` and `decorations` are ignored. If one of them is not empty, the CLI gives a
warning. `morphir.json` is always read as an Elm project, and it must have `exposedModules`; a `morphir.json` without it is refused at discovery. Other languages, Scheme included, use `morphir.toml`.

## Ion checkpoints

The `checkpoint` backend runs a typed IR identity pipeline with Ion binary as its
default intermediate file format. Source format and checkpoint format are separate:

```toml
[project]
name = "Pricing"
source_directory = "src"
[frontend]
language = "ir-json"
[pipeline]
backend = "checkpoint"
checkpoint_format = "ion-binary"
```

```sh
morphir run . --frontend ir-json --backend checkpoint --json
morphir run . --frontend ion-binary --backend checkpoint --checkpoint-format ion-text
morphir run . --frontend ion-text --backend checkpoint --checkpoint-format morphir-json
```

`ir-json` reads supported versioned Morphir JSON. `ion-text` selects `.ion` files;
`ion-binary` selects `.ionb` and `.10n` files. Ion sources use the engine's
[`morphir-pipeline-v1` IR-unit envelope](../../pkgs/morphir-engine/data/README.md).
Each unit ID is its source-relative path with the final extension removed, such as
`nested/Main`. Moving or renaming an Ion source requires an explicitly matching
envelope ID. Output suffixes are `.ionb`, `.ion`, or `.json`, respectively, under
the existing `compile.dest` task directory. Checkpoint JSON export writes the
standard current Morphir JSON schema and refuses to discard engine metadata or
additional envelope annotations. Historical JSON export remains available through
the `ir-json` backend and `ir.format_version`.

Checkpoint execution preserves rich Ion metadata and ordered annotations. It
currently rejects configured transforms and `project.exposed_modules`, which
require metadata lineage. Scheme and registered text frontends can also produce
typed IR checkpoints. This source-only path needs no compiler or toolchain
provider and acquires nothing. Existing Scheme/JSON text pipelines retain their
defaults. `pipeline.checkpoint_format` applies to the checkpoint backend;
`ir.format` continues to describe the existing JSON output contract.

Dry-run and execution JSON include `boundaries`, recording selected codec,
profile and byte requirements. Execution adds `artifactDetails` with format,
encoding, byte count and `status: "accepted"`. An accepted artifact passed engine
generation; `committed` separately records destinations actually published.
JSON Lines uses `boundary` and `accepted` records for these additions while
retaining existing `artifact` path records. Human output makes the same
distinction. Failed staging or generation preserves the previous task output.

## Frontend logs

`morphir run . --log` enables frontend stage logs with no path configuration.
The default is `.morphir/logs/frontend.ionb` beneath the discovered project or
workspace root. `execute`, `verify` and `conform` use
`.morphir/logs/execution.ionb` beneath their working directory when `--log` is on.
The host creates the default log directory during bounded flush and retains three
previous log files. Logging stays off without `--log` or `--log-file`.

```sh
morphir run . --log --json
morphir run . --log --log-format ion-text
morphir run . --log-file /chosen/path/frontend.jsonl --log-format json-lines
```

An explicit `--log-file` wins over the default, including paths outside
`.morphir/logs/` and the existing `@stderr` text sink. Relative explicit paths resolve from cwd. Their parent directories must
already exist. Formats are binary Ion by default, Ion text, JSON Lines and text;
default filename extensions follow the selected format. Dry runs parse no source
and create no logs or log directories. A failed optional sink reports a warning
without changing artifacts or required diagnostics.

Both MoonBit channels record nested `frontend`, `parse`, `profile-check`, `resolve`
and `lower` spans through the portable observation contract, with a second
`profile-check` stage after resolution. `profile-check` checks declarations
and signatures; `lower` checks and lowers body expressions. Default records omit
source text, source paths, parameter names and diagnostic text. Observations do not
enter IR metadata, provenance or identity inputs. CLI local log delivery uses the
existing native and Node host capabilities; standalone WASI/Wasm GC CLI hosts
report `observability.clock_capability_required` if logging is requested. Their
normal source compilation and pure host-supplied observation remain supported.

## Tests

```sh
mise run test:cli
```

Tests run real workspaces on native, Node, standalone WASI and WASM-GC, then pack/install the npm package and repeat the workflow.

## MoonBit tooling

```sh
morphir toolchain info --json
morphir toolchain setup --yes --json-lines
morphir toolchain build ./project --target wasm --json
morphir toolchain run ./project --package main --target wasm --json -- argument
morphir toolchain exec ./script.mbtx --json
```

Use `--home <directory>` or `MORPHIR_MOON_HOME` to select a toolchain explicitly.
Setup reuses matching installations. Network acquisition requires `--yes` and
currently supports macOS arm64 and Linux x64. Native, Node and the Node WASM-GC
runner provide process execution; plain WASI reports it as unsupported. Every
command supports text, JSON and JSON Lines, including errors and help.

`--timeout <milliseconds>` bounds each child operation, from 1 through 600000;
the default is 120000. Arguments after `--` belong to the executed program, so its
`--help` and `--json` flags are preserved. See the host toolchain and embedding
packages for adapters and capability details.

Generate a complete MoonBit library from supported Morphir JSON or Ion input:

```sh
morphir run . --frontend ir-json --backend moonbit --validation source-only
```

Each input gets a project directory with compiler-native source and manifests
and a binary Ion symbol file. MoonBit exports default to readable names and retain
usable MoonBit source spellings. `[backends.moonbit] naming = "legacy-hex"` selects
the earlier generated ABI. Naming recoveries appear as structured warnings even
with logs disabled; `pipeline.strict_naming = true` stops publication on recovery.
New MoonBit source uses the `moonbit-readable-names-v1` identity policy and
`moonbit-readable-targets-v1` generated-name policy. Use returned canonical
entries in invocation suites and allocated names from `symbols.10n` in consumers.
Existing checkpoints retain their identities, including earlier `source-<hex>`
entries. Choosing `legacy-hex` changes automatic target allocation, not checkpoint
identity or an explicit declared target request.

The library generator accepts declared `targetNames` through a host-supplied
authenticated provider. The installed CLI has no signed-Library restoration
service yet. It preserves those facts in Ion checkpoints and rejects generation
with `metadata.provider_unavailable` before publication. This failure leaves
existing output intact. Unknown metadata remains opaque; Morphir JSON export
retains its checked metadata-loss boundary.

JSON reports include the project contract and
membership; JSON Lines reports emit `generated`, `validated` and `published`
events separately. Required builds are the default and require a library
build provider before publication.

For required validation, supply the process provider, helper, matching compiler
installation and offline SDK source explicitly:

```sh
morphir run . --frontend ir-json --backend moonbit --target native \
  --build-provider process --build-helper /path/to/library-build.mjs \
  --home /path/to/moonbit --sdk /path/to/morphir-sdk
```

The npm package includes `build-provider/library-build.mjs`. `--build-node` selects
the Node executable and `--timeout` bounds the process lease in milliseconds.
Equivalent root configuration uses `pipeline.build_provider`, `build_helper`,
`compiler_home`, `sdk`, `build_node` and `build_timeout`. Reports distinguish
`generated` projects, `validated` projects with Ion receipts, and `published`
destinations. JSON retains `committed` destinations for compatibility and adds
`publicationDetails`. Source-only replacement removes old receipts.

Required builds use a private workspace and frozen supplied dependencies. The
provider identifies compiler binaries, matching core, supplied SDK, generated
source and fresh compiler outputs in `build-receipt.ionb`. Every required project
must build and dispose its lease before the publisher takes its lock. A compiler
failure, deadline or cleanup failure preserves previous task output. Generation
does not install a compiler or fetch dependencies, and failed builds never switch
to source-only mode.

The current backend supports concrete nongeneric libraries, including pricing
functions, records, aliases/custom types and audited SDK adapters. See
[generator scope and acceptance](../../pkgs/morphir-moonbit/README.md).

`--component json-identity` inserts a declared Morphir JSON compatibility step.
Repeat `--component` for a sequence of registered components. Dry-run and result
reports list component transports and metadata policies while the engine and
checkpoint formats retain their independent defaults.

## Evaluate model functions and Scheme worksheets

These commands complete in a terminal without a browser, display, Workbench
server or frontend assets. Local function evaluation uses the shared portable
Scheme evaluator. It does not start or download a provider.

```sh
morphir eval model.json --suite calls.json --json
morphir eval model.yaml --suite calls.ion --suite-format ion-text \
  --checking-policy permissive --provider scheme --json-lines
cat model.json | morphir eval - --model-format json --suite calls.json --json
morphir worksheet worksheet.scm --json
cat worksheet.scm | morphir worksheet - --source-id example --source-revision 1 --json-lines
```

`eval` accepts the existing `morphir-invocations-v1` suite, with ordered calls,
public entry names and tagged arguments. For example:

```json
{"profile":"morphir-invocations-v1","calls":[{"id":"answer","entry":"example:main#answer","arguments":[]}]}
```

A function invocation is one call inside an evaluation. The suite codec is
selected independently with `--suite-format json|ion-text|ion-binary` and
defaults to JSON. Model formats are JSON, YAML, Ion text and Ion binary.
`--model-format` overrides extension selection; `.yaml` and `.yml` both select
YAML. Stdin requires an explicit model format, and only one input can consume
stdin. Model normalization keeps the codec separate from source language,
generation backend and logical model identity. `--unit-id` supplies a logical
identity for raw IR; a rich checkpoint retains its envelope's identity.

`--checking-policy strict`, the default, checks the whole model before running.
`--checking-policy permissive` checks supported behavior as code executes, so an
unreached unsupported operation can remain in the model. Both policies enforce
the selected public input/output boundaries, model integrity and resource
limits. An unsupported selected provider or policy is an error. There is no
implicit provider fallback.

Evaluation JSON contains canonical `terminalOutcomes` with returned tagged
values, model errors, failures or cancellation. Integers and decimals retain
their exact representations; floating values retain their bits. `boundary`
describes the captured public entry types. A planning refusal has a separate
`failure` with its stage and domain code. JSON-lines emits each `call` followed
by a `result`, or an `error` record for a planning refusal.

`worksheet` uses the same source-mapped processor as the Workbench. Definitions
are shared within one worksheet run. Ordered observations retain exact UTF-16
source ranges, expressions and typed results. Runtime failure retains its
completed prefix. Empty input succeeds with no observations. JSON-lines emits
`observation` records followed by the canonical report in a `result` record.

Both commands accept `--timeout` in milliseconds, from 1 through 600000, with
default 120000, and `--cancel-file`. Creating the selected cancellation file or
sending SIGINT requests cancellation. A returned model error, runtime failure
or timeout exits 1; invalid invocation or input exits 2; cancellation exits 130;
successful evaluation exits 0. Model errors remain typed outcomes, separate
from infrastructure failures and ordinary returned `Result.Err` values.

The installed Node launcher handles SIGINT while evaluation runs in an owned
worker. Native execution uses the host interruption adapter. The supplied
Wasm GC runner also supports evaluation and worksheets through its explicit
host bridge. WASI retains help and refuses evaluation and worksheet execution
with an explicit unavailable-interruption error before reading their input.

Evaluation and worksheets produce reports. Use `generate` to generate from an
existing model, or `run` to compile project sources and publish their outputs.

## Inspect models and save captured originals

```sh
morphir model inspect model.yaml --json
morphir model inspect path/to/yaml-tree --json
morphir model export-original model.ionb --output saved --json
cat model.yaml | morphir model export-original - --model-format yaml \
  --filename model.yaml --output saved --json
```

Inspection reports normalized IR separately from the captured source format
version and labels it `normalized-ir`. Single files retain their basename and
exact bytes, including BOM, CRLF, comments and binary Ion. YAML directory inputs
retain their relative file paths, opaque sidecars and explicit empty directories.
Stdin requires `--filename` for a portable captured name. Inspection and exact
original export support JSON, YAML, Ion text and Ion binary on native, Node and
the supplied WASI/Wasm GC runners. WASI file and directory paths are relative
to its preopened current directory. Input capture enforces finite byte, entry,
depth and path limits and refuses symbolic links.
Native Windows directory enumeration also follows the host's
[Win32 path-length limit](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-findfirstfilew).
A deep input can therefore report `directory.open_failed` before reaching the
application's depth cap. The Windows Node CLI exercises the shared original-path
depth bound.

Export publishes the captured inventory under `<output>/originals/` through the
shared transactional publisher. An existing originals directory requires
`--overwrite`. Failed staging or replacement preserves the previous publication.
The output directory must be inside the current workspace and must pass the
host's path confinement checks. A normalized semantic projection cannot be saved
as an exact original.

## Generate from retained models

```sh
morphir generate model.yaml --output generated --json
morphir generate checkpoint.ion --target moonbit --output generated --json
morphir generate model.json --target elm --output generated --json
```

`generate` reads JSON, YAML, Ion text and Ion binary through the shared model
decoder. It reuses engine generation, build validation and transactional
publication. Rich checkpoints and MEP model envelopes retain their logical unit
identity and supported source context in binary sidecars. A target that cannot
preserve required context refuses with `data.lossy_conversion`.

Generation publishes source artifacts. `--validation required` additionally
requires an explicitly selected build provider and a successful build receipt
before replacement. Use `execute` or `verify` to invoke generated libraries.
Default execution logs are written to `.morphir/logs/execution.ionb`; select a
different sink with `--log-file` and `--log-format ion-binary|json-lines`.
Unavailable host effects refuse before publication on portable targets.

## Execute and verify generated libraries

`execute` runs public entries with supported typed boundaries in an E1-generated library. `verify` also
compares each result with the local Scheme evaluator and exits with status 1 on
any mismatch. Select `--target js` (default), `wasm-gc`, `native` (C), or `llvm`.
Native and Node CLI hosts supervise the selected driver using an explicitly
supplied Node helper. The provider probes compile/run capabilities before the
engine plans the calls; missing required targets fail without substitution or
acquisition. Native execution currently uses the POSIX compiler/linker contract
on macOS/Linux. Windows can run JS and Wasm GC; native Windows execution is not
yet advertised by this provider.

The supervisor reclaims descendants on normal parent exit as well as on
cancellation, deadline and diagnostic overflow. POSIX hosts use an owned process
group and check that no live group members remain. Windows uses a private Job
Object worker with Windows PowerShell 5.1. The root executable joins the job
while suspended, before its code runs; breakaway is disabled. The worker stops
the job if its Node owner exits and checks the active-process count before
writing a completion receipt. An absent receipt or unconfirmed termination
produces a cleanup failure, so the execution host retains its lease for recovery.
This manages ordinary process descendants; it is not an OS sandbox. Windows
launches executable files directly and does not invoke `.cmd` or `.bat` scripts.
Run `mise run test:supervision` to exercise this lifecycle. CI runs the same gate
on Linux, macOS and Windows.

```sh
morphir verify model.json --suite calls.ion \
  --execution-helper /path/to/@morphir/morphir/build-provider/execution.mjs \
  --home /path/to/pinned/moon-home \
  --dependency finos/morphir-sdk=/path/to/morphir-sdk \
  --dependency finos/morphir-execution=/path/to/morphir-execution \
  --dependency moonrockz/ion=/path/to/ion \
  --dependency moonbitlang/x=/path/to/x \
  --dependency moonbitlang/async=/path/to/async \
  --log-file execution.ionb --json
```

Supply SDK and execution protocol 0.1.0, Ion 0.5.0, x 0.5.5 and async 0.22.4.
The default compiler/core pin is `0.10.16+b1a0e846e`; the C lane forces
`MOONBIT_NEW_NATIVE=0`. Preparation copies and hashes
these explicit dependencies into a frozen workspace; it does not fetch packages.
The driver imports public generated exports and applies their curried arguments
in order. Argument values arrive at runtime through binary Ion files. A process
session can invoke the same executable repeatedly before disposal.

Model JSON remains supported. Select `--model-format morphir-json`, `ion-text`, or
`ion-binary` explicitly, or use `.json`, `.ion`, `.ionb`/`.10n` suffix detection.
For an Ion model, `--unit-id` must match its envelope identity; the default is
`model`. Suite formats are `ion-text`, `ion-binary`, and `json`, selected with
`--suite-format` or the same suffix rules. See the
[invocation profile](../../pkgs/morphir-execution/README.md) for its schema.

`--dry-run` validates the model, public signatures and suite without acquiring a
provider, compiling, publishing, or writing a log file. `--json` emits one result;
`--json-lines` uses the existing CLI event framing. Logs never enter stdout.
Dry-run capability verification is explicitly deferred; an LLVM dry run requires
a declared toolchain pin, while actual execution probes and checks its local
compiler/core/runtime identities before planning.
`execute` and `verify` leave existing generation output untouched. Their execution
workspaces are disposed after calls and evaluator comparisons, including failure.

`--log` selects `.morphir/logs/execution.ionb` beneath cwd. An explicit
`--log-file` overrides that path. File logs default to binary Ion. `--log-format ion-text`, `json-lines`
and `text` are available. The local adapter retains up to 2,048 observations and
three previous log files. Binary logs include a final bounded stage-metrics record;
duration buckets have upper bounds 0.001, 0.01, 0.1, 1, 10 and 60 seconds, followed
by an overflow bucket. Sink failures and dropped records produce stderr warnings
without changing execution results. Payload capture and network export are not
enabled. Hosts can supply their own observer, clock, sink and lifecycle policy.

Scheme comparison has finite evaluation limits and disables runtime accelerators.
It shares SDK implementations with generated code, so it does not establish
independent SDK conformance. The tests also assert independently chosen expected
values. LLVM scalar execution is verified separately on macOS arm64 with
`0.10.15+1e9f6672d-nightly` and its matching LLVM core bundle. Other LLVM hosts
are explicitly unavailable until verified. Upstream Rust evaluator coverage, full failure supervision, verification publication
and native OpenTelemetry collector integration remain open E2 gates. Rich values
are supported by the pricing slice described below.

Run the scalar CLI acceptance with:

```sh
mise exec -- bun install --frozen-lockfile
mise exec -- bun run build:runtimes
mise run setup:core
MOON_HOME=/path/to/pinned/moon-home mise exec -- node apps/morphir/scripts/test-execution.ts
```

The ordinary stable provider uses the toolchain's own core and verifies its source
bytes against `tools/moonbit-core-pin.json`. A set `MOON_CORE_OVERRIDE` is rejected.

For the LLVM lane, prepare an isolated compiler/core installation, bundle its
LLVM core, and supply `--home` and `--toolchain-pin`. The explicit JSON pin
profile `morphir-toolchain-pin-v1` contains `compilerVersion`, SHA-256
`compilerIdentity`/`coreIdentity`, `platform`, `arch`, `targets: ["llvm"]`, and
`acquisition` with `compilerUrl`, `coreUrl`, `compilerArchiveIdentity` and
`coreArchiveIdentity`. Preserve and verify the acquired archives yourself;
provider helpers never acquire tooling. Generate the pin from prepared local
files with `build-provider/toolchain-pin.mjs <home> <acquisition.json>`.
Keep this home separate from the default installed compiler. LLVM pins select
only `llvm`; pins for JS, Wasm GC or native C must use the stable compiler version.
Mixed stable/nightly target sets and duplicate targets are rejected.

Execution receipts identify source, driver, configured driver, manifest, build,
executable, compiler, core and runtime independently. Native receipts include the
selected C compiler/linker, runtime objects and linked libraries. macOS libraries
in the system shared cache are identified by the OS version rather than a
nonexistent standalone file. Wasm GC uses the packaged, hashed Node runner and
its narrow `morphir_execution_v1` import ABI; unknown imports fail. Runtime and
executable identities are rechecked when invoking.

Trace propagation uses bounded W3C version-00 context, separate from semantic
suite and source identity. The driver validates and echoes the context in its Ion
outcome envelope. Completed call observations correlate target, lease, call and
attempt, with durations measured on the driver's own monotonic clock. Repeated
invocations need distinct, ordered attempts. `--telemetry-adapter local` is the
default; `none` disables logging. An unavailable explicitly named adapter fails
selection. No OpenTelemetry package is imported by portable engine/driver code.

To include the verified LLVM lane in the scalar acceptance gate, set both
`MORPHIR_LLVM_HOME` and `MORPHIR_LLVM_PIN` alongside `MOON_HOME`. The gate runs
selected targets through native, Node and installed npm CLI hosts, and reports
LLVM as not selected when those variables are absent. Task 6 will establish the
required debug/release CI matrix; this optional local gate does not claim it.

Execution defaults to `--build-mode debug`; `--build-mode release` builds and locates
the optimized executable and records its mode. `--comparison exact` is the default.
Use `--comparison approximate --absolute-tolerance 0.000001 --relative-tolerance 0`
to select a tolerance explicitly. Tolerances without approximate selection are
rejected, and signed zero/non-finite bits remain exact under either policy.

The checked-in [pricing suite](../../pkgs/morphir-moonbit/fixtures/execution/pricing-suite.ion)
exercises 32 rich calls. `mise run test:compiler` runs it in debug and release on
available JS, Wasm GC and native targets, plus explicitly supplied LLVM. Its reports
state the shared-SDK Scheme conformance profile. It also verifies Ion extension
round trips, enumerated model errors, typed rejections, and telemetry isolation.
Embedding hosts can opt into redacted payload capture separately from the logging
observer; the CLI leaves capture disabled. Local metric dimensions are capped at
128 series, with overflow counts and no entry/correlation identifiers as labels.


Execution failures now produce a structured unsuccessful report with exactly one
terminal status for each required call. Reports retain valid actual outcomes,
expected values, the first mismatch as a JSON Pointer, and separate bounded
primary/cleanup diagnostics. Model mismatches and runtime failures exit with 1;
planning/configuration errors still exit with 2. An embedding caller can use
`run_report`; the existing `run` API still raises typed provider/cleanup errors.

`--cancel-file /absolute/path/to/marker` cancels when that marker exists. The
process provider checks it between stages and polls it while a command runs.
POSIX commands own process groups; cancellation/deadlines terminate descendants
and wait for command closure before deleting execution scratch. Process
diagnostics are capped at 1 MiB. Failed process sessions are poisoned against
reuse, and disposed handles reject build/invoke calls.

Hosts can explicitly call `verify_and_publish` with a required target matrix,
evaluator and byte publisher. It verifies every target, finishes all execution
cleanup, then publishes generated sources and native Ion verification evidence in
one task transaction. The default CLI commands remain publication-free. Failed
verification never acquires the publication lock.

Local log flush runs in a separate worker with a 1-second allowance, a 4 MiB
encoded limit and three-file rotation. Nonregular destinations are rejected.
Failed flushes count undelivered records without replacing the execution result.
Full exporter-drain integration and the remaining lifecycle fault matrix are
still being completed in E2 Task 4.

## Independent semantic conformance

`conform` runs generated code once and compares each call separately against
versioned independent expectations and configured live evaluators. It uses
exact comparison. The default lanes are independent expectations, required
live Scheme, and optional Rust. Unavailable or unsupported Rust coverage has
`matches: null`; it never counts as a successful comparison. Scheme shares SDK
code with generated execution, which is recorded in its evidence profile.

```sh
morphir conform model.json --cases cases.ion \
  --execution-helper /path/to/build-provider/execution.mjs --home /pinned/moon-home \
  --dependency finos/morphir-sdk=/path/to/sdk \
  --dependency finos/morphir-execution=/path/to/execution \
  --dependency moonrockz/ion=/path/to/ion \
  --dependency moonbitlang/x=/path/to/x \
  --dependency moonbitlang/async=/path/to/async \
  --receipt conformance.ionb --json
```

`--cases-format` accepts `ion-text`, `ion-binary`, or explicit `json`. Receipts
default to binary Ion and retain native rich values; `--receipt-format ion-text`
or `json` selects an explicit alternative. Dry runs validate model/case and
required evaluator compatibility without building or evaluating. Missing
required coverage exits 2; a comparison disagreement or evaluator failure exits
1 and retains the call ID and mismatch path. Cancellation exits 130 and
remains explicit in the execution and evaluator coverage receipts. Execution does not publish generated
sources. Logging keeps the existing separate stderr/file contract.

Add `--rust-evaluator <binary> --rust-evaluator-pin <pin.json> --rust-helper
<build-provider/evaluator.mjs> --require-evaluator rust` to require the Rust
lane. `--evaluators scheme,rust` selects live lanes. Independent expectations
always run. See the [fixture provenance and Rust pin instructions](../../pkgs/morphir-moonbit/fixtures/execution/conformance.md).

Run `MOON_HOME=/pinned/home mise run test:conformance` for the portable local gate.
Optional `MORPHIR_LLVM_HOME`/`MORPHIR_LLVM_PIN` selects the isolated LLVM toolchain;
`MORPHIR_RUST_EVALUATOR`/`MORPHIR_RUST_EVALUATOR_PIN` selects a local pinned Rust
binary. Each pair is mandatory when selected. `MORPHIR_CONFORMANCE_RECEIPTS`
retains native Ion receipts, explicit JSON projections and separate coverage
summaries. CI reports Rust as unavailable unless its own binary/pin is supplied;
local Rust evidence does not imply Rust CI parity.

## Installed lifecycle acceptance

`mise run test:installed-lifecycle` packs and installs the actual npm CLI, then
runs it from an empty directory outside the checkout. Compiler/core and absolute
local dependency paths are supplied explicitly; execution, evaluator, telemetry,
Wasm GC and process helpers come from the installed package. The 23 independent
cases run from standard Morphir JSON, Ion text and Ion binary models in debug and
release. JSON, JSON Lines, human and dry-run output are checked alongside lease
disposal, local logs and a deliberate expectation mismatch.

The same installed gate compiles a `moonbit-model-stable-v1` source project through
the explicit frontend and `json-identity` component into a default binary Ion
checkpoint. Four independently authored truth-table rows are checked against
compiler-built original source, Scheme and generated execution on every selected
target in debug and release. It retains source text, origins, generated symbols,
conformance receipts and package/compiler/dependency/runtime identities under
`moonbit-source/`. Paired disabled telemetry and failed optional sinks must keep
outcomes and semantic identities unchanged. Missing required targets fail the gate.

The installed gate also selects `moonbit-model-stable-v1` explicitly and
processes the six hand-authored library fixtures through the same JSON component
and Ion checkpoint boundary. Its 13 public entries cover 42 exhaustive Boolean
rows per target and mode. Original MoonBit, the independent evaluator, Scheme
and generated execution must agree. Separate compiler consumers check that
private helpers stay private in both original and generated libraries, including
the all-private fixture. Library receipts are retained under `moonbit-library/`.

A stable String library then exercises every stable String type, operator and
call: concatenation, equality, shortlex ordering, UTF-16 `length()`, owned slices
and the pinned `is_empty`, `contains`, `has_prefix` and `has_suffix` predicates.
Its 39 hand-authored rows cover empty, supplementary and combining text, split
surrogates, negative and Int32-extreme indexes, malformed UTF-16 and the
1,048,576-unit bound. The original compiler checks the 34 rows that source can
spell, and the independent evaluator, Scheme and generated execution check all
39 on every required target in debug and release. The gate also checks Ion text
replay with an unknown provenance fact, lossy JSON refusal, rejected source that
keeps the published checkpoint, private-entry refusal, cancellation and a
deliberate mismatch. `--string-only` runs this part alone. Receipts and a
`summary.json` evidence matrix are retained under `moonbit-string/`.

The numeric gate qualifies the experimental `moonbit-model-experimental-v1`
numeric and Decimal capabilities without promoting them. It compiles seven
source libraries with the packed CLI: Int32 boundaries and wrapping, fixed-width
and big integers, Float and Double carriers, math functions, Integer/Double
conversions and Decimal calculations. Their 80 public entries have 178
hand-authored rows. On every required target in debug and release, 164 exact rows
go through `conform` against the independent evaluator and Scheme. The other 14
rows use `execute` and an authored bound: 4 ULP for 5 math rows, or a NaN or
infinity category. Scheme checks all 178 rows on the installed checkpoint. One
consumer workspace compiles the original sources and the installed-generated
wrappers; it runs 356 assertions on native, JS, Wasm and Wasm GC in debug and
release. The gate also decodes the primary Ion receipts, checks generated
visibility and replays Ion text, an unknown metadata fact and a JSON receipt with
exact values. Lossy checkpoint JSON is refused. Rejected sources keep the
published checkpoint: the stable channel, an unsupported function, literal
overflow, a missing error annotation and the function budget. The gate also checks
wrongly typed input, a missing SDK dependency, the 4096 digit Integer budget,
cancellation, a deliberate Decimal mismatch and default and explicit log paths.
`--numeric-only` or `MORPHIR_INSTALLED_SCOPE=numeric` runs this part alone. CI
runs it as a separate job beside `MORPHIR_INSTALLED_SCOPE=lifecycle`. Receipts
and `summary.json` are retained under `moonbit-numeric/`.

Library checks include lazy planning, explicit profile selection, preservation
of published output after rejected source or lossy JSON export, optional logging
under `.morphir/logs/`, explicit log paths, failed sinks, stdout framing, execution
lease disposal and deliberate mismatches. These receipts report local acceptance;
they do not certify MCK verification or extension installation.

```sh
MOON_HOME=/pinned/stable/home \
MORPHIR_REQUIRED_TARGETS=js,wasm-gc,native \
MORPHIR_INSTALLED_RECEIPTS=.dev/installed-receipts \
mise run test:installed-lifecycle
```

A required target fails when its capability is missing; it is never silently
skipped. CI requires JS, Wasm GC and native C on Linux/x64 and macOS/arm64. The
macOS job also requires LLVM debug/release using separate compiler/core archives
pinned to `0.10.15+1e9f6672d-nightly`. `mise run setup:llvm` explicitly acquires
those hash-checked, versioned archives into a **new isolated directory**, bundles
LLVM core and writes a pin. Use `MORPHIR_LLVM_HOME` and `MORPHIR_LLVM_PIN` for both
setup and acceptance, and include `llvm` in `MORPHIR_REQUIRED_TARGETS`. This
supports darwin/arm64; required LLVM on another host fails. It does not replace
the stable default. Archive unavailability or changed hashes fail setup; there
is no substitution with a newer nightly.

Local logging still defaults to binary Ion when `--log-file` is supplied.
`--log-file @stderr --log-format text` provides bounded stderr text while stdout
remains result output. `@stderr` also accepts explicit JSON Lines; binary Ion and
Ion text require a file path. Log delivery remains optional health.

The explicit `opentelemetry-native` adapter is described in the
[native adapter guide](../morphir-otel/README.md). It requires a supplied native
binary, pin, packaged helper and endpoint. The CLI never enables outbound
telemetry implicitly. Collector/capture tests and overhead baselines run in
separate CI jobs and retain their own receipts.

## Naming recovery diagnostics

MoonBit source compilation emits readable Morphir entry IDs and warns when source
spellings normalize to the same identity. Compilation continues with checked,
traceable names by default. Warnings show the original spellings, allocated names,
related source spans and a suggested rename. The generator's current target
encoding remains separate from the frontend identity policy.

Human output sends warnings to stderr. `--json` includes a `warnings` array with
codes, severity, fixes and related locations; `--json-lines` emits `warning`
records. Optional logs are not required. Ion checkpoints preserve diagnostic
provenance, and replay reports each owning allocation once per source run.

To fail on recoverable naming warnings before publication:

```toml
[pipeline]
strict_naming = true
```

New-source entry IDs change from `#source-<hex>` to readable canonical names.
Use the returned public entry list when constructing invocation suites. Loading an
existing checkpoint keeps its entry IDs unchanged.

### Declared naming providers

The engine exposes project-scoped metadata-provider binding to embedding hosts.
`[metadata] provider = "shared-local-restore"` describes an explicit service request
and is validated with configuration provenance. The CLI binds that service when
the host supplies an explicit matching grant as described below. Configuration
alone cannot grant authentication or install host callbacks. Ordinary naming
and projects without relevant facts continue to work. See the
[engine host contract](../../pkgs/morphir-engine/README.md#project-scoped-metadata-providers).

## Authenticated metadata provider

`run --metadata-grants /host/grants.ion` explicitly enables the shared restore
provider selected in project configuration. Nothing discovers a grant file,
installs a service or initializes trust. A disabled provider keeps the existing
unavailable behavior; a grant file alone does not enable it. The selected policy, complete lock,
registry and already provisioned trust-state directory must each match a grant
for that exact workspace/project. The registry release is authority-qualified;
the native IR package is independently checked as `morphir/naming`.

```toml
[metadata]
provider = "shared-local-restore"
service = "/tools/morphir-provider-snapshot"
policy = "/trust/policy.json"
lock = "morphir.lock"
registry = "/registry/local"
state = "/trust/state"
assurance = "portable"

[metadata.naming]
release = "example.com/morphir/naming@1.0.0"
```

Selections resolve relative to their own configuration file. CLI-origin paths
resolve from the invocation directory. Relative environment or unknown-origin
selections refuse rather than guessing a base. Grant paths resolve from the
explicitly supplied grant file. For example, a workspace with member `one` uses:

```ion
{
  profile: "morphir-metadata-host-grants-v1",
  workspace: "/work/example",
  runtime: {
    node: "/tools/node", nodeSha256: "sha256:<raw digest>",
    helper: "/tools/morphir/build-provider/metadata.mjs",
    helperBundleSha256: "sha256:<bundle digest>"
  },
  projects: [{
    project: "one",
    service: "/tools/morphir-provider-snapshot",
    serviceSha256: "sha256:<raw digest>",
    policy: "/trust/policy.json", lock: "/work/example/one/morphir.lock",
    registry: "/registry/local", state: "/trust/state"
  }]
}
```

Replace the placeholders with independently accepted pins from the qualified
installation. The helper bundle pin hashes the compact JSON array of
`[filename, raw-SHA256]` pairs for `WindowsJob.cs`, `metadata.mjs`,
`supervision.mjs`, `windows-job.mjs`, `windows-job.ps1`, in that order. Embeddings
can calculate it with `host.metadata_helper_bundle_sha256`. Node/service pins
hash original regular-file bytes, with a 512 MiB identity-read limit.

Grant documents are closed and capped at 1 MiB, with at most 128 project entries.
Use `.ion` for Ion text, `.ionb` for binary Ion or `.json` for an explicit JSON
opt-out. The process exchange always uses binary Ion, retaining supported native
JSON artifacts as exact blobs. Small JSON bridge receipts contain control data
only. A frame or a saved receipt never grants fresh authority.

Sessions acquire only when metadata is requested during execution. Each fresh
operation probes the accepted service and replays authentication. The host pins
its executable/runtime, bounds responses and waits for process-tree quiescence
before disposing scratch and publishing output. Unknown termination retains
scratch and refuses publication. Shared trust-state updates remain owned by the
restore component, including when later generation refuses.

`--metadata-timeout` sets one project operation budget, including probe and
cleanup, from 6001 through 600000 milliseconds; the default is 120000.
`--cancel-file PATH` cancels a run when that path exists. Dry runs acquire no
provider. The process composition currently supports qualified native and Node
JS hosts; Wasm and WasmGC refuse it explicitly. Pure binary wire support remains
available on all four targets. The shared profile is `local-library-mvp` /
`0.1.0-draft.1`, with its portable filesystem assumptions.

Provider lifecycle events join existing frontend observations. `--log` defaults
to `.morphir/logs/frontend.ionb`; `--log-file PATH` honors an explicit destination,
including outside that directory. Observations contain operation/project IDs,
profile, result and duration. Ordinary logs exclude policy/lock bodies, native
provider payloads and contexts. Installed cross-platform signed-provider
qualification is tracked separately from these host and wire contracts.

See the [provider operations guide](../../docs/PROVIDER_OPERATIONS.md) for identity
preparation, test-only trust provisioning, audit inspection, refusal handling and
the installed qualification gate.

## Connected execution sessions

`connected` selects the qualified `workbench-http` execution binding. It uses the
existing authenticated Workbench gateway backed by a Rust connected session.
The gateway must advertise the exact supported Workbench execution profile.
The Rust connected v1 manifest or an unauthenticated standalone gateway alone
does not offer this service. The command needs no browser, frontend assets or
browser cookie store.

Save the gateway's single-use launch URL in an owner-only file, then exchange it
into a new connection file. Keep tokens and cookies out of command arguments:

```sh
morphir connected connect launch.txt --provider workbench-http \
  --connection connection.json --json
morphir connected run request.json --provider workbench-http \
  --connection connection.json --timeout 120000 --json
```

The connection file is created exclusively with owner-only permissions. An
existing destination refuses before consuming the launch token. Each run freshly
authenticates and checks the pinned session and execution offer. A replaced host,
changed authority, unsupported profile or unreadable private file refuses before
submission. This connection file stores session credentials; it is separate from
execution state and must not be committed. Delete it when its session is no
longer needed. Native callers select the maintained installed Node helper with
`--connected-helper PATH` and, when needed, `--node PATH`. The installed Node
launcher selects its adjacent helper automatically.

The bounded request file, or `-` for bounded stdin, captures `source`, `entry` and
exactly one of `arguments` or `argumentsIon`. `source` is the supported JSON IR
text. Arguments use the existing typed invocation values. A qualified policy
mapping additionally accepts the existing `admission` object and
`executionMode: "capability"`; it never downgrades to another mapping.

A run owns one submission, its query loop and terminal release. Socket reconnect
reauthenticates and observes that same retained identity once. A lost submission
reply reports `submission-unknown` and submits no replacement. SIGINT,
`--cancel-file PATH` or the command timeout requests cancellation; only a received
terminal receipt proves the outcome. Cancellation acknowledgement does not prove
termination. If replies remain unavailable, output retains the known identity
with `observation-stopped`, no invented terminal result and honest release state.
A value returned before cancellation remains that value. Lost release replies
are reconciled only after fresh authentication and exact offer validation.

JSON output includes the validated execution view, typed terminal outcomes when
known, cancellation acknowledgement and release state. JSON-lines wraps that
report as a `result` record. Exit 0 means returned outcomes and confirmed release,
130 means confirmed user cancellation or stopping before submission on user request,
1 means failed,
unknown or incomplete execution/cleanup, and 2 means refused setup or input.
Execution state is held only for the current command; no process-restart recovery
or implicit resubmission is provided. CLI interruption closes its own transport
and helper and never terminates the remote host.

Connected host effects require Node and POSIX private credential-file support. Portable
Wasm/Wasm-GC retain pure receipt/core and help support and refuse connected effects
explicitly. Windows private credential-file protection is not qualified by this
binding and refuses explicitly. Installed packaging and platform qualification
remain separate from the authenticated host protocol.

`connected originals` discovers and downloads complete declared model originals
using a separately selected `--connection-scope models` connection. It requests
original bytes with semantic conversion disabled, verifies the whole inventory,
and publishes to the explicit destination only after acknowledged release.
See [connected model originals](docs/connected-transfers.md#connected-model-originals)
for source/project selection, commands, bounds and qualification scope.
