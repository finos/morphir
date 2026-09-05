---
type: Decision Record
title: Attributes are an optional first member of every node payload
description: "Every IR v4 type, value, and pattern node has a compact spelling and an expanded spelling whose payload carries attributes as its optional first member; writers use the compact form when attributes are empty."
state: Accepted
decided: 2026-09-04
tags: [ir, ir-v4, encoding, attributes, mck]
status: draft
---

# Attributes are an optional first member of every node payload

Every v4 type expression, value expression, and pattern has two spellings. The compact spelling is what the schema
documents today. The expanded spelling is the same wrapper key whose payload is an object with `attributes` as its
optional first member, followed by the node's own members. A writer emits the compact spelling when the attributes
are empty and the expanded spelling otherwise. A reader accepts both.

```yaml
# compact                      # expanded
a                              Variable:
                                 attributes:
                                   source: { startLine: 3, startColumn: 5, endLine: 3, endColumn: 6 }
                                 name: a

Unit: {}                       Unit:
                                 attributes: { source: ... }
```

| Option | Outcome | Why |
| ------ | ------- | --- |
| `attributes` as the optional first member of the payload | Chosen | Generalizes the shape `Literal` already has; keeps the single-key wrapper every reader dispatches on |
| `attributes` as a sibling of the wrapper key | Rejected | Every node becomes a two-key object, which breaks single-key dispatch and matches nothing written today |
| Attributes only on `Literal` and `LiteralPattern`, as the schema has it | Rejected | The specification's own examples write attributes on `Variable`, `Apply`, `Reference`, `Field`, and `Tuple`, and source locations are the point of v4's structured attributes |

## Why

The v4 schema defines `TypeAttributes` and `ValueAttributes` but lets only `LiteralValue` and `LiteralPattern`
carry them; every other value wrapper is `additionalProperties: false` or a bare string, so the specification's own
examples fail the schema. The register in [IR v4 stabilization](/ir-v4-stabilization.md) lists this as a
contradiction inside the schema.

The `Literal` node already has the expanded shape `{ "Literal": { "attributes": ..., "literal": ... } }`. Extending
it to every node is the smallest change that makes the examples valid, and it preserves the rule the readers depend
on: a node is an object with one member, and that member's name is the node kind.

Casing does not change. morphir-elm's v3 codec writes PascalCase tags for types and values alike, its v1 codec
wrote snake_case for both, and only v2 differed, because type tags were capitalized one release before value tags.
Case has never marked type versus value in the IR; role comes from position. Under decision 0001, an uppercase
segment inside a name means an initialism, and that is case's only job.

## Consequences

1. `TypeAttributes` (`source`, `constraints`, `extensions`) and `ValueAttributes` (`source`, `inferredType`,
   `extensions`) keep their members; each is optional inside `attributes`, and an `attributes` object with nothing set
   is never written.
2. Nodes whose compact payload is a bare string (`Variable`, `Reference`, `Constructor`, `FieldFunction`) expand to
   `{ "attributes": ..., "name" | "fqname": ... }`. Nodes whose compact payload is an array (`Tuple`, `List`,
   `TuplePattern`) expand to `{ "attributes": ..., "elements" | "items" | "patterns": [...] }`. `Record` expands to
   `{ "attributes": ..., "fields": ... }` per decision 0004.
3. Patterns follow the same rule with `ValueAttributes`.
4. Kit case `types-0009` becomes active with the bare `a` as canonical and the expanded `Variable` as accepted; every
   node kind gains one expanded-form fence so the coverage rule holds.
5. The v4 schema's `Value`, `Type`, and `Pattern` definitions gain the expanded arm for every node; the generated
   schema of specification step 7.2 follows the reference codec.

## Revisit when

- Attributes grow members whose presence changes meaning, at which point "empty attributes and no attributes are
  the same" needs restating.
