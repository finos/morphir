---
type: Design Note
title: Example-driven CLI validation
description: Notebook scenarios and embedded Rego assertions turn documented Morphir CLI workflows into incremental regression coverage.
tags: [cli, examples, integration-tests, tdd, evaluation]
status: stable
---

# Example-driven CLI validation

`morphir itest` recursively discovers `scenario.ipynb` under categorized example
directories. Each notebook supplies prose, source/configuration files, literal
CLI commands and Rego assertions. The driver materializes a fresh workspace and
uses the same Morphir executable for workflow commands and `morphir eval`.

```sh
mise run test:examples -- --filter elm/single-file
mise run test:examples -- --list --tag language:elm
```

The [single-file Elm notebook](https://github.com/finos/morphir/blob/main/examples/elm/single-file/scenario.ipynb)
checks native type compilation, public record/custom-type structure, v3 task
results and an installed IR copy. The negative fixture proves malformed Elm
fails without publishing usable IR. Neither establishes native Elm function
lowering or native Morphir IR evaluation.

## Authoring and feedback

Scenario title, purpose and tags belong in notebook metadata. Markdown cells
explain intent. File cells carry logical paths and language metadata; paths are
separate from nbformat cell IDs. Command cells declare case names, captures and
timeouts. Assertion cells contain Rego modules and name the preceding command
and rule entrypoints. No Markdown/JSON assertion DSL is retained.

Repeated tags require all selected dimensions. Categories may contain more
categories without driver edits. All selected commands and named assertions
must execute successfully; false, undefined, missing rules, malformed results
and empty assertions cannot make a scenario green.

```mermaid
flowchart LR
    Workflow[User workflow] --> Notebook[Notebook scenario]
    Notebook --> CLI[Real Morphir CLI]
    CLI --> Observation[Captured status and artifacts]
    Observation --> Eval[Morphir eval with Rego provider]
    Eval --> Diagnosis[Assertion result and diagnosis]
    Diagnosis --> Fix[Focused regression and fix]
    Fix --> Notebook
```

**Figure 1:** Real CLI observations are checked by a reusable evaluator while the notebook retains the intended behavior.

Start with the smallest missing behavior, write fixed expectations and run it
before changing implementation. Establish whether a failure belongs to source,
expectation, driver or CLI. Retain passing behavior and demonstrate that a wrong
expectation fails. Do not regenerate expectations from actual output or weaken
a structural check to a successful exit. Keep broken source in failure fixtures.

## Evaluator boundary and target state

Milestone 0 embeds Regorus through `morphir-opa`. `morphir-evaluator` owns a
versioned host-independent request/report and provider trait. Generic evaluation
returns values, undefined outcomes or errors. `itest` separately requires boolean
true. The provider receives already-loaded source and JSON input; it does not
own filesystem or process access. No external OPA executable is required.

The native Morphir evaluator is the next target, not a current feature. The
same boundary is intended for native IR programs, CLI hosting, a WASM ABI,
UI workers and policy hosts. Beads epic `morphir-o6vm.9` tracks semantic core,
CLI/notebook integration, native/WASM parity, UI/policy adapters and evaluator
capability negotiation. See the
[evaluation design and milestone table](https://github.com/finos/morphir/blob/main/docs/developers/evaluation.md).

The embedded Rego provider is registered natively. Installed evaluator discovery
and MEP negotiation remain follow-up work. Pin and test the engine profile;
Regorus integration does not claim all OPA builtins or Rego-to-Morphir compilation.

## Coverage and maintenance

MCK owns IR/package compatibility contracts. `itest` exercises CLI workflows
and reuses evaluator providers; it does not implement another compatibility kit.
Existing projects without `scenario.ipynb`, old `scenario.md` and `test.yaml`
files remain unverified. Adopt classic JSON, TOML/YAML, workspaces and additional
frontends/backends incrementally with their own observable checks.

Driver tests cover discovery, notebook parsing/materialization, tags, capture
semantics, isolation and process cleanup. CLI acceptance tests run positive and
negative examples and intentionally bad assertions. Provider fixtures test
evaluation independently. Changes under `examples/**` trigger the Rust CI job.

Use the [authoring guide](https://github.com/finos/morphir/blob/main/docs/developers/example-integration-tests.md)
for the complete contract and isolation limits. Agents use the
[local skill](https://github.com/finos/morphir/blob/main/.agents/skills/morphir-example-tests/SKILL.md).
