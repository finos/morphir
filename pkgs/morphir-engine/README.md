# Morphir Engine

A portable engine for transforming a file, directory, project or workspace:

```text
Host files → frontend → current Morphir IR → Scheme transforms → backend → artifacts
```

The engine handles discovery, manifests, configuration and diagnostics. The host
owns I/O. Its synchronous `read`, `exists` and recursive `list` callbacks can read
an editor snapshot, a filesystem or a cache populated by asynchronous I/O.
The engine returns artifacts; the caller chooses how to persist or publish them.

## Run the example

From the repository root:

```sh
mise exec -- moon run pkgs/morphir-engine/examples --target native
# Also supported: --target js, --target wasm, --target wasm-gc
```

This runs a project from a memory host, applies its configuration, emits an IR
artifact and executes its `main` entry. The [CLI](../../apps/morphir/README.md)
exposes workspace discovery and pipeline execution through the [host adapters](../morphir-host/README.md).

## TOML workspaces and execution plans

`config` wraps `moonbit-community/toml` with semantic encoding, deep merge,
environment mapping and provenance. `workspace` discovers canonical Morphir layouts,
expands member globs and selects by name or path. It accepts the protocol-v1 request
shape through `discover_request`; the supported TOML success snapshots are tested
against vendored upstream fixtures. YAML candidates produce explicit diagnostics.
Malformed members have error state and do not prevent selecting a valid sibling.

`Engine::list_projects` resolves effective frontend and target choices through the
same configuration resolver used by planning, including workspace and member scripts.
It returns `ProjectInfo` entries with per-project errors, accepts an optional final
script and host runtime bindings, and does not enumerate or read sources. Backend
identifiers are target names. Unknown compiler names can be listed without registering
them in the engine.
Listing shares IR configuration validation with planning and raises cancellation
instead of turning it into a per-project error.

`Engine::plan` resolves project settings, evaluates configuration scripts, validates
registered frontends/backends and fixes source paths and output destinations.
`Engine::execute` runs that plan once against a source snapshot and returns a report.
Prepare a fresh plan for each execution so Scheme closure state never leaks across runs.
An embedding host can pass `bind_runtime` to `Engine::plan` or `Engine::run` to
register native procedures in each isolated project session before scripts run.
The callback receives the project runtime; it can use the Morphir Scheme backend's
`register_external`, `register_native`, and `register_accelerator` APIs.
`morphir-host` prepares snapshots and publishes reports through explicit capabilities.
See its README for the complete embedding sequence.

A source belongs to its most specific discovered project. Parent projects exclude
nested members, and explicit file/directory selections cannot cross that ownership.

Workspace outputs live under `<out_dir>/<member-path>/compile.dest/`. Each input
still produces its own distribution. Scheme configuration `output` adds a subtree
inside that task destination. Project module prefixes and exposed modules apply
before IR transformations. Explicit CLI options take precedence over scripts.

IR JSON output can request versions 1 through 4. The existing migration codecs
refuse lossy conversions. For example, Scheme output with absent member documentation
cannot be converted to a classic encoding that requires documentation text; this
produces a diagnostic and prevents publication.

## Legacy embedding API

Declare `finos/morphir-engine@0.1.0` in your module and import it as `engine`.

```moonbit
let host = @engine.Host::memory(Map::from_array([
  ("demo/morphir.json", "{\"name\":\"demo\",\"sourceDirectory\":\"src\"}"),
  ("demo/src/main.scm", "(* 6 7)"),
]))
let engine = @engine.Engine::new()
let report = engine.run(host, @engine.Project("demo"))
// report.artifacts[0].path == "demo/dist/main.ir.json"
```

`Report` contains `artifacts`, `diagnostics` and `processed` (successful artifact
count). `successful()` means no diagnostics. Diagnostics identify the path,
stage and error detail. A failed file produces no artifact; other files continue.
Output collisions produce a diagnostic and retain only the first artifact.
Check the whole report before publishing. The host runner refuses publication when
any selected transformation fails.

| Input | Discovery |
| --- | --- |
| `File(path)` | One file, regardless of extension; parent directory supplies config |
| `Directory(root)` | Recursively listed files matching the selected frontend extensions |
| `Project(root)` | `morphir.json` supplies `name` and `sourceDirectory` (defaults: `user`, `src`) |
| `Workspace(root)` | `morphir-workspace.json` lists project directories in `projects` |

For this legacy API, project manifests must exist. It uses their name and source directory;
it does not implement Elm `exposedModules`, dependency resolution or cross-file
linking. Each source yields a separate IR distribution/artifact. A Scheme module's
name comes from its source-relative path without the final extension. Nested source
paths are retained in output paths. References to other implementations can be
resolved by loading them together in a Scheme runtime.

Workspace manifest:

```json
{"projects": ["packages/orders", "packages/pricing"]}
```

Workspace project order is retained; files within each project are sorted and
deduplicated. Duplicate project entries are ignored. Configuration and manifest
files at the project root, plus the output subtree, are excluded from discovery.

## Script configuration

Place `morphir.config.scm` at the workspace/project/directory root, or pass a script
as the `config` argument to `run`:

```scheme
(pipeline
  (frontend "scheme")
  (backend "ir-json")
  (output "generated")
  (transform
    (lambda (file)
      (ir-rewrite-file file
        (lambda (node)
          (if (ir-integer? node)
              (ir-with-integer node (+ (ir-integer node) 2))
              node))))))
```

Options: `frontend`, `frontend-provider`, `frontend-profile`, `backend`, `output`, `source`, `package-name`,
`inference` and `transform`. `run` refuses an `inference` other than `"off"`, because the inference stage needs the
planned pipeline (`Engine::plan`).
Defaults are Scheme → IR JSON, output `dist`, package `user`, and the input directory
as source (project manifests default to `src`). `source` applies to discovery,
not explicit `File` inputs. Output paths are relative to the input/project root.

Precedence is manifest → workspace script → project script → explicit script.
Scalar options override earlier values; transforms accumulate and execute in order.
Each script returns a `pipeline` list of option records. Scripts can define helpers
and use the [Scheme IR bridge](../morphir-scheme/README.md#transform-scripts).
Each transform accepts and returns a typed IR file. During transforms, `source-path`
and `project-root` are strings in the script session.

Every project/run gets a fresh runtime. Within a project, configuration closures
and their state are shared across files in discovery order. Evaluation budgets
apply to each script and each transform; frame allocation is bounded across the
session. A workspace configuration is evaluated separately for each project.

## Frontends and backends

Built-in frontends:

- `scheme`: `.scm` and `.ss`, structural Scheme → current IR.
- `ir-json`: `.json`, versioned IR JSON → current IR using existing migrations.

Built-in backends:

- `ir-json`: current IR JSON, suffix `.ir.json`.
- `scheme`: executable Scheme, suffix `.scm`; requires the Morphir Scheme runtime.

`register_frontend(name, extensions, compile)` accepts `Source -> IRFile`.
`Source` includes path, source-relative path, content, package name and module name.
`register_backend(name, extension, emit)` accepts `IRFile -> String`.
Registrations replace the same name and share the standard transform/diagnostic flow.
All frontends and transforms operate on the current unversioned IR model.

### Rich source frontends

`register_unit_frontend(name, extensions, compile, profile?, dependencies?, limits?)`
accepts `(Source, unit_id, cancelled) -> data.IRUnit`. The engine supplies canonical
package/module names, a source-relative logical ID and the execution cancellation
callback. Source paths and content retain their original spelling. Each file is an
independent unit; the hook does not imply linking or dependency acquisition.

Registrations reject conflicting names and copy extensions/dependency descriptors.
Plans capture the callback and limits. `Plan::source_frontends()` reports the selected
source, unit ID, frontend, optional profile, dependency versions and `ir-file` or
`ir-unit` output contract without reading source bodies. Legacy `register_frontend`
continues to accept `IRFile` and replace registrations with the same name.

During execution the engine checks the returned ID, envelope budgets and metadata
node ownership before components or output. Adapters can raise
`SourceFrontendError::Rejected(code, detail, source_span)`; diagnostics preserve the
code and parser span in their message. Rich callbacks require planned checkpoint or
generation output. Legacy text backends and `Engine::run` reject them rather than
implicitly discarding metadata. Components retain their existing projection and
lineage rules. Morphir JSON remains supported; its checkpoint export rejects rich
metadata that the standard schema cannot represent.

The separate [MoonBit adapter](moonbit/README.md) registers `moonbit` explicitly.
`Engine::new()` does not register it or import its parser into the core package.

### Source providers and profiles

`register_source_provider(SourceProvider)` registers an in-process compiler provider
with one or more `SourceLanguage` offerings. Each language has file extensions, an
explicit default profile, and `SourceProfile` records. Each profile contains its
rich-unit callback, envelope limits, source capabilities, dependency versions and
`SourceEvidence`. Registration validates bounded descriptors and copies mutable
arrays and maps. It invokes no compiler.

Configure `frontend.language`, `frontend.provider` and `frontend.profile` in TOML.
Scheme equivalents are `frontend`, `frontend-provider` and `frontend-profile`.
A missing profile selects that provider's default. A missing provider selects the
only provider offering the language. Multiple providers require an explicit choice,
even if a profile name matches only one of them. Unknown providers, a provider that
does not offer the language, and unknown profiles fail before model reads.
Source constraints are invalid on codec inputs, including `ir-json`.

A plan captures the selected callback and its limits. Later registrations cannot
change execution of that plan. Selection descriptors include `language`, `provider`,
`profile`, `default_profile`, `available_profiles`, `capabilities` and `evidence`.
`default_profile` means the selected profile is the provider's default, including an
explicit request for it. The existing `frontend` field retains the language name.
Legacy registrations use their frontend name as provider ID, have no capability
claims, and report `Declared` evidence. Their overwrite API remains available;
a conflicting provider identity fails during selection rather than silently hiding
one compiler. `register_unit_frontend` rejects such collisions at registration.

`SourceCapabilities` describes supported and excluded source behavior, document
bounds, incremental support and configured parser budgets. These descriptions are
separate from IR feature vocabulary and protocol negotiation. `LocalAcceptance`
records repository qualification, not Morphir MCK certification. A callback receives
one source document per invocation; a provider's broader document capability does
not create project linking. Profile diagnostics keep their code and span and add
the captured provider/profile context. Project listing continues to report language
and configured target, without requiring compiler registration.

### Type inference

`pipeline.inference` runs the language-neutral type inference of
[`morphir-typing`](../morphir-typing/README.md) on each unit. Set it in `morphir.toml` or with
`(inference "fill")` in a `pipeline` script.

| Value | Effect |
| --- | --- |
| `off` (default) | No inference. The IR is unchanged. |
| `fill` | Writes the solved types into the IR: an `inferred_type` on each node, and the solutions of the signature types that have the unknown marker. |
| `check` | Checks the IR and does not change it. |

The stage runs after the transforms and before the backend. It uses the Morphir SDK specification as a dependency.
On the checkpoint and generation paths, `fill` changes the unit through `data.fill_lineage` with the
`no_derived` metadata policy, so metadata stays on its logical nodes and a written type gets no metadata.
Each inference problem is a diagnostic at stage `inference`, in the form `<code> at <node>: <message>`.
A value other than `off`, `fill` or `check` stops planning and names the file that set it.

On Scheme input, a call from one top-level `define` to another, or a top-level `define` that calls itself,
fails `fill` with `unknown_reference`, because the Scheme frontend lowers that reference as a local variable. Bead
`morphir-ukvn.5.22.8` tracks the frontend fix.

**End to end.** `mise run e2e:scheme-moonbit` and `mise run e2e:scheme-elm` compile the Scheme corpus in
`acceptance/inference`, fill its types and generate code. `moon build` must accept each MoonBit library, and
`elm make` must accept each Elm project. The MoonBit task uses `MOON_HOME`, or the pinned toolchain from
`mise where http:moonbit` when it is not set; to set it yourself, run
`MOON_HOME=$(mise where http:moonbit) mise run e2e:scheme-moonbit`. The corpus
holds monomorphic programs only, because the MoonBit generator has no specialization: a generic value, such as
`(define (id x) x)`, needs the specialization follow-up. `moonbit_gaps` names the corpus programs that the MoonBit
generator does not support yet, with the error that it must raise; Elm checks them all.

### Typed checkpoints

Planned pipelines can select `pipeline.backend = "checkpoint"`. Its default
`pipeline.checkpoint_format = "ion-binary"` is independent of the frontend.
Built-in data formats are `morphir-json`, `ion-text`, and `ion-binary`; `ir-json`
is also accepted as the JSON frontend name. Checkpoints preserve a typed
`data.IRUnit`, including rich metadata, through the
[`morphir-pipeline-v1` profile](data/README.md). The current checkpoint pipeline
permits identity processing and rejects transforms or visibility rewrites until
they provide metadata lineage. Standard JSON export checks for metadata loss.

`Engine::execute_content(plan, read)` returns `ContentReport` and accepts a
callback `(path, binary) -> data.Content`. Each `ContentArtifact` records path,
source, format and text/bytes. The existing `execute` API adapts text plans to
the same executor and reports missing byte capabilities for binary plans.
Both executors consume the same single-use plan. Host-level capability failures
occur before execution and leave the plan available for a capable host.

`Plan::boundaries()` returns source identities, selected input/output codecs,
profile and byte requirements. `requires_byte_read/write` also account for jobs
with no matching sources. Unit IDs are source-relative stems; envelope IDs must
match them. Selection, confinement, suffix collisions and destination ownership
use the existing planner.

For an additional codec, register it with `data.Registry::register`, register
its file extensions, output suffix and encoding using
`Engine::register_data_format(name, DataFormat)`, and pass the registry to
`Engine::plan(..., codecs=Some(registry))`. Format registrations reject conflicts,
copy extension arrays and bind descriptors into the plan. Planning checks that
the selected codecs exist. Execution rejects outputs whose encoding disagrees
with the format descriptor. This keeps file selection and host capability
requirements separate from codec implementation.

## Host contract and targets

Host paths are portable, relative, slash-separated strings. The engine removes
empty/`.` segments and rejects absolute paths, `..`, backslashes, colons and NUL.
`list(root)` returns recursive file paths relative to the host root, not the list
root. Listed files must remain inside the requested source subtree. `exists` tests
files; `read` returns text. The host must enforce its own filesystem root and symlink
policy. Output directories must be nonempty and cannot contain the source root.

`Host::memory` copies its input map so later caller changes cannot affect a run.
No filesystem/network dependency or Node-only API is imported by this module.
The same API and example build for `native`, `js`, `wasm` and `wasm-gc`.

Generation backends use `GenerationBackend` and return a `GenerationBatch` of
files and complete library projects. A batch carries legacy text warnings and
`structured_warnings` for diagnostics with codes, locations and fixes. Strict naming
mode checks structured naming warnings before accepting artifacts. The engine validates portable paths,
case collisions, file/directory conflicts, project root overlap and exact member
ownership before accepting a batch. Each input receives its own project root
under the task output. The generic engine contract has no filename or manifest
rules for a particular target.

A `GenerationBackend` has these fields:

- `generate` takes the IR unit, the options and a cancel check, and returns the batch.
- `write_bytes` tells the engine that the host must be able to write binary files.
- `validate_options` checks the options at planning time.
- `targets` lists the build targets that `pipeline.validation = "required"` can use.

The options of a generator are the `[backends.<name>]` table of the project
configuration, as JSON. The engine passes the table to `validate_options` when it
plans, and to `generate` for each unit. When `validate_options` fails, the plan
fails with `Invalid`. The message names the key and the file that set the key, or
the file that set its nearest table.

The built-in generators are:

- `moonbit` imports the portable `finos/morphir-moonbit` generator. Its targets are
  `wasm`, `wasm-gc`, `js` and `native`. `[backends.moonbit] naming = "readable"`
  is the default; `"legacy-hex"` retains the earlier generated ABI. Other keys
  remain ignored. Invalid naming settings fail when planning.
- `elm` imports `finos/morphir-elm` and writes an Elm package project for each
  unit. It has no targets. Its options are in the
  [morphir-elm README](../morphir-elm/README.md), for example
  `[backends.elm] profile = "literal"`.

`pipeline.validation` defaults to `required` for a generator that has targets, and
to `source-only` for a generator that has none. `pipeline.target` defaults to
`wasm`. A `required` plan fails with `build.unsupported_target` when the generator
does not list the target, so `required` always fails for `elm`. Set `source-only`
explicitly to publish source without build evidence. Existing String backends and
checkpoint outputs use the same execution and publication lifecycle.

Register typed or JSON-only components with `register_component`. Configure their
order with `pipeline.components` and select a registered `pipeline.metadata_policy`.
The built-in `json-identity` is a compatibility boundary exercised by the CLI.
Plans expose each component's declared transport and metadata policy separately
from the input and checkpoint codecs. A JSON-only step does not change the engine
or intermediate default from Ion. Legacy Scheme rewrites remain on their text
pipeline; typed pipelines require the explicit lineage component contract.

## Generated-model execution

`finos/morphir-engine/execution` plans calls against a generated public invocation
manifest and runs a host-supplied `Provider`. Its `Session` builds once, retains an
executable for runtime suites, and disposes it after execution and comparison.
Custom providers use the same contracts without filesystem assumptions.

`plan` validates the suite and public boundary types before host effects. `run`
accepts an optional `Evaluator` and `Observer`. The Scheme evaluator uses the same
IR unit as the generator, finite limits and no runtime accelerators. Provider
failures are errors; unequal typed values are unsuccessful comparison reports.
Required reports bypass observation sampling, queues and sinks.

The invocation boundary supports exact Int/Decimal, Float64 bits, UTF-16 text
and characters, records, tuples, lists, nongeneric custom types, Maybe and Result
on JavaScript, Wasm GC and native C. A separately pinned LLVM provider runs the
same rich pricing suite on its verified host. `plan(available_targets=...)` rejects an unavailable
required target before acquisition; LLVM needs an explicit available capability.
Session build/invoke callbacks receive optional validated trace context, separate
from semantic inputs. Lifecycle hardening and verification publication are implemented. Independent
conformance uses the separate contract below. Native OpenTelemetry collector
integration remains Task 6. E1 build-only
behavior is unchanged. Execute/verify do not publish over generated project output.


`run_report` returns required call terminals and separate primary/cleanup causes
for provider failures and cancellation. `run` preserves raising behavior,
including `CleanupFailed(original, cleanup)`. Input IR and suites are cloned
through binary Ion before effects, and source/manifest mutations cannot produce
a successful report. `matrix_successful` rejects partial, duplicate-target and
failed matrices; a required parity matrix also needs an evaluator profile.

## Independent conformance

`finos/morphir-engine/conformance` accepts versioned `Expectations` with explicit
provenance and a list of `EvaluatorLane` providers. `prepare` validates the same
suite/model and expected output types, and rejects unavailable or unsupported
required evaluators before acquisition. `run` freezes the Ion model and cases,
runs generated execution once, disposes its session, then compares each call
separately against independent and live results. Provider callbacks cannot
mutate the frozen model, driver or suite to change the comparison inputs.

Each lane records its own profile, identity evidence and call statuses.
Unavailable/unsupported optional coverage never becomes a comparison. Any
independent or live mismatch fails `Report.successful()` and retains its call
and JSON Pointer. `Report.encode()` defaults to native binary Ion; JSON is an
explicit projection. Required evidence does not depend on observer delivery.
Host-specific Rust conversion/process code stays in `morphir-host`. Field
projection policies live in `morphir-execution/projection`, separate from
semantic values and from host exporters.

### Source naming warnings

Rich source adapters may retain `morphir-warning-v1` diagnostic records in unit
provenance. Planned execution reads these records before components and generation,
returns them through `ContentReport.warnings` with structured `Diagnostic.details`,
and deduplicates identical owning allocations within one source run. Warning
locations refer to original source spans, even when the input is a checkpoint.
Unknown provenance remains untouched; malformed records marked as this diagnostic
contract fail explicitly. Storage does not authenticate a producer or confer
upstream metadata trust.

For MoonBit recoverable name allocation warnings, `[pipeline] strict_naming = true`
rejects the run before artifacts or projects are returned for publication. Warnings
remain visible in the report, and successful execution does not require optional
logging. Normal processing preserves the warning records through Ion checkpoint
output. Existing checkpoint semantic identities are never normalized on load.

## Declared target-name facts

`Engine::new(metadata_capabilities=...)` accepts the explicit provider restoration,
context acquisition and naming interpreter capabilities described in
[the metadata contract](../morphir-metadata/README.md). The built-in MoonBit generation
backend captures them at registration. Default capabilities are unavailable; neither
metadata nor configuration supplies provider trust. Known requests fail before artifacts
are returned when admission or required interpretation is missing. Rich Ion checkpoints
retain the authored payload, and Morphir JSON retains its checked loss boundary.
