---
type: Decision Record
title: Node member names follow the schema, with a one-release compatibility window
description: "IR v4 value and type nodes use the member names the v4 schema and the Morphir Compatibility Kit pin; the spellings the Rust CLI and older spec examples wrote are accepted on input for one release, then refused."
state: Accepted
decided: 2026-09-04
tags: [ir, ir-v4, encoding, vocabulary, mck, compatibility]
status: draft
---

# Node member names follow the schema, with a one-release compatibility window

The canonical member names of v4 value and type nodes are the ones the v4 schema defines and the Morphir
Compatibility Kit pins: `IfThenElse` has `condition`, `then`, `else`; `Field` has `target`, `name`; `LetDefinition`
has `name`, `definition`, `in`; the attributes member is `attributes`. The spellings other writers used are accepted
on input for one release and refused after it.

| Node | Canonical | Accepted for one release |
| ---- | --------- | ------------------------ |
| `IfThenElse` | `condition`, `then`, `else` | `thenBranch`, `elseBranch` |
| `Field` | `target`, `name` | `subject`, `fieldName` |
| `LetDefinition` | `name`, `definition`, `in` | `valueName`, `valueDefinition`, `inValue` |
| any node | `attributes` | `attrs` |
| `Function` type | see [decision 0007](/decisions/0007-parameters-are-declared-and-arguments-are-applied.md) | `arg`, `result`, `argumentType` |

| Option | Outcome | Why |
| ------ | ------- | --- |
| Schema names canonical, legacy names accepted for one release | Chosen | The kit already pins the schema names; the window keeps files the alpha CLI wrote loadable |
| Adopt the Rust CLI's names | Rejected | Flips three active kit cases, the schema, and the morphir-ui decoder to preserve files only the alpha CLI ever wrote |
| Schema names with no window | Rejected | Strands every v4 artifact on disk on the day the rule lands |

## Why

Three implementations wrote three vocabularies for the same nodes. The kit's first run against the reference codec
reported `unknown_member` at `/IfThenElse/thenBranch`, `/Field/subject`, and `/Function/arg`, which is the drift the
register in [IR v4 stabilization](/ir-v4-stabilization.md) lists under "Between schema and implementations".

The schema's names are the shortest spellings that read as the Elm constructor's argument names (`then`, `else`,
`in`), the kit's active cases `values-0005`, `values-0006`, and `types-0007` already pin them, and every non-Rust
reader was written against them. The Rust names are a compatibility concern, not a design one, and a window
handles that without changing the contract.

## Consequences

1. The kit records the window: each affected case gains the legacy spelling as an `accepted` fence now, and that
   fence becomes `rejected` with `unknown_member` at the release that closes the window.
2. Readers that accept a legacy spelling report a warning diagnostic naming the canonical spelling.
3. The Rust encoder is corrected under the Rust mirror follow-up, and the morphir-ui decoder drops its `attrs`
   alias when the window closes.
4. `values-0005`, `values-0006`, and `types-0007` stay active with their current canonical fences.

## Revisit when

- The window closes, at which point the accepted fences flip and this record's table becomes history.
