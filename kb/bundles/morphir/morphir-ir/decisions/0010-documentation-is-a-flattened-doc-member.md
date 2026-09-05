---
type: Decision Record
title: Documentation is a flattened doc member
description: "In IR v4, documentation is a doc member placed first beside a definition's or specification's variant, never a nested {doc, value} wrapper, and a document-tree node file carries it in exactly one place."
state: Accepted
decided: 2026-09-04
tags: [ir, ir-v4, encoding, documentation, document-tree, mck]
status: draft
---

# Documentation is a flattened doc member

Documentation on a v4 definition or specification is a `doc` member beside the variant, written first. The nested
`{ "doc": ..., "value": ... }` wrapper is withdrawn as a canonical form.

```yaml
user-ID:
  Public:
    doc: Unique identifier for a user
    TypeAliasDefinition:
      typeParams: []
      typeExp: morphir/SDK:string#string
```

| Thing | Where `doc` goes |
| ----- | ---------------- |
| Type or value definition | Inside the access tag, first member, beside the variant |
| Type specification | First member beside the variant |
| Value specification | A member of the specification, beside `inputs` and `output` |
| Module definition or specification | A `doc` member after `types` and `values` |
| Entry point | A `doc` member beside `target` and `kind` |
| Document-tree `*.type` and `*.value` file | Inside `def` or `spec` only; the file-level `doc` is withdrawn |

| Option | Outcome | Why |
| ------ | ------- | --- |
| Flattened `doc` beside the variant | Chosen | What the only shipping writer and both published examples produce; one level less nesting on most definitions |
| Nested `{ doc, value }` wrapper | Rejected | A v3 shape that changes the shape of what it wraps; no v4 producer writes it |
| Both canonical | Rejected | Two spellings for the same thing, which the kit exists to prevent |

## Why

The v4 schema's `ModuleDefinition` describes the nested wrapper, the Rust CLI and both published examples write the
flattened member, and the schema's access-control arms validate neither, so the disagreement went unnoticed until
the Morphir Compatibility Kit's first run. The flattened member is the form in use, and it makes `doc` a member with
a fixed position instead of a wrapper.

The document-tree specification allowed `doc` at the top of a node file and inside `def` or `spec`, with the top
level winning for display. Two places for one string is a source of drift; a definition has one documentation
string, in the same place it has in a single-file distribution.

## Consequences

1. The nested wrapper is accepted on input for the one-release window of
   [decision 0006](/decisions/0006-node-member-names-follow-the-schema-with-a-one-release-window.md), then refused.
2. The v4 schema's `ModuleDefinition` and `ModuleSpecification` entries, and the document-tree schema's node files,
   change to the flattened member.
3. Kit `definitions-0006` becomes active with the flattened form as canonical and the nested form as an accepted
   fence for the window; `document-tree-0003` gains a `doc` inside its node file's `def`.
4. The reference model's `Documented<T>` wrapper stays as the in-memory shape; only the wire spelling is fixed here.

## Revisit when

- Documentation grows structure (a summary and a body, or per-parameter text), at which point `doc` becomes an
  object and this record's placement rule still applies to it.
