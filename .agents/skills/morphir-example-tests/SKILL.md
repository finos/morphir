---
name: morphir-example-tests
description: Use when adding, adopting, debugging or updating Morphir CLI examples and morphir itest scenarios, including nbformat notebooks, scenario metadata, Rego assertions and integration coverage.
---

# Morphir example tests

Read [the scenario contract](../../../docs/developers/example-integration-tests.md)
and [the example catalog](../../../examples/README.md). Use
[the single-file Elm notebook](../../../examples/elm/single-file/scenario.ipynb)
as the smallest working example. Keep the contract in the guide; do not create
a second driver or copy MCK comparison logic.

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

1. Create a self-contained `scenario.ipynb` using nbformat 4.5. Put scenario
   title, description, tags and `provider: "rego"` in notebook
   `metadata.morphir.itest`, with `metadata.morphir.version: 1`.
   Use Markdown cells for explanations. Keep valid unique cell IDs separate
   from file paths. Preserve unrelated metadata and newlines.
2. Put source/configuration contents in workspace file cells with
   `metadata.morphir.file` path and language. Neighboring files are not copied.
   Commands are code cells containing literal `morphir ...` invocations;
   case names, captures and timeouts belong to their `morphir.itest` metadata.
3. Put complete Rego modules in assertion cells. Reference a preceding command
   cell by ID and enumerate unique named rule entrypoints. Only boolean true
   passes. Check exit status plus meaningful artifacts/diagnostics. Request
   stdout JSON decoding and artifact captures explicitly. Missing files, JSON
   null, undefined rules and errors are distinct. Never derive expected values
   from the implementation during a run.
4. Follow root checkout setup before testing. Run
   `mise run test:examples -- --filter <category/example>` before changing the
   CLI. Retain real CLI subprocesses for both workflow commands and evaluation;
   do not replace them with internal compiler calls or an external OPA binary.
5. Diagnose with `--keep-temp`, inspecting command logs, `observation.json` and
   assertion request/report logs. Establish whether the source, expectation,
   driver or CLI is wrong before fixing it. Demonstrate that a deliberately
   wrong expectation fails, then restore it and rerun the selected scenario,
   `mise run test:itest`, and the offline suite.
6. Update the catalog, developer/KB guidance and Beads with the exact coverage
   established. Native IR evaluation, WASM hosting and installed evaluator
   protocol negotiation are follow-up work, not milestone 0 capabilities.

Repeated tags use AND selection. Missing prerequisites fail; there are no
implicit downloads or skips. Old `scenario.md`/`test.yaml` files are not
executable coverage. For throwaway checks, set an outer scratch `MORPHIR_HOME`
as well as the temporary-directory root so ordinary CLI logs stay contained.
The guide documents host configuration and isolation limits.
