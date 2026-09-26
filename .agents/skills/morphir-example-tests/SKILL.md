---
name: morphir-example-tests
description: Use when adding, adopting, debugging or updating Morphir CLI examples and morphir itest scenarios, including scenarios.md, .feature.md and .feature files, scenario metadata, Rego assertions and integration coverage.
---

# Morphir example tests

Read [the scenario contract](../../../docs/developers/example-integration-tests.md)
and [the example catalog](../../../examples/README.md). Use
[the single-file Elm scenario](../../../examples/elm/single-file/scenarios.feature.md)
as the smallest working example. Keep the contract in the guide; do not create
a second driver or copy MCK comparison logic.
For Markdown authoring, use [CLI basics](../../../examples/cli/basics/scenarios.md).
For reference Elm, follow the catalog's explicit release preparation step and
select `suite:elm-reference`. The preparation helper stages fixtures only;
repository registration, installation and compilation remain real CLI commands.
Use `suite:offline` when no downloaded provider is available.
For installed Avro/OpenAPI backends, fetch the pinned releases and run
`mise run examples:prepare-backends`, then select `suite:wasm-backends`.
Keep repository creation, publication and installation in scenario commands.
Main backend cases compile default v4 output; `backends/v3-compatibility` retains
explicit v3 generation coverage. Verify both when updating provider pins.

## Choose the claim

State the user workflow and what passing proves. Native Elm is opt-in and
currently compiles types only. Use the reference `morphir-elm` provider to
claim function lowering. Rego assertions evaluate CLI observations; they do
not establish native Morphir IR evaluation. See the
[evaluation architecture](../../../docs/developers/evaluation.md) for the
implemented provider boundary and native/WASM follow-up milestones.

Check existing tags with `morphir itest examples --list`. Use categorized
project directories; deeper categories require no runner edit. Keep malformed
source fixtures under `crates/morphir/tests/fixtures/itest/`.

## Author and verify

1. Choose one document per example directory: `scenarios.md`, or a Gherkin
   `scenarios.feature.md` (or `.feature`) file.
   For a Gherkin file, put the title and tags on the `Feature`, the description
   on the scenario, and `provider` and `workspace` in a `yaml itest` fence in the
   feature description. Write commands, captures and Rego checks as the itest
   steps in the guide. Use `@section:<id>` for a stable scenario ID.
   For `scenarios.md`, use YAML frontmatter with version 1, a title, a
   description, tags and `provider: rego`.
   Each top-level `##` heading starts an independent scenario; use `###` for
   steps. Explicit `{#id}` heading attributes keep filters stable across renames.
   Pair `yaml morphir:command`, `yaml morphir:assertion` and `yaml morphir:file`
   metadata fences with their next language source fences. Prose, lists and
   subheadings may separate the pair. A pair cannot cross a scenario heading.
   Keep YAML outside source fences and executable fences outside list/quote
   containers. Unmarked fences remain documentation. Filter one heading with
   `--filter 'category/example#id'`. IDs and workspace files may repeat across
   independent scenarios, but must be unique within each scenario.
2. Keep ordinary source/configuration files on disk beside the document. The
   scenario directory is copied into an isolated workspace by default. Use
   `workspace: {kind: "directory", path: "project", exclude: ["installed"]}`
   in scenario metadata to choose a subdirectory or exclude custom outputs.
   Optional `yaml morphir:file` fences (or `files` in a `yaml itest` fence) add
   inputs; conflicting disk and inline paths fail. Use `workspace: {kind: "inline"}`
   only for a self-contained scenario that ignores adjacent project files.
   Commands contain literal `morphir ...` invocations; case names, captures and
   timeouts belong to their metadata fence or their steps.
3. Put complete Rego modules in assertions. Reference the most recent command
   by ID and enumerate unique named rule entrypoints. Only boolean true
   passes. Check exit status plus meaningful artifacts/diagnostics. Request
   stdout JSON decoding and artifact captures explicitly. Missing files, JSON
   null, undefined rules and errors are distinct. Never derive expected values
   from the implementation during a run.
   For exact generated text, use `yaml morphir:golden` with `command`, `actual`
   and either a paired literal source fence or a standalone `expected_file`.
   Expected file paths are relative to the scenario directory and are
   frozen before commands; actual paths are relative to the temporary project.
   Use `select: {kind: lines, start: 3, end: 5}` for inclusive lines or
   `select: {kind: between, start: "BEGIN", end: "END"}` for unique literal
   markers. Omit selection for the whole file. Exact comparison is the default;
   use `line_endings: lf` explicitly for CRLF normalization after selection.
   Golden checks also require exit code zero. Review fixed expected content;
   never regenerate it as part of the test run. Inspect the diff and retained
   evaluation request when diagnosing mismatches.
4. Follow root checkout setup before testing. Run
   `mise run test:examples -- --filter <category/example>` before changing the
   CLI. Verify independent Markdown headings, prose between paired fences and
   every authoring format when changing the driver. Retain real CLI subprocesses for both workflow commands and evaluation;
   do not replace them with internal compiler calls or an external OPA binary.
5. Diagnose with `--keep-temp`, inspecting command logs, `observation.json` and
   assertion request/report logs. Establish whether the source, expectation,
   driver or CLI is wrong before fixing it. Demonstrate that a deliberately
   wrong expectation fails, then restore it and rerun the selected scenario,
   `mise run test:itest`, and the offline suite.
6. Update the catalog, developer/KB guidance and Beads with the exact coverage
   established. Native IR evaluation, WASM hosting and installed evaluator
   protocol negotiation are follow-up work, not milestone 0 capabilities.
   Tag deliberate current-limit checks `kind:negative` and
   `coverage:known-limitation`, link their follow-up issue, and describe the
   rejection they prove. Do not count them as successful feature coverage.

Repeated tags use AND selection. Missing prerequisites fail; there are no
implicit downloads or skips. Old `scenario.md`/`test.yaml` files are not
executable coverage. For throwaway checks, set an outer scratch `MORPHIR_HOME`
as well as the temporary-directory root so ordinary CLI logs stay contained.
The guide documents host configuration and isolation limits.
