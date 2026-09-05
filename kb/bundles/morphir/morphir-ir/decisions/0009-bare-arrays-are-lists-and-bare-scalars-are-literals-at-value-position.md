---
type: Decision Record
title: Bare arrays are lists and bare scalars are literals at value position
description: "In IR v4 value position, a bare array is a List, a bare boolean or number is a literal, a bare string is a Variable or Reference, and a Tuple always carries its wrapper; writers keep the wrapped forms as canonical."
state: Accepted
decided: 2026-09-04
tags: [ir, ir-v4, encoding, shorthand, list, tuple, yaml, mck]
status: draft
---

# Bare arrays are lists and bare scalars are literals at value position

At value position a v4 reader accepts these shorthands, each with exactly one expansion:

| Bare spelling | Meaning |
| ------------- | ------- |
| `[a, b, c]` | `List` of the elements |
| `42`, `-7` (no point, no exponent) | `Literal` `IntegerLiteral` |
| `4.2`, `1e3` | `Literal` `FloatLiteral` |
| `true`, `false` | `Literal` `BoolLiteral` |
| a canonical name `x` | `Variable` |
| an FQName `morphir/SDK:basics#add` | `Reference` |

A string literal always needs its wrapper (`Literal: "a"` or `Literal: { StringLiteral: "a" }`), because a bare
string is a name. A `Tuple` value always carries its wrapper: `Tuple: [1, x]`.

```yaml
[1, 2, 3]                               # List of IntegerLiteral
[1.5, true]                             # List of FloatLiteral, BoolLiteral
[x, y]                                  # List of Variable x, Variable y
[{ Literal: "a" }, { Literal: "b" }]    # List of StringLiteral
Tuple: [1, x]                           # Tuple, always wrapped
```

Writers keep emitting the wrapped, typed forms as canonical in both profiles: `{ List: [...] }` and
`{ Literal: { IntegerLiteral: 1 } }`.

| Option | Outcome | Why |
| ------ | ------- | --- |
| Bare array is `List`; scalars are literals; `Tuple` wrapped | Chosen | Every language ports native list literals; the only ambiguity (List versus Tuple) disappears when the bare array means one of them |
| Reject all bare shorthands, as the reference codec first did | Rejected | Safe but makes `[1, 2, 3]` cost three wrappers, which defeats the readable profile |
| Bare array is `Tuple` at value position, matching type position | Rejected | Lists are far more common than tuples in value position; at type position the bare array is a `Tuple` only because a type has no list |
| A tuple shorthand (nested array, special key, string grammar, YAML tag) | Rejected | JSON's structural budget is spent; a YAML `!tuple` tag would break the no-tags rule and diverge the two profiles for one rare node |

## Why

The v4 schema listed bare booleans, numbers, and arrays as `Value` shorthands and, in the same file, said bare arrays
are not allowed because `List` and `Tuple` would be ambiguous. The design's reasoning was right about the
ambiguity and wrong about the remedy: the ambiguity is between two nodes, so giving the bare array to one of them
removes it. The bare array goes to `List` because that is what a native list literal in every target language is.

Bare scalars follow, because without them the list shorthand carries no weight. They are safe when the YAML
profile fixes scalar resolution.

## Rules

1. The YAML profile resolves plain scalars with the YAML 1.2 core schema only: `true`/`false`, integers, floats,
   and `null`; every other plain scalar is a string. The YAML 1.1 spellings `yes`, `no`, `on`, `off`, `~` are never
   booleans or null; a document that needs them as text quotes them.
2. A bare number's kind follows its lexeme: no point and no exponent is `IntegerLiteral`, otherwise `FloatLiteral`.
3. The string grammar is disjoint from names: a canonical name or FQName is a `Variable` or `Reference`; anything
   else at bare string position is `invalid_name`, never a string literal.
4. Canonical output is the wrapped form. Whether the YAML writer later prefers the shorthand as its readable
   vocabulary is a separate decision, taken once a YAML writer exists.

## Consequences

1. Kit `values-0008` becomes active: `[1, 2, 3]`, `true`, and `42` are `accepted` fences whose canonicals are the
   wrapped forms; `Tuple: [1, 2]` is pinned as the only tuple spelling, and a bare `[1, 2]` under a `Tuple` case
   is `rejected` with `expect=List`.
2. The schema's `Value` union keeps its scalar and array arms; the notes on `TupleValue` and `ListValue` are
   rewritten to say a bare array is a list.
3. The reference codec's `ambiguous_shorthand` rejections for bare booleans, numbers, and arrays are replaced by
   the expansions above.

## Revisit when

- Real models show tuple density in value position high enough that a YAML-only `!tuple` tag pays for itself.
