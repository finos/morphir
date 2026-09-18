# Morphir CLI examples

These examples are projects you can read, copy and run with the consolidated
`morphir` CLI. Categories can contain further subdirectories. A `scenario.ipynb`
or `scenarios.md` file makes an example executable by `morphir itest`.

```sh
mise run test:examples
mise run test:examples -- --list
mise run test:examples -- --filter elm --tag suite:offline
```

With a built or installed CLI that includes `itest`:

```sh
morphir itest examples --tag language:elm --tag frontend:elm-native
```

Multiple tags require all listed tags. Every scenario declares its purpose and
tags in notebook metadata or Markdown YAML frontmatter. Markdown `##` headings
separate independent scenarios; `--filter 'cli/basics#version'` selects one.
Marked YAML fences describe the next source fence, with prose permitted between
them. Both formats share execution and validation. Markdown cells explain the workflow, command cells
invoke the CLI, and Rego cells assert outcomes. Project files stay on disk by
default; optional file cells can supply additional inputs or an entire workspace.
The driver copies the scenario directory into a temporary workspace and runs actual CLI processes
with a separate Morphir home. The embedded Regorus provider evaluates assertions.

## Executable examples

| Example | What its scenario proves |
| --- | --- |
| [Elm single file](elm/single-file/scenario.ipynb) | Native type compilation to v3 IR, public record/custom-type structure, task result and installation |
| [CLI basics](cli/basics/scenarios.md) | Version reporting and public command help in independent Markdown scenarios |

Passing this example does not establish Elm function lowering or evaluation.
The native frontend is types-only; reference Elm functions need the real
`morphir-elm` provider and a separate scenario.

## Existing material awaiting adoption

These files remain available, but they have no `scenario.ipynb` or `scenarios.md` and are not
verified by `itest`. Their old `test.yaml` files are not driver inputs.

| Location | Current scope |
| --- | --- |
| `morphir-elm-compat/` | Classic `morphir.json` project; its README still describes the old Go/NPX workflow |
| `simple-project/` | TOML configuration expectations without source modules |
| `monorepo-workspace/` | Workspace/member configuration expectations without source modules |
| `task-pipeline/` | Task configuration and an Elm source; commands need adoption to the current CLI |
| `toolchain-config/` | Legacy toolchain configuration demonstration |
| `decorations/` | Decoration configurations and sample values |
| `morphir.toml`, `morphir.minimal.toml` | Configuration reference fragments, not runnable projects |

Adopt these incrementally: reference Elm functions, classic JSON projects,
TOML and YAML projects, multi-project workspaces, then additional frontends and
backends. Each adoption needs its own passing scenario before coverage is claimed.

See [authoring and debugging integration scenarios](../docs/developers/example-integration-tests.md).
