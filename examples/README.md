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
| [Elm single-file functions](elm/single-file-functions/scenarios.md) | Reference lowering of an annotated addition function, including SDK operator and arguments | Reference Elm 0.1.0 |
| [Classic JSON Elm](elm/classic-json/scenarios.md) | Compilation from an on-disk `morphir.json` and source directory with explicit `--language elm` | Reference Elm 0.1.0 |
| [TOML project](simple-project/scenarios.md) | Config discovery and two public native Elm type modules in v4 IR | Offline |
| [YAML project](elm/yaml-project/scenarios.md) | Config discovery and a public native Elm record in v4 IR | Offline |
| [Multi-project workspace](monorepo-workspace/scenarios.md) | Default selection, selecting each member by path/name, distinct package identities, isolated task outputs and installed IR copies | Offline |
| [Gleam compile and generate](gleam/compile-generate/scenarios.md) | Function compilation, generated Gleam source and compile-to-generate task provenance | Offline |
| [Gleam type compatibility](gleam/type-compatibility/scenarios.md) | IR v3/v4 type compilation, imported generic references, labelled records, discriminated unions, opaque types and generated Gleam | Offline |
| [CLI basics](cli/basics/scenarios.md) | Version reporting and public command help in independent Markdown scenarios | Offline |
| [Classic multi-file Elm](morphir-elm-compat/scenarios.md) | Config discovery and the released provider's **known rejection** of multiple source documents | Reference Elm 0.1.0 |

Native Elm is types-only. Reference function lowering does not prove function
evaluation. The workspace scenarios do not yet prove cross-package dependency
resolution, and generated Gleam is inspected but not executed.

## Prepare the reference Elm scenarios

Download the executable for your host from the
[Elm extension 0.1.0 release](https://github.com/finos/morphir-elm/releases/tag/extension/elm/v0.1.0),
verify the archive against its published checksum, and extract it. Then run:

```sh
mise run examples:prepare-elm -- /path/to/morphir-elm-extension
mise run test:examples -- --tag suite:elm-reference
```

The helper also accepts `MORPHIR_ELM_EXTENSION_BIN`; the optional
`MORPHIR_ELM_EXTENSION_VERSION` must be `0.1.0`. Supply the executable for the
machine running the examples. Preparation copies it into ignored `.itest/elm`
fixture repositories beside the three reference examples. It does not install
or run the provider. Each scenario registers its copied repository and installs
the extension through real CLI commands in a fresh Morphir home.

CI uses the Linux executable pinned by `.config/published-extension-bundles.toml`.
Local preparation bridges the current absence of process-bundle publication in
`morphir extension repository publish`. No download happens inside `itest`.
Missing prerequisites fail; there are no implicit skips. After preparation,
`mise run test:examples` runs all scenarios. Use `suite:offline` to run without
the downloaded provider. Remove the generated `.itest` directories to clean up.

The multi-file classic case is tagged `kind:negative` and
`coverage:known-limitation`. Follow-up `morphir-o6vm.15` tracks classic Elm language
inference and multi-source extension support. Its passing rejection assertion
must be replaced with positive module/function assertions when support lands.

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
