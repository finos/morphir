---
title: F# readiness workflow case
sidebar_label: Readiness workflow
status: draft
---

# F# readiness workflow case

An F# generation is `workflow-qualified` when it has run one fixed case: a small F# source package is compiled to an expected semantic IR model, and that model is generated to F# with the selected providers. This page describes that case, `fsharp-compile-generate`, and the files that hold it. Its [installation receipt](./installation-receipt.md#readiness) records the result as the generation's `workflow` check.

The case is data. It lives in [`spec/toolchain/workflows/fsharp-compile-generate/`](https://github.com/finos/morphir/tree/main/spec/toolchain/workflows/fsharp-compile-generate). The conformance runner that executes it lives in finos/morphir-dotnet, in `src/Morphir.Conformance`, with its `cli`, `library` and `mep-guest` adapters. This repository holds the case and checks that the data is consistent; it runs nothing.

The expected generated files are still pending (see below), so no generation can pass this case yet, and no manager records the check today.

## What the workflow is

The case has three steps. Each generation step reads the expected IR, not the compile step's output, so a generation failure is never caused by a compile difference.

| Step | Operation | Provider | Protocol and model | Expected |
| --- | --- | --- | --- | --- |
| `compile` | `compile`, language `fsharp`, from `files` | The recipe's process frontend | MEP `0.2.0-draft.1`, `morphir.frontend.compileModel` / `morphir-ir` / `morphir-json` / envelope `0.1.0-draft.1` / IR `4.0.0` | Success with no error diagnostics, and IR equal to `expected/ir-4.0.0.json` |
| `generate-built-in` | `generate`, target `fsharp` | The host's built-in `morphir.fsharp` | `modelInput` `morphir-ir` / `morphir-json` / IR `4.0.0` | Pending |
| `generate-external` | `generate`, target `fsharp` | The recipe's external process backend | MEP `0.2.0-draft.1`, `morphir.backend.generateModel` / `morphir-ir` / `morphir-json` / envelope `0.1.0-draft.1` / IR `4.0.0` | Pending |

The `morphir-json` codec carries the whole IR JSON document, including its `formatVersion`. The tuples are the ones the TEST-ONLY signed F# recipe fixture binds (`toolchains/recipes/fsharp/1.0.0.json` in [`fixtures/0.1.0-draft.1/signed/`](./index.md#fixtures-and-conformance)), and the morphir-dotnet frontend and backend guests advertise the same tuples.

## What it proves and what it does not

When a generation passes the case, it shows that:

- the selected frontend, the host and the selected backends agree on the model tuple and actually exchange a model over it;
- the frontend compiles this package to the expected semantic IR;
- each selected backend accepts that IR. Once the generation expectations are frozen, it also shows that each backend produces the expected F# files.

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

## Generation expectations are pending

The expected generated F# files are not frozen yet, for two reasons:

- the Native AOT host skips the Fantomas formatting pass, so its built-in backend emits different bytes from the managed hosts and from the process guest. How frozen files treat that difference is a maintainer decision;
- candidate files have to come from morphir-dotnet and be reviewed before they are frozen. They are never recorded here from a backend run.

Each generation step therefore has `status: "pending"`, a `reason` and an empty `sets` array. A frozen step will list one or more sets. Each set has its `files` (the generated path, the committed file and its SHA-256), a `comparison` (`exact-bytes` or `json-member-order-insensitive`), a `provenance`, and an optional `appliesTo` object that says which deliveries it covers. The schema leaves `appliesTo` open, so one set for every provider and one set per delivery are both possible without changing the case version.

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
| `steps` | The compile step first, then one or more generation steps |
| `steps.protocolVersion`, `steps.modelTuple` | The MEP version and tuple of a frontend or external provider |
| `steps.modelInput` | The model a built-in provider reads |
| `steps.provider` | The `delivery`, and for a built-in the `extensionId` |
| `steps.expected` | The expected outcome, IR or generated files, with comparison and provenance |

Every file the manifest lists is stored with its exact bytes and LF line endings, and `.gitattributes` marks the case directory `-text` so checkouts do not rewrite them.

The external backend step names its delivery but not its `extensionId`. The signed recipe fixture calls the backend `morphir-fsharp-backend`, while the morphir-dotnet process guest identifies itself as `org.finos.morphir.fsharp-backend`. That is the open question on [dotted provider identities](./toolset-recipe.md#open-questions-for-the-maintainer), and the case does not settle it.

## Running the case

A runner in morphir-dotnet reads the case as follows:

1. Read `case.json`, accept only `schemaVersion` `0.1.0-draft.1`, and check every listed SHA-256 before using a file.
2. Compile `sources` through the generation's frontend with the compile step's tuple, using the adapter that fits the delivery: `cli` for the `morphir` command line, `library` in process, or `mep-guest` for a process guest.
3. Compare the produced IR with `expected/ir-4.0.0.json` using the stated comparison rule.
4. For each generation step, give `expected/ir-4.0.0.json` to the selected provider and compare its output with the step's set for that delivery.
5. Report the outcome as the generation's `workflow` check. It is `passed` only when the compile step passed and every generation step passed against frozen files. While a generation step is `pending` the check cannot pass: it is `skipped`, with a reason naming the pending steps, so the generation stays `capability-checked`.

## Checks in this repository

`crates/morphir-toolchain-contract/tests/readiness_workflow.rs` checks the data only. It validates `case.json` against its schema; checks that every listed file is at a portable path inside the case directory and has its stated SHA-256; checks that the expected IR's `formatVersion` matches the declared value and the tuple's IR major version, and that it is an IR v4 library distribution of this package with its exposed modules; checks that every tuple, protocol version, built-in identity and model input matches the signed F# recipe fixture; checks that the qualified receipt fixture names this workflow; and checks that pending steps list no files. It generates and regenerates nothing. The docs job's `mise run examples:validate` validates the expected IR against the [IR v4 schema](/schemas/morphir-ir-v4.json); it runs whenever that schema or this case changes.

```sh
cargo test --locked --package morphir-toolchain-contract --test readiness_workflow
```
