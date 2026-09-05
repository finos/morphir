---
type: Decision Record
title: Record fields are spelled under a fields member
description: "In IR v4, a Record type or value writes its fields under a fields member, never as the wrapper's direct member map, so attributes can sit beside them without ambiguity."
state: Accepted
decided: 2026-09-04
tags: [ir, ir-v4, encoding, record, mck]
status: draft
---

# Record fields are spelled under a fields member

A v4 `Record` type and a v4 `Record` value spell their fields under a `fields` member of the wrapper's payload.
The direct member map the v4 schema's `RecordType` definition describes is withdrawn.

```yaml
Record:
  fields:
    name: morphir/SDK:string#string
    age: morphir/SDK:basics#int
```

| Option | Outcome | Why |
| ------ | ------- | --- |
| Fields under a `fields` member | Chosen | Unambiguous beside `attributes`; three of four existing sources already write it |
| Fields as the payload's direct member map | Rejected | A record with a field named `fields` or `attributes` cannot be told apart from the expanded form |
| Both accepted, direct map canonical | Rejected | Two readers disagreed on the same bytes during the Morphir Compatibility Kit's first run |

## Why

The v4 schema defines `RecordType` as a direct field map, `{ "Record": { "name": ..., "age": ... } }`. The published
complete example, the document-tree specification page, and the Rust CLI all write `{ "Record": { "fields": { ... } } }`.
The schema never caught the difference because its access-control wrapper arms validate nothing inside a
definition, so both spellings passed `examples:validate`.

With attributes carried inside the payload (decision 0005), the direct map has a structural hole. The reader must
decide whether a payload member named `fields` or `attributes` is a field or the expanded form, and a record whose
only field is named `fields`, or whose fields are exactly `attributes` and `fields`, is misread. The `@finos/morphir-ir`
reference reader reproduced both misreads on 2026-09-04. No detection rule closes them, because the two shapes are
identical by structure.

Spelling fields under `fields` removes the hole: `attributes` and `fields` are the only members a `Record` payload
can have, and a field name never competes with them.

## Consequences

1. Canonical: `{ "Record": { "fields": { ... } } }`; expanded: `{ "Record": { "attributes": { ... }, "fields": { ... } } }`.
2. The `RecordType` and `RecordValue` definitions in `website/static/schemas/morphir-ir-v4.yaml` change, and the
   generated schema of the specification's step 7.2 follows the reference codec.
3. Kit case `types-0005` becomes active with the `fields` spelling as its canonical fence; the direct map becomes a
   `rejected` fence with diagnostic `unknown_member`. Cases `types-0006` (extensible record) and the value-side
   record case are aligned.
4. The published examples and the `json canonical` fences that used the direct map (`types-0005` illustration,
   `document-tree-0003`) are rewritten.
5. Readers accept the direct map on input for one release, so files written by the schema-following path still
   load, and refuse it after.

## Revisit when

- A future version moves attributes out of the wrapper payload, at which point the direct map would be
  unambiguous again.
