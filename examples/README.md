# Morphir CLI examples

These examples are projects you can read, copy and run with the consolidated
`morphir` CLI. Categories can contain further subdirectories. A `scenario.ipynb`
or `scenarios.md` file makes an example executable by `morphir itest`.

```sh
mise run test:examples -- --list
mise run test:examples -- --tag suite:offline
mise run test:examples -- --filter simple-project
```

With a built or installed CLI that includes `itest`:

```sh
morphir itest examples --tag language:elm --tag frontend:elm-native
```

Multiple tags require all listed tags. Every scenario declares its purpose and
tags in notebook metadata or Markdown YAML frontmatter. Markdown `##` headings
separate independent scenarios; `--filter 'cli/basics#version'` selects one.
Marked YAML fences describe the next source fence, with prose permitted between
them. Both formats share execution and validation. Prose explains the workflow,
command cells invoke the CLI, and Rego cells assert outcomes. Project files stay
on disk by default; optional file cells can supply additional inputs or an entire
workspace. The driver copies the scenario directory into a temporary workspace
and runs actual CLI processes with a separate Morphir home. The embedded Regorus
provider evaluates assertions.

## Executable examples

| Example | What its scenario proves | Prerequisites |
| --- | --- | --- |
| [Elm single file](elm/single-file/scenario.ipynb) | Native type compilation to v3 IR, public record/custom-type structure, task result and installation | Offline |
| [Elm single-file functions](elm/single-file-functions/scenarios.md) | Reference lowering of an annotated addition function, including SDK operator and arguments | Reference Elm 0.3.1 |
| [Classic JSON Elm](elm/classic-json/scenarios.md) | Compilation from an on-disk `morphir.json` and source directory with explicit `--language elm` | Reference Elm 0.3.1 |
| [TOML project](simple-project/scenarios.md) | Config discovery and two public native Elm type modules in v4 IR | Offline |
| [YAML project](elm/yaml-project/scenarios.md) | Config discovery and a public native Elm record in v4 IR | Offline |
| [Multi-project workspace](monorepo-workspace/scenarios.md) | Default selection, selecting each member by path/name, distinct package identities, isolated task outputs and installed IR copies | Offline |
| [Gleam compile and generate](gleam/compile-generate/scenarios.md) | Function compilation, whole-file/line/marker golden comparisons, semantic Rego assertions and compile-to-generate task provenance | Offline |
| [Gleam type compatibility](gleam/type-compatibility/scenarios.md) | IR v3/v4 type compilation, imported generic references, labelled records, discriminated unions, opaque types and whole-file generation goldens for both modules | Offline |
| [Gleam structural values](gleam/structural-values/scenarios.md) | V4 local bindings, tuple destructuring, list tails and patterns, escaped strings and float spelling, with a whole-file generation golden | Offline |
| [Morphir V3 defined in Gleam](gleam/ir-v3/scenarios.md) | Complete V3 data model, 30 types in 12 modules, generation goldens and a structural type roundtrip; real compiler check available separately | Offline |
| [Installed Avro backend](backends/avro/scenarios.md) | Local bundle publication/installation, native Elm to default v4, Avro record and primitive field mappings, task provenance and installed output | Pinned Avro 0.1.2 WASM bundle |
| [Installed OpenAPI backend](backends/openapi/scenarios.md) | Local bundle publication/installation, native Elm to default v4, JSON Schema and OpenAPI schema components, task provenance and installed outputs | Pinned OpenAPI 0.1.1 WASM bundle |
| [Avro v3 compatibility](backends/v3-compatibility/avro/scenarios.md) and [OpenAPI v3 compatibility](backends/v3-compatibility/openapi/scenarios.md) | Explicit v3 compilation and successful Avro, JSON Schema and OpenAPI generation with the same providers | Both pinned WASM bundles |
| [Signed local Library resolve and restore](package/local-library-restore/scenarios.md) | Explicit trust, metadata-only refresh preserving locks, authenticated full-lock resolution, fresh two-Library restore/replay, generated and compiled provider code in a consumer project | Offline, fresh signed fixture |
| [Signed local Library scoped update](package/local-library-update/scenarios.md) | Explicit target update, movement within the old dependency closure, frozen outside pins, full-lock preservation and updated provider consumption | Offline, fresh signed fixture |
| [Create and publish a local Library](package/local-library-publish/scenarios.md) | Compile source, create and sign a classic V4 Library, publish with distinct registry-role keys, then resolve, restore, generate and compile in an independent consumer | macOS, source-built CLI; public test-only signing seeds |
| [CLI basics](cli/basics/scenarios.md) | Version reporting and public command help in independent Markdown scenarios | Offline |
| [CLI migration](cli/migrate/scenarios.md) | Classic JSON to V4 YAML with a fixed whole-file golden and a command result assertion | Offline |
| [Classic multi-file Elm](morphir-elm-compat/scenarios.md) | Config discovery and the released provider's **known rejection** of multiple source documents | Reference Elm 0.3.1 |

Native Elm is types-only. Reference function lowering does not prove function
evaluation. The workspace scenarios do not yet prove cross-package dependency
resolution, and generated Gleam is inspected but not executed.

## Prepare the reference Elm scenarios

Download the executable for your host from the
[Elm extension 0.3.1 release](https://github.com/finos/morphir-elm/releases/tag/extension/elm/v0.3.1),
verify the archive against its published checksum, and extract it. Then run:

```sh
mise run examples:prepare-elm -- /path/to/morphir-elm-extension
mise run test:examples -- --tag suite:elm-reference
```

The helper also accepts `MORPHIR_ELM_EXTENSION_BIN`; the optional
`MORPHIR_ELM_EXTENSION_VERSION` must be `0.3.1`. Supply the executable for the
machine running the examples. Preparation copies it into ignored `.itest/elm`
fixture repositories beside the three reference examples. It does not install
or run the provider. Each scenario registers its copied repository and installs
the extension through real CLI commands in a fresh Morphir home.

CI uses the Linux executable pinned by `.config/published-extension-bundles.toml`.
Local preparation bridges the current absence of process-bundle publication in
`morphir extension repository publish`. No download happens inside `itest`.
Missing prerequisites fail; there are no implicit skips. After preparing both
the reference Elm and WASM backend prerequisites below,
`mise run test:examples` runs all scenarios. Use `suite:offline` to run without
the downloaded provider. Remove the generated `.itest` directories to clean up.

The multi-file classic case is tagged `kind:negative` and
`coverage:known-limitation`. Follow-up `morphir-o6vm.15` tracks classic Elm language
inference and multi-source extension support. Its passing rejection assertion
must be replaced with positive module/function assertions when support lands.

## Prepare the installed WASM backend scenarios

Download the releases pinned in `.config/published-extension-bundles.toml`, then
stage the Avro and OpenAPI bundles beside their examples:

```sh
mise run ci:fetch-published-bundles
mise run examples:prepare-backends
mise run test:examples -- --tag suite:wasm-backends
```

The existing fetch task downloads all pinned bundles. WASM guests are portable;
the separately downloaded Elm executable is Linux-specific and is not used by
this suite. To reuse an existing download directory, pass
`mise run examples:prepare-backends -- /path/to/published-bundles`.

Preparation verifies the WASM bytes against the repository's pinned digests and
copies the guest, checksum and release descriptor into ignored `.itest`
directories. Each scenario uses real CLI commands to create/register a local
repository, publish its bundle and install the provider in an isolated Morphir
home. No download or installation happens in the preparation helper.

The main examples compile default v4 IR with canonical `Public` wrappers.
The v3 compatibility projects check the same targets with explicit v3 output.
Select one version with `--tag suite:wasm-backends --tag ir:v4` or
`--tag suite:wasm-backends --tag ir:v3`.
OpenAPI coverage checks schema components from types, not inferred API operations.
Remove generated `.itest` directories to clean up.

## Existing material awaiting adoption

These examples have no executable scenario yet. Old `test.yaml` files are not
driver inputs; the adopted TOML/workspace examples retain them as historical data.

| Location | Current scope |
| --- | --- |
| `task-pipeline/` | Task configuration and an Elm source; commands need adoption to the current CLI |
| `toolchain-config/` | Legacy toolchain configuration demonstration |
| `decorations/` | Decoration configurations and sample values |
| `morphir.toml`, `morphir.minimal.toml` | Configuration reference fragments, not runnable projects |

See [authoring and debugging integration scenarios](../docs/developers/example-integration-tests.md).
