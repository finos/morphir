---
title: Example integration tests
sidebar_label: Example integration tests
---

# Example integration tests

`morphir itest` discovers `scenario.ipynb` notebooks recursively and exercises
real Morphir CLI commands. Notebook cells combine the explanation, project
files, commands and Rego assertions in one document. Milestone 0 uses an embedded
Regorus evaluator, so the baseline suite requires no OPA executable or downloaded
extension. See [the evaluation architecture](evaluation.md) for the native
Morphir evaluator and WASM follow-up design.

## Run and select scenarios

Review and trust the repository mise configuration and initialize submodules
before building:

```sh
mise trust .config/mise/config.toml
mise run submodules:init
mise run test:examples
mise run test:examples -- --list
mise run test:examples -- --filter elm --tag suite:offline
mise run test:itest
```

With a built CLI:

```sh
morphir itest examples --list --tag language:elm
morphir itest examples --filter elm/single-file --keep-temp
```

The root defaults to `examples`. The scenario ID is its containing directory
relative to the search root, or `.` for a notebook directly in that root.
`--filter .` selects only that root-level notebook; `--filter root` selects a
directory named `root` and its descendants. Other filters select an exact ID
or directory category. Repeated `--tag` options
require every tag. Empty suites and selections fail, including with `--list`.
Scenario directories must have UTF-8 names that follow the portable path rules
below; discovery rejects names that would produce ambiguous or unselectable IDs.
All discovered notebook structures and scenario metadata are validated before
selection; Rego compilation occurs when the selected assertions execute.
Listing prints the scenario's intent and tags without executing it.

## Notebook and scenario metadata

Use nbformat **4.5** and the Morphir notebook profile version **1**. Standard
cell IDs are unique strings of 1–64 ASCII letters, digits, hyphens or underscores.
File paths belong in cell metadata, never in the cell ID. Source may be a string
or a list of strings; line endings are retained. Unknown metadata outside the
scenario's typed fields is preserved. Morphir reads the document without
rewriting it or using stored notebook outputs as test results.

Notebook `metadata.morphir` contains:

```json
{
  "version": 1,
  "itest": {
    "title": "Compile single-file Elm types",
    "description": "Verify the public types and canonical v3 IR artifact.",
    "tags": ["language:elm", "config:none", "area:compile", "suite:offline"],
    "provider": "rego"
  }
}
```

These scenario-wide fields replace Markdown frontmatter. All fields shown are
required. Title and description must explain what success proves. The `itest`
object rejects unknown fields. The only evaluator provider in milestone 0 is
`rego`; its implementation is the native `morphir-opa` crate using Regorus.

Use standard Markdown cells for explanations. Code and raw cells can carry
workspace files. Code cells carry commands and assertions. In a notebook editor,
authors edit cell source directly. The JSON document remains readable on disk;
nbformat support alone does not install a Jupyter kernel or guarantee per-cell
language highlighting in every editor. Execute the notebook with `morphir itest`.

| Tag dimension | Examples |
| --- | --- |
| Source language | `language:elm`, `language:gleam` |
| Frontend under test | `frontend:elm-native`, `frontend:morphir-elm` |
| Configuration | `config:none`, `config:json`, `config:toml`, `config:yaml` |
| Workflow | `area:compile`, `area:install`, `area:workspace`, `area:generate` |
| IR output | `ir:v3`, `ir:v4` |
| Expected behavior | `kind:positive`, `kind:negative` |
| Prerequisites | `suite:offline` |

Tags are unique, nonempty strings of lowercase ASCII letters, digits, colon,
hyphen, underscore or period. They select scenarios; they do not declare a
feature supported or skip a failing test.

## Workspace file cells

A cell with `metadata.morphir.file` declares an input file:

```json
{"path": "Example.elm", "language": "elm"}
```

Its source is the literal file contents. JSON, TOML, YAML, Elm and other text
files use the same convention. Every declared file is materialized before the
first command, regardless of cell position. A notebook supplies its complete
workspace; neighboring files are not implicitly copied. Keep the assertion
source in assertion cells, outside the project under test.

Paths are normalized, relative, slash-separated paths without empty components,
`..`, backslashes or drive prefixes. Windows device names, reserved punctuation and trailing dots/spaces are rejected.
Duplicate paths, case collisions and file/
directory conflicts fail validation. Materialization refuses existing files
and symlink ancestors. This shared notebook layer has no test-execution logic,
so other Morphir workspace consumers can adopt it later.

## Command cells

Command source is one literal invocation, such as:

```sh
morphir compile --input Example.elm --extension morphir-elm-native --package-name examples/single-file --json
```

Its `metadata.morphir.itest` describes the case:

```json
{
  "kind": "command",
  "name": "Compile public types",
  "timeout_seconds": 30,
  "stdout_json": true,
  "captures": [
    {"name": "ir", "path": ".morphir/out/compile.dest/morphir-ir.json", "format": "json"}
  ]
}
```

The name is nonempty and unique, and timeout is 1–300 seconds. `captures`
defaults to empty and `stdout_json` to false. Arguments support shell-style
quoting, but the driver invokes the current Morphir executable directly:
variables, substitutions, operators and pipelines have no shell semantics.

Commands run in notebook order in a fresh shared scenario workspace. Each
command must have at least one assertion cell. Observations are captured and
asserted before the next command runs, so later commands cannot overwrite an
earlier result. A nonzero normal exit can be tested; a signal or timeout is a
harness error.

## Rego assertion cells

Use ordinary Rego v1 modules. For the command above, a cell can contain:

```rego
package single_file_test

import rego.v1

test_compile_succeeds if {
    input.exitCode == 0
    input.stdoutJson.success == true
}

test_writes_v3_ir if {
    input.artifacts.ir.kind == "json"
    input.artifacts.ir.value.formatVersion == 3
    input.artifacts.ir.value.distribution[0] == "Library"
}
```

Its `metadata.morphir.itest` identifies the command cell and named rules:

```json
{
  "kind": "assertion",
  "command": "compile",
  "entrypoints": [
    "data.single_file_test.test_compile_succeeds",
    "data.single_file_test.test_writes_v3_ir"
  ]
}
```

Here `compile` is the command cell's ID. References must point to preceding
commands. Entrypoints must be nonempty and unique within the cell. Each assertion
cell is a complete module evaluated independently; it does not implicitly import
another assertion cell. Module loading and rule semantics belong to Regorus.
The driver sends a versioned request to a real `morphir eval` subprocess and
requires one matching result per entrypoint.

Only boolean **true** passes. False, undefined, nonboolean results, missing
rules, invalid source and runtime errors fail. Empty assertions cannot pass.
An `if` rule whose condition is false commonly produces `undefined` unless a
default value is declared; this is still a failed assertion.
Expected values are authored in Rego, never regenerated from actual output.
For negative cases, check the intended nonzero exit, diagnostics and absent
artifacts; a generic process failure is insufficient evidence.

The version 1 observation supplied as Rego `input` contains:

| Field | Value |
| --- | --- |
| `version` | `1` |
| `exitCode` | Normal process exit code |
| `stdout`, `stderr` | Captured UTF-8 text |
| `stdoutJson` | Parsed stdout, only when requested |
| `artifacts` | Object keyed by declared capture names |

A capture uses format `json`, `text` or `exists`. A present file becomes
`{"kind":"json","value":...}`, `{"kind":"text","value":"..."}`, or
`{"kind":"file"}` respectively. An absent path becomes `{"kind":"missing"}`.
Present directories and symlinks are errors. Invalid requested JSON is an error;
it does not become null. A decoded JSON null and an absent file stay distinct.

## Isolation and diagnosis

Every scenario receives a fresh project and Morphir home. Child commands and
assertion evaluation remove inherited `MORPHIR_*` overrides and redirect user
configuration/home directories. A local `.morphir` directory confines output
discovery. The driver never substitutes direct compiler-library calls.

Scenario commands are trusted local instructions, not a filesystem sandbox.
CLI arguments retain their usual meaning. The driver refuses system Morphir
configuration because the CLI cannot relocate it. On Windows it also refuses
Morphir configuration in the native Known Folder; use a clean account there.
The temporary root must also have no project/workspace configuration in its
canonical ancestors; choose a clean `TMPDIR`/`TEMP` when needed. A local
`.morphir` directory bounds output discovery, not configuration discovery.
Listing does not require a clean host. Missing prerequisites fail a selected
scenario; the driver does not silently install or skip anything.

Failures name the scenario, command and assertion cell, with stdout/stderr and
rule outcomes. Timeouts terminate the process tree; descendant cleanup also
runs after a normal child exit. `--keep-temp` retains each command's logs,
`observation.json`, and assertion request/report logs. Otherwise the temporary
workspace is removed. Set an outer scratch `MORPHIR_HOME` to contain the ordinary
logs of the invoking CLI too.

## Incremental coverage

1. Add the smallest missing workflow under `examples/<category>/<example>/`.
   Keep broken source fixtures under `crates/morphir/tests/fixtures/itest/`.
2. State its claim, tags and literal expected behavior in the notebook. Run the
   scenario before changing the implementation.
3. Establish whether a failure is in source, expectation, driver or CLI. Retain
   a regression and make the smallest justified fix.
4. Demonstrate that a deliberately wrong expectation fails, then restore it.
   Run the selected scenario, `mise run test:itest`, and the offline suite.
5. Update the catalog and coverage notes. Track missing workflows and verified
   defects in Beads. Report the exact behavior established.

The [single-file Elm notebook](https://github.com/finos/morphir/blob/main/examples/elm/single-file/scenario.ipynb)
verifies native type compilation and installation. It does not establish Elm
function lowering or native Morphir IR evaluation. Classic JSON projects,
TOML/YAML projects, workspaces and other frontends/backends remain increments.

Old `scenario.md` and `test.yaml` files are not executable coverage.
`examples:validate` checks published schema examples. MCK remains responsible
for IR/package compatibility contracts; this driver tests CLI workflows.
The Rust CI acceptance tests run the checked-in offline notebooks, and changes
under `examples/**` trigger that job.
