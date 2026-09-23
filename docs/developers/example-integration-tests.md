---
title: Example integration tests
sidebar_label: Example integration tests
---

# Example integration tests

`morphir itest` discovers `scenario.ipynb` and `scenarios.md` recursively and exercises
real Morphir CLI commands. Both formats define explanations, commands, Rego
assertions and golden text comparisons for ordinary on-disk projects. They can also supply optional project
files in cells, including entirely self-contained examples. Milestone 0 uses an embedded
Regorus evaluator, so the baseline suite requires no OPA executable or downloaded
extension. See [the evaluation architecture](evaluation.md) for the native
Morphir evaluator and WASM follow-up design.

## Run and select scenarios

Review and trust the repository mise configuration and initialize submodules
before building:

```sh
mise trust .config/mise/config.toml
mise run submodules:init
mise run test:examples -- --tag suite:offline
mise run test:examples -- --list
mise run test:examples -- --filter elm --tag suite:offline
mise run test:itest
```

With a built CLI:

```sh
morphir itest examples --list --tag language:elm
morphir itest examples --filter elm/single-file --keep-temp
```

Reference Elm cases use `suite:elm-reference` and require an explicitly prepared
extension 0.3.1 executable. Follow the
[catalog preparation instructions](https://github.com/finos/morphir/blob/main/examples/README.md#prepare-the-reference-elm-scenarios)
before selecting them or running all examples without a tag. The helper stages
local fixture repositories; commands in each scenario register and install the
provider into the isolated Morphir home. Missing prerequisites fail.

Installed Avro/OpenAPI cases use `suite:wasm-backends`. Run
`mise run ci:fetch-published-bundles` followed by
`mise run examples:prepare-backends` to stage pinned WASM bundles. Scenarios
perform repository initialization, registration, publication and installation
through the CLI. Main cases use default v4 IR and assert generated schemas;
`backends/v3-compatibility` retains explicit v3 coverage. Select either IR version
with an additional `--tag ir:v4` or `--tag ir:v3`.
See the [backend preparation instructions](https://github.com/finos/morphir/blob/main/examples/README.md#prepare-the-installed-wasm-backend-scenarios).

Use `coverage:known-limitation` with `kind:negative` for a scenario deliberately
checking a current rejection, and record its follow-up issue in the prose. Such
a pass is not successful feature coverage; replace it with positive expectations
when support lands.

The root defaults to `examples`. A notebook's scenario ID is its containing directory
relative to the search root, or `.` for a notebook directly in that root.
Markdown scenario IDs append `#heading-id`, such as `cli/basics#version` or
`.#version` at the search root. Quote filters containing `#` in the shell.
`--filter .` selects scenarios directly in the search root; `--filter root` selects a
directory named `root` and its descendants. Other filters select an exact ID
or directory category. Repeated `--tag` options
require every tag. Empty suites and selections fail, including with `--list`.
Scenario directories must have UTF-8 names that follow the portable path rules
below; discovery rejects names that would produce ambiguous or unselectable IDs.
All discovered document structures and scenario metadata are validated before
selection; Rego compilation occurs when the selected assertions execute.
Listing prints the scenario's intent and tags without executing it.
Use one supported document per directory. Having both `scenario.ipynb` and
`scenarios.md` in one directory is an error. Scenario directory names cannot
contain the reserved `#` separator.

## Markdown scenarios

Use `scenarios.md` for ordinary Markdown authoring. YAML frontmatter provides
document context and shared scenario defaults. The fields below are required;
`workspace` is optional and has the same behavior as notebook workspace metadata.

````markdown
---
version: 1
title: CLI basics
description: Verify version reporting through the real CLI.
tags: [area:cli, suite:offline]
provider: rego
---

# CLI basics

## Report version {#version}

```yaml morphir:command
id: run
name: Report CLI version
timeout_seconds: 10
```

Explanations may appear between the metadata and its source fence.

```sh
morphir --version
```

### Check the result

```yaml morphir:assertion
id: check
command: run
entrypoints: [data.version_test.reports_version]
```

```rego
package version_test
import rego.v1

reports_version if {
    input.exitCode == 0
    some line in split(input.stdout, "\n")
    startswith(line, "morphir ")
}
```
````

Each top-level second-level heading (`##`) starts an independent scenario with
a fresh workspace and Morphir home. Its heading text becomes the scenario title;
the frontmatter supplies its description, tags, provider and workspace settings.
Use `###` and deeper headings to organize steps within a scenario. Commands and
file additions do not carry over between scenarios, and block IDs may be reused
in different scenarios.

Without an explicit `{#id}`, the heading ID is its lowercase ASCII words joined
by hyphens. IDs must be unique within the document and contain 1–64 lowercase
ASCII letters, digits, hyphens or underscores. Use an explicit ID for a stable
filter when changing a title, or for headings without ASCII words.
For example, `--filter 'cli/basics#version'` runs only the version scenario;
`--filter cli/basics` runs every scenario in that directory and its descendants.

The paired metadata markers are `yaml morphir:command`, `yaml morphir:assertion`,
`yaml morphir:file` and inline `yaml morphir:golden`. Each metadata fence applies
to the next fenced source block. A golden with `expected_file` instead stands
alone, without a source fence. Prose, lists and subheadings may separate the pair. A new `##` scenario
heading or another metadata fence before the source is an error. Executable
pairs must be top-level, with opening fences at column one, rather than nested
in blockquotes or lists. Both backtick and tilde fences are supported.

Metadata requires an `id` with the same rules as notebook cell IDs. Command and
assertion fields match the corresponding notebook roles below, without `kind`,
which comes from the marker. Commands contain literal `morphir ...` invocations;
assertion source fences use `rego`. Source fences must name their language.
Unpaired ordinary fences are documentation and do not execute. Unknown Morphir
markers, unknown metadata fields, duplicate YAML keys, unclosed paired fences,
dangling metadata and scenarios without commands/assertions fail validation.

Optional file pairs use metadata such as:

````markdown
```yaml morphir:file
id: example-source
path: src/Example.elm
```

```elm
module Example exposing (Name)

type alias Name = String
```
````

The language comes from the source fence. Source contents, including indentation
and line endings, are preserved. Every file in a scenario is materialized before
its first command. Use `workspace: {kind: inline}` in frontmatter to ignore
adjacent disk inputs and use only that scenario's file fences. The `inline`
spelling also works in notebooks; the existing `notebook` spelling remains valid.

Both authoring formats load into the same scenario validator and run through the
same CLI subprocess and evaluator pipeline. Markdown does not create or rewrite
a notebook on disk. See [CLI basics](https://github.com/finos/morphir/blob/main/examples/cli/basics/scenarios.md)
for a complete document containing two scenarios.

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

These scenario-wide fields correspond to Markdown frontmatter. All fields shown are
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
| Prerequisites | `suite:offline`, `suite:elm-reference`, `suite:wasm-backends` |
| Known gaps | `coverage:known-limitation` with `kind:negative` |
| Workspace inputs | `workspace:directory`, `workspace:notebook` |

Tags are unique, nonempty strings of lowercase ASCII letters, digits, colon,
hyphen, underscore or period. They select scenarios; they do not declare a
feature supported or skip a failing test.

## Workspace inputs

By default, the directory containing the scenario document is the workspace source.
Keep normal project files on disk:

```text
single-file/
  Example.elm
  scenario.ipynb
```

The driver copies the project into a temporary workspace before executing any
commands. Source files and directories are preserved; command outputs remain in
the temporary copy. File cells are optional additions to that copy.

The optional `metadata.morphir.itest.workspace` field selects another source:

```json
{"kind": "directory", "path": "project", "exclude": ["installed"]}
```

`path` is `.` or a portable relative subdirectory of the scenario directory.
Omitting the entire field is equivalent to `{"kind":"directory","path":"."}`.
The optional `exclude` list contains relative file or directory paths, not globs.
Directory exclusions include descendants. Use it for custom generated outputs.

The copy omits `scenario.ipynb`, `scenarios.md`, `.git`, `node_modules`, `target`, `elm-stuff`,
`dist` and `out` entries, plus `.morphir/cache`. Other `.morphir` inputs, including
`.morphir/morphir.toml`, are preserved. Git ignore files are not interpreted.
Symlinks and special files are rejected; ordinary files retain their bytes and
permissions, and empty directories are copied.

For a self-contained notebook that deliberately ignores adjacent project files,
use `{"kind":"notebook"}`. Its project inputs come entirely from file cells.
Both forms run through the CLI and need no Jupyter kernel.

### Optional file cells

A cell with `metadata.morphir.file` declares an input file:

```json
{"path": "Example.elm", "language": "elm"}
```

Its source is the literal file contents. JSON, TOML, YAML, Elm and other text
files use the same convention. Every declared file is materialized before the
first command, regardless of cell position. Disk files and notebook file cells
can be combined. Duplicate files, portable-name collisions and file/directory
conflicts fail rather than silently replacing inputs. Keep the assertion source
in assertion cells, outside the project under test.

Paths are normalized, relative, slash-separated paths without empty components,
`..`, backslashes or drive prefixes. Windows device names, reserved punctuation and trailing dots/spaces are rejected.
Duplicate paths, Unicode-normalization or case-fold collisions, and file/
directory conflicts fail validation. Collision keys use NFKC, full case folding
and NFC, while materialized filenames retain their authored spelling.
Materialization refuses existing files
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

## Golden text assertions

Use golden assertions when the exact generated text is part of the expected
behavior. They work alongside Rego assertions and reference a preceding command
by its cell/block ID. A golden passes only when that command exits successfully
and its selected text equals the authored expectation. The driver evaluates this
rule through the same real `morphir eval` subprocess used for Rego assertions.
Golden checks do not add another evaluator provider.

For a checked-in expected file, the Markdown metadata fence stands alone:

```yaml morphir:golden
id: generated-source
command: generate
actual: .morphir/out/generate/gleam.dest/main.gleam
expected_file: golden/main.gleam
```

`actual` is relative to the temporary project workspace. `expected_file` is
relative to the directory containing the scenario document, even when
`workspace.path` selects a subdirectory or the workspace is inline. Expected
files need not be embedded in the document. All expectations are read before any
scenario command runs, so generated output cannot replace the baseline mid-run.
Both paths must be portable relative paths; symlinks and non-regular files fail.
Missing files and invalid UTF-8 fail instead of becoming empty expectations.

For inline expected text, omit `expected_file` and pair the metadata with a
source fence. Its language is for highlighting; its contents are literal text.
Prose may separate the fences as with existing paired blocks.

````markdown
```yaml morphir:golden
id: generated-function
command: generate
actual: .morphir/out/generate/gleam.dest/main.gleam
select: {kind: lines, start: 3, end: 5}
```

Compare this exact function, including indentation and the final newline:

```gleam
pub fn hello() {
  "world"
}
```
````

A notebook uses the same fields under a code cell's
`metadata.morphir.itest`, plus `"kind": "golden"`. The cell source holds the
inline expected text. When `expected_file` is supplied, the cell source must be
empty; combining the two is an error. Golden cells are expectations, not
workspace files, and do not require `entrypoints`.

The optional `select` field selects **actual** contents only. The entire
expected contents are compared against that selection:

| Selection | Behavior |
| --- | --- |
| Omitted or `{kind: all}` | Compare the complete file |
| `{kind: lines, start: 3, end: 5}` | Compare lines 3 through 5, inclusive and numbered from 1 |
| `{kind: between, start: "BEGIN", end: "END"}` | Compare the exact text after the start marker and before the end marker |

Lines split at LF and retain their terminators, including CRLF. A final
unterminated line counts; a trailing LF does not create an extra empty line.
Zero, reversed and out-of-range line selections fail. Markers are literal,
nonempty, distinct strings, each occurring exactly once in the actual file.
Missing, repeated, overlapping or reversed markers fail. Marker selection does
not trim whitespace or remove surrounding newlines. For example,
`start: "BEGIN\n"` excludes that newline, while `start: "BEGIN"` retains it.

Comparison defaults to `line_endings: exact`: whitespace, CRLF versus LF, and
the final newline all matter. Use `line_endings: lf` to convert CRLF to LF on
both sides **after selection**. It does not trim, reindent, replace lone CRs or
add a final newline. Markers must match the original file's line endings.

A mismatch reports the scenario, command, golden ID, actual path, selector,
expected source and a bounded unified-style diagnostic diff. Missing final
newlines and control characters are made visible. With `--keep-temp`, the
assertion's `request.json` retains the selected actual and expected contents
sent to the evaluator, including any explicit normalization. Diffs are diagnostic
text, not patches to apply. There is no automatic golden-update mode: edit and
review expectations intentionally.

See the [Gleam example](https://github.com/finos/morphir/blob/main/examples/gleam/compile-generate/scenarios.md)
for whole-file, line-range and marker checks alongside semantic Rego assertions.

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
2. State its claim, tags and literal expected behavior in the scenario document. Run the
   scenario before changing the implementation.
3. Establish whether a failure is in source, expectation, driver or CLI. Retain
   a regression and make the smallest justified fix.
4. Demonstrate that a deliberately wrong expectation fails, then restore it.
   Run the selected scenario, `mise run test:itest`, and the offline suite.
5. Update the catalog and coverage notes. Track missing workflows and verified
   defects in Beads. Report the exact behavior established.

The [single-file Elm notebook](https://github.com/finos/morphir/blob/main/examples/elm/single-file/scenario.ipynb)
verifies native type compilation and installation. It does not establish Elm
function lowering or native Morphir IR evaluation. The
[example catalog](https://github.com/finos/morphir/blob/main/examples/README.md) also covers reference Elm functions,
classic JSON, TOML/YAML projects, member selection and Gleam generation, with
explicit prerequisites and limits for each claim.

Old `scenario.md` and `test.yaml` files are not executable coverage.
`examples:validate` checks published schema examples. MCK remains responsible
for IR/package compatibility contracts; this driver tests CLI workflows.
The Rust CI acceptance tests run the checked-in offline scenarios in both formats, and changes
under `examples/**` trigger that job.
