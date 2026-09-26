# Morphir Compatibility Kit: IR suite

This directory holds the executable IR serialization contract. The native
`morphir mck` runner drives each binding through an explicit external adapter.
Parent CI runs the TypeScript and Rust adapters. A passing run can contain
capability skips, so a compatibility claim must name its required capabilities
and kit version.

The case files are plain Gherkin `*.feature` files. The kit driver contract is
2; a CLI that reads the former Markdown case grammar must refuse a managed
version-2 kit before starting an adapter. The adapter protocol remains integer
contract version 1. Historical reports, transcripts and corpus inventories
remain under [the baseline directory](../../mck/baseline/README.md).

The kit states meaning by example. The semantic model lives in TypeScript; YAML
is the current reference text form and JSON is the second profile. If a spec
page and an executable case disagree, correct the page or the case explicitly.
Ion as a reference encoding is specified in
[the next kit draft](../../../docs/design/draft/testing/mck-ion-reference.md).

## Files

| File | Holds |
| --- | --- |
| `names.feature` | Canonical strings, accepted legacy names, document-tree escapes |
| `types.feature` | Type expressions |
| `values.feature` | Value expressions |
| `patterns-and-literals.feature` | Patterns and literals |
| `definitions.feature` | Definitions, specifications, access and annotations |
| `distributions.feature` | Complete Library, Specs and Application documents |
| `document-tree.feature` | Manifest, module and node files; layout equivalence |
| `versions.feature` | Cross-version reading and writing |
| `documents/` | Large fixtures referenced by cases |
| `allowed-failing.json` | Parent TypeScript adapter gate baseline |
| `protocol.schema.json` | Closed version-1 IR adapter protocol |
| `report-draft.schema.json` | Consolidated report contract |

The linked-metadata reference corpus, node-address draft corpus, and package
suite have separate contracts and gates. They do not add IR adapter cases to
these feature files.

## Authoring a case

Name a scenario `<topic>-<NNNN> <title>`, where the topic matches its file.
Keep an assigned ID stable. A case may span consecutive scenarios with the
same ID. An outline row makes one report record. Use a `Feature` or
`Scenario` description for the reason behind the case.

Tags carry case options: `@node:Value`, `@version:4`, `@pending`, and
`@compare:attributes`. Put a shared tag on the feature or a local tag on a
scenario. The runner's step library accepts canonical spellings, accepted
inputs, rejected inputs, and document-tree files. One-line inputs can be
outline rows; multiline inputs use doc strings with a format content type.

```gherkin
@node:Value
Feature: Values
  Scenario Outline: values-0003 Reference shorthand
    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                                  |
      | YAML   | Reference: morphir/SDK:basics#add         |
      | JSON   | { "Reference": "morphir/SDK:basics#add" } |
```

A reader step may require a specific warning or rejection diagnostic. Tree
steps group files by set and compare both the decoded document and written
files. `morphir mck check spec/ir/mck` validates Gherkin syntax, case IDs,
tags, step shapes, fixture paths and cross-file duplicates.

## What a run checks

The runner first asks the adapter for its supported IR versions, profiles,
layouts, paths and node kinds. It skips a record whose requirement the adapter
does not claim. It decodes each canonical and accepted input and compares the
adapter's canonical output with the case's canonical spelling, allowing one
trailing newline. A rejected input must produce its named diagnostic or node
kind. For a document-tree set, the runner reads the files as one document and
compares them with the single-file canonical document, then compares the files
written back. Pending cases produce skips; an active case containing only
rejected inputs still runs. The wire messages are defined by
[protocol.schema.json](protocol.schema.json), contract version 1.

To add a case, choose the next unused ID in its topic file, explain the
decision in scenario prose, add canonical YAML and JSON spellings where the
profile supports both, then add accepted and rejected spellings. A temporary
legacy spelling carries a `legacy_spelling` warning until its release window
closes. Run `mise run mck:check` and record a decision bead when the case
settles an open contract question.

## Run and inspect

```sh
morphir mck check spec/ir/mck
morphir mck schema check --kit spec/ir/mck
morphir mck run --kit spec/ir/mck --adapter ./my-adapter --report report.json
morphir mck report check report.json allowed-failing.json --kit spec/ir/mck
morphir mck report render report.json --format html --output report.html
```

`mise run mck:run` and `mise run mck:run-rust` exercise the TypeScript and
Rust adapters and check full-kit coverage and reports. A filtered report
requires the same explicit `--filter` at report check time. The consolidated
JSON report is authoritative; HTML is a standalone offline view.
`report check` independently verifies the kit digest, record inventory and
allowances. A failed adapter session or missing digest cannot pass. Capability
skips and a development allowance limit any compatibility claim.
