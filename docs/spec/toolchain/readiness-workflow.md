---
title: F# readiness workflow case
sidebar_label: Readiness workflow
status: draft
---

# F# readiness workflow case

An F# generation is `workflow-qualified` when it has run one fixed case: a small F# source package is compiled to an expected semantic IR model, and that model is generated to F# with the generation's selected providers. `workflow-qualified` is a readiness state of one generation on one machine; it is not a claim that a release, an offering or a platform is qualified (see the [glossary](./index.md#glossary)). This page describes that case, `fsharp-compile-generate`, and the files that hold it. Its [installation receipt](./installation-receipt.md#readiness) records the result as the generation's `workflow` check.

The case is data. It lives in [`spec/toolchain/workflows/fsharp-compile-generate/`](https://github.com/finos/morphir/tree/main/spec/toolchain/workflows/fsharp-compile-generate). The conformance runner that executes it lives in finos/morphir-dotnet, in `src/Morphir.Conformance`, with its `cli`, `library` and `mep-guest` adapters. This repository holds the case and checks that the data is consistent; it runs nothing.

Both steps now have fixed expectations. The expected generated file was produced by builds that are not released and was observed on Windows ARM64 only (see [generation expectations](#generation-expectations)). The compatibility kit cannot yet observe generated files, so no runner can pass the generate step today, and no generation is reported as `workflow-qualified` by this case.

## What the workflow is

The case has one step per operation of the `fsharp` preset. A generation runs each step once, with **the generation's selected provider** for that operation: the provider its lock records, whatever its delivery. It never runs a provider it did not select, so a default generation, which selects the built-in backend, never needs the external backend to qualify, and never downloads it.

Each step lists, under `providers`, the deliveries it covers and what each must agree on:

| Step | Operation | Covered deliveries of the selected provider | Expected |
| --- | --- | --- | --- |
| `compile` | `compile`, language `fsharp`, from `files` | `built-in` `morphir-dotnet.fsharp` writing `modelOutput` `morphir-ir` / `morphir-json` / IR `4.0.0` (the managed offerings); `process` and `dotnet-tool` speaking MEP `0.2.0-draft.1` with `morphir.frontend.compileModel` / `morphir-ir` / `morphir-json` / envelope `0.1.0-draft.1` / IR `4.0.0` | Success with no error diagnostics, and IR equal to `expected/ir-4.0.0.json` |
| `generate` | `generate`, target `fsharp` | `built-in` `morphir.fsharp` reading `modelInput` `morphir-ir` / `morphir-json` / IR `4.0.0`; `process` speaking MEP `0.2.0-draft.1` with `morphir.backend.generateModel` and the same model | Run with formatting off: exactly the bytes of `expected/generated/Pricing.fs` at the generated path `Pricing.fs` |

The generate step reads the expected IR, not the compile step's output, so a generation failure is never caused by a compile difference. The `morphir-json` codec carries the whole IR JSON document, including its `formatVersion`. The identities, tuples and models are the ones the F# recipe fixtures bind: the synthetic `recipe/fsharp-synthetic.json` and the TEST-ONLY signed `toolchains/recipes/fsharp/1.0.0.json` in [`fixtures/0.1.0-draft.1/signed/`](./index.md#fixtures-and-conformance). The morphir-dotnet guests advertise the same tuples.

A process or `.NET` tool provider is identified by its delivery and its tuple, not by an `extensionId`, because the case qualifies whichever provider the generation's recipe bound. A built-in is identified by its `extensionId`, because it is part of the host and has no artifact.

## What it proves and what it does not

When a generation passes the case, it shows that:

- the selected frontend, the host and the selected backend agree on the model and actually exchange it;
- the selected frontend compiles this package to the expected semantic IR;
- the selected backend accepts that IR and, with formatting off, produces the expected F# file byte for byte.

It does not show:

- that the frontend accepts any other F# program. Frontend coverage is the job of the full frontend corpus;
- that a .NET SDK build, `dotnet restore`, an MSBuild project evaluation or package references work. The case uses none of them;
- that the generated F# compiles, or that consumers can build it;
- anything about IR versions other than 4.0.0, about other targets, or about WASM delivery;
- that an artifact is authentic. Authentication is the `integrity` check, which comes earlier.

## Source compilation, not a project build

The compile step gives the frontend the source documents and the package identity, and nothing else. The package is `acme/demo`, exposing module `Pricing`, with one document, `Pricing.fs`. The input kind is `files`: each document is passed by name in the listed order. No project file, SDK, restore, package reference or network access is needed. A runner that drives the `morphir` command line writes `project.name` and `project.exposed_modules` to a `morphir.toml` and passes each source with `--input`, which is how the morphir-dotnet `cli` adapter runs a `files` case.

Building an F# project with the .NET SDK is a different operation, with different prerequisites and a different failure model. It is not part of readiness. The corpus also has `directory` and `project file` inputs; this case uses `files` because it is the one with no project evaluation at all.

## The source package

The package reuses case `frontend-fsharp-0100` of the morphir-dotnet frontend corpus, from `conformance/suites/frontend-fsharp/records.feature` at commit `3f226a086220a45a3926a69e2093d53b86730ca5` (feature blob `d3e67b692b4d04baba3e76a1bdc5609d1538c626`), in its `files` × IR 4 row. That corpus case is tagged `@semantic` and `@basis:hand-authored`. It is a record type and one function that reads a field:

```fsharp
namespace Acme.Demo
module Pricing =
    type Car = { Plate: string; Seats: int }
    let seats (car: Car) : int = car.Seats
```

The corpus runs this case for the `files`, `directory` and `project file` inputs and for IR 1 to 4, so it is inside the boundary the frontend already supports. It has no dependencies and uses no construct that the F# admission catalog refuses.

`source/Pricing.fs` is the corpus docstring with its six spaces of Gherkin indentation removed and no final newline, as a Gherkin reader produces it. The manifest records its SHA-256.

The corpus case also checks a call (`Pricing.seats` with a car of two seats returns `2`). The readiness case does not repeat it: a call check runs generated F#, which readiness does not require.

## The expected IR

`expected/ir-4.0.0.json` is a byte-identical copy of the corpus file `conformance/suites/frontend-fsharp/expected/0100/ir-4.json` at the same commit, git blob `2dd743ba9853b65194c071d63ffa966c0f3e2643`. The corpus says its expected IR is written by hand for each IR version from the format specifications. No compiler output was recorded for it, and none may replace it. The manifest records the file's SHA-256, its `formatVersion` (4) and this provenance.

The comparison is the corpus rule: the produced IR document equals the expected one when they are equal JSON values, ignoring the order of object members. Arrays, strings, scalar kinds and number spellings are compared exactly, so `1` and `1.0` differ. No other normalization is applied. The manifest names this rule `json-member-order-insensitive`.

## Generation expectations

**Decided (9 November 2026, [finos/morphir#1146](https://github.com/finos/morphir/issues/1146#issuecomment-6759989025)).** The workflow check compares one unformatted set of generated files with LF line endings on every platform. It runs `generate` with formatting explicitly off, so all four offerings and both backends, the built-in and the external one, must produce byte-identical files. Formatted output is not part of a fixed expectation. A formatter hook around the generate phase is a separate, later change with its own design (finos/morphir-dotnet#575), and readiness never runs a hook.

The Native AOT built-in cannot run the Fantomas formatter, because Fantomas is built on the F# compiler's parser, which the Native AOT composition excludes; that is why the fixed set is unformatted.

The generate step says `"formatting": "off"`. A runner runs the selected backend with formatting off, however its host spells that. morphir-dotnet's spelling is the F# backend option `--option format=false`, given here only as an example: whether formatting should instead be a generate-level setting every backend honours is a question for the maintainer, and the case does not depend on the answer.

**The frozen set.** The step's `status` is `frozen`, with one set without `appliesTo`, which covers both covered deliveries:

| Generated path | Committed file | Bytes | SHA-256 | Comparison |
| --- | --- | --- | --- | --- |
| `Pricing.fs` | `expected/generated/Pricing.fs` | 112 | `64e08313f3e57be2c18995a2e8b275db9d921341958da2c8cd960c601c066de0` | `exact-bytes` |

The file is UTF-8 without a byte order mark, with LF line endings only and exactly one final LF. It is the generator's text for `expected/ir-4.0.0.json` with formatting off.

morphir-dotnet produced it five ways from that IR, and all five were byte-identical:

- the built-in backend under a JIT host, under the Native AOT host, and as the .NET tool;
- the external MEP guest driven by a JIT host and by the Native AOT host.

Its `provenance` (`kind: "generated"`) records the producing pull request, finos/morphir-dotnet#578 (`pullRequest: 578`), `released: false`, `observedOn: ["win-arm64"]`, each producer, and the file's git blob. **The set is fixed; its producers are not.**

- The producing work is the unmerged finos/morphir-dotnet#578, stacked on finos/morphir-dotnet#574. That repository squash-merges, so the commits on the pull request's branch become unreachable once the branch is deleted, and the provenance names the pull request rather than a branch commit. When #578 merges, its merge commit on the default branch is recorded in `commit`. The file's bytes and digest do not change then, and the blob stays the same.
- No released build has produced the file.
- It has been observed on Windows ARM64 only; Linux and macOS have not been observed.

The file was reviewed against the producing report, not generated here.

A frozen step lists one or more sets. Each set has:

- `files`: the generated path, the committed file, its length in bytes and its SHA-256;
- a `comparison`: `exact-bytes` or `json-member-order-insensitive`;
- a `provenance`. A `generated` provenance records the producing repository and its `pullRequest` number, the pull request's merge `commit` once it exists (absent before), whether the producers are `released`, the platforms the result was `observedOn`, the `producers` by delivery and host, and the file's `blob`. The other kinds record the source repository, commit, `path` and `blob`;
- an optional `appliesTo`, keyed by delivery: `{ "delivery": ["built-in", "process"] }` names the deliveries of the selected provider it covers.

A set without `appliesTo` covers every delivery and must be the step's only set. Otherwise each delivery appears in at most one set, and only deliveries the step lists under `providers`. A step whose files have not arrived has `status: "pending"`, a `reason`, and an empty `sets` array.

## Case manifest

`case.json` follows [`toolchain-workflow-case-0.1.0-draft.1.schema.json`](/schemas/toolchain-workflow-case-0.1.0-draft.1.schema.json). It is a new document with its own `schemaVersion`, versioned like the other toolchain documents: a `0.1.0-draft.1` reader accepts exactly that version, ignores unknown members, and refuses a `critical` member it does not understand.

The corpus format, Gherkin with the closed step vocabulary 1.1, was not used. That vocabulary has steps for compiling and comparing IR, but none for generation, provider selection, protocol tuples or file digests, and adding them would change a vocabulary other suites depend on. The compile half of the manifest maps one-to-one onto vocabulary 1.1 instead: `package` is "the F# package … exposing …", `sources` are "the source …", `compile` is "it is compiled from … with IR version …", and its `expected` is "compilation succeeds with no error diagnostics" and "the IR equals …". `basis` names the corpus case and row it reuses.

| Member | Meaning |
| --- | --- |
| `workflow` | The workflow id a receipt's `workflow` check names |
| `preset` | The recipe preset this case qualifies |
| `basis` | The corpus case, commit, feature blob, vocabulary and row the case reuses |
| `package` | The package name and its exposed modules |
| `sources` | Each document's `uri` as the frontend sees it, its `file` in the case directory and its SHA-256 |
| `steps` | The compile step, then the generate step |
| `steps.providers` | Each delivery of a selected provider that the step covers, at most once each: `delivery`; for a built-in, `extensionId` and its model (`modelOutput` when it compiles, `modelInput` when it generates); otherwise `protocolVersion` and `modelTuple` |
| `steps.expected` | The expected outcome, IR or generated files, with comparison and provenance |

Every file the manifest lists is stored with its exact bytes and LF line endings, and `.gitattributes` marks the case directory `-text` so checkouts do not rewrite them.

The external backend is `org.finos.morphir.fsharp-backend` and the external frontend is `org.finos.morphir.fsharp-frontend`. Dotted extension ids in release descriptors are decided, and the descriptor change is finos/morphir#1149. Until it lands, the signed fixtures use `morphir-fsharp-frontend` and `morphir-fsharp-backend` (see [toolset recipe limits](./toolset-recipe.md#limits-of-this-contract-version)). The case names neither, because it identifies external providers by delivery and tuple.

## Running the case

A runner in morphir-dotnet reads the case as follows:

1. Read `case.json`, accept only `schemaVersion` `0.1.0-draft.1`, and check every listed SHA-256 before using a file.
2. For each step, take the generation's selected provider for the step's operation from its lock. If the step does not list that provider's delivery under `providers`, or the provider's identity, protocol or model differs from the listed entry, the case does not cover this generation: the workflow check is `unsupported`, naming the step.
3. Compile `sources` through the selected frontend, using the adapter that fits its delivery: `cli` for a built-in, run through the `morphir` command line, `library` in process, or `mep-guest` for a process or .NET tool guest. Compare the produced IR with `expected/ir-4.0.0.json` using the stated comparison rule.
4. Give `expected/ir-4.0.0.json` to the selected backend with formatting off, and compare every generated file with the generate step's set for that delivery, byte for byte. A file missing from the output, an extra file, or any difference fails the step.
5. Report the outcome as the generation's `workflow` check. It is `passed` only when every step passed with the selected providers against frozen files. A runner that cannot run a step reports the check `skipped`, with a reason naming the step. The compatibility kit observes compilation only today, so a runner built on it skips the generate step until the kit can observe generated files.

The workflow check runs whenever it can. A `skipped` check does not prevent activation, and a generation whose check is skipped is never reported as `workflow-qualified`; a check that ran and failed prevents activation ([activation](./installation-receipt.md#readiness)).

## Checks in this repository

`crates/morphir-toolchain-contract/tests/readiness_workflow.rs` checks the data only. It validates `case.json` against its schema; checks that every listed file is at a portable path inside the case directory and has its stated SHA-256 and length; checks that the expected IR's `formatVersion` matches the declared value and the tuple's IR major version, and that it is an IR v4 library distribution of this package with its exposed modules; checks that every provider the synthetic and signed F# recipes can select for an operation, built-in or external, is covered by its step with the same identity, protocol and model; checks that each step names a delivery once and that frozen sets name disjoint deliveries; checks that the managed offerings, and only they, compile in process; checks that the qualified receipt fixture names this workflow; and checks that the generate step runs with formatting off and has one frozen set, without `appliesTo`, of UTF-8 files with LF line endings and one final LF, whose provenance says the producers are unreleased and were observed on `win-arm64` only. It generates and regenerates nothing. The docs job's `mise run examples:validate` validates the expected IR against the [IR v4 schema](/schemas/morphir-ir-v4.json); it runs whenever that schema or this case changes.

```sh
cargo test --locked --package morphir-toolchain-contract --test readiness_workflow
```
