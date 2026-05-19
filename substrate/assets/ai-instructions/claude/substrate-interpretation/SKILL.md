---
name: substrate-interpretation
description: Annotate a Substrate markdown document with executable `substrate:` YAML blocks so the Substrate dev UI's interpretation view can render it. Trigger whenever the user wants to interpret, annotate, or "add YAML" to a markdown file, asks for a substrate AST from prose, or says things like "make this interpretable", "fill in the YAML", "produce the substrate interpretation".
---

# Substrate interpretation

Substrate documents are plain markdown. The **interpretation view** in
the `substrate dev` UI renders a typed AST (types and values) side-by-side
with the prose, but only if the document carries fenced `substrate:` YAML
blocks. This skill is how you produce those blocks from prose.

## When to reach for this skill

Use it when the user:

- Hands you a markdown file (or section) and asks you to **interpret**,
  **annotate**, **add YAML**, **make it executable**, or **make it show
  up in the interpretation view**.
- Wants the prose-driven substrate AST (types + values) reverse-engineered
  from a narrative description.
- Asks for a "substrate YAML" block, a "one-of", a `match`, an `if/then/else`,
  or any operator expression derived from English.

Do **not** invent prose. Only emit YAML that is grounded in what the
markdown already says. The whole point of the `src:` keys is to prove
every node in the AST traces back to a literal phrase in the prose.

## The output contract

For each markdown section that contains domain meaning (a type
enumeration, a rule, a formula, a piece of decision logic), append a
fenced YAML block of the form:

````markdown
```yaml
substrate:
  types: { ... }
  values: { ... }
```
````

Rules:

1. **One file, possibly many blocks.** Put each block in the section
   whose prose it interprets. The dev UI concatenates blocks per file.
2. **Don't restate the prose.** Leave the markdown text intact. The YAML
   block is added *after* the prose it interprets.
3. **Cover what makes sense.** Sections that are pure narrative, history,
   or motivation typically have no YAML. Sections that enumerate cases,
   define a calculation, or describe a decision rule do.
4. **Every node carries `src:`.** Extract as much `src` information as
   possible. The `src` value is an **exact substring of the prose** —
   not a paraphrase. Prefer the shortest phrase that uniquely supports
   the node. A node may have a single string `src:` or a YAML sequence
   of strings when more than one phrase supports it.
5. **Names are kebab-case identifiers.** Type names, value names, and
   variant tags use `^[A-Za-z_][A-Za-z0-9_-]*$`. Variable references
   (parameters, fields the prose mentions) are bare identifiers; string
   data is quoted.

## Canonical example

The following short document exercises every construct in one piece —
a `one-of` type, a `match` over its variants, nested `if` / operator
expressions, numeric literals, variable references, and `src:` anchors
at every level. Study it before writing your first block.

````markdown
# Trade Auto-Approval Risk Logic

## Overview

We need to build some basic logic for auto-approving trades based on
the type of asset being traded. For now, we're dealing with equities,
bonds, and derivatives. Each type has a different risk profile, so the
approval logic should reflect that. Equities should be auto-approved
if their risk score is under 0.5. Bonds are more conservative, so only
auto-approve if the risk score is under 0.3. For derivatives, we want
to auto-approve only if the notional is under one million and the
leverage is less than 2.

```yaml
substrate:
  types:
    asset:
      one-of:
        - tag: equity
          src: "equities"
        - tag: bond
          src: "bonds"
        - tag: derivative
          src: "derivatives"
      src: "type of asset"
  values:
    auto-approve:
      match:
        on: asset
        cases:
          - when: equity
            then:
              - if:
                  less-than:
                    - risk_score
                    - 0.5
                  src: "risk score is under 0.5."
                then: true
                else: false
            src: "Equities should be auto-approved if their risk score is under 0.5."
          - when: bond
            then:
              - if:
                  less-than:
                    - risk_score
                    - 0.3
                  src: "risk score is under 0.3."
                then: true
                else: false
            src: "Bonds are more conservative, so only auto-approve if the risk score is under 0.3."
          - when: derivative
            then:
              - if:
                  all-of:
                    - less-than:
                      - notional
                      - 1,000,000
                    - less-than:
                      - leverage
                      - 2
                  src: "notional is under one million and the leverage is less than 2"
                then: true
                else: false
            src: "For derivatives, we want to auto-approve only if the notional is under one million and the leverage is less than 2."
        src: "Each type has a different risk profile"
```
````

Notice how every variant, every comparison, and every case carries its
own `src:` quoting the exact phrase from the prose above.

## The YAML shape

### Module skeleton

```yaml
substrate:
  types:
    <type-name>: <type-definition>
  values:
    <value-name>: <value-definition>
  src: "phrase that justifies the module / section as a whole"
```

`src:` is optional at every level but should be filled in wherever a
phrase in the prose justifies the node.

### Type definitions — `one-of`

The only supported type kind is `one-of` (a tagged union / enum):

```yaml
types:
  asset:
    one-of:
      - tag: equity
        src: "equities"
      - tag: bond
        src: "bonds"
      - tag: derivative
        src: "derivatives"
    src: "type of asset"
```

A bare-string variant (`- equity`) is shorthand for `{ tag: equity }`.
Prefer the mapping form so each variant carries its own `src:`.

### Value definitions

A zero-parameter value is just an expression:

```yaml
values:
  auto-approve:
    match:
      on: asset
      cases:
        - when: equity
          then: true
```

A value with parameters uses the explicit form:

```yaml
values:
  area:
    params: [width, height]
    body:
      multiply: [width, height]
    src: "area is width times height"
```

### Expressions

A `ValueExpression` is one of:

- **Literal**: a bare scalar (`true`, `0.5`, `"hello"`, `null`). Numbers
  with thousands separators are accepted (`1,000,000`). For ambiguity-free
  intent, use the explicit `lit:` form: `lit: 0.5`.
- **Variable**: an unquoted identifier matching
  `^[A-Za-z_][A-Za-z0-9_-]*$` is a variable reference (e.g. a parameter
  or a field name the prose mentions like `risk_score`, `notional`,
  `leverage`). Quoted strings are **always** string literals. The
  explicit form is `var: name`.
- **If**: a mapping with `if`, `then`, `else`.
  ```yaml
  if:
    less-than: [risk_score, 0.5]
    src: "risk score is under 0.5"
  then: true
  else: false
  ```
- **Match**: a mapping with `match: { on, cases: [{ when, then }] }`.
- **Apply**: one operator key per expression.

### Operators

Operators are a closed, discriminated set. Use only these keys:

- **Binary** (sequence of two operands, or `{ left, right }`):
  `equals`, `not-equals`, `less-than`, `less-than-or-equal`,
  `greater-than`, `greater-than-or-equal`, `add`, `subtract`,
  `multiply`, `divide`, `contains`, `starts-with`, `ends-with`.
- **Unary** (single operand): `not`.
- **N-ary** (sequence of operands): `and`, `or`, `concat`.

Aliases the parser also accepts: `all-of` → `and`, `any-of` → `or`,
`eq`, `neq`, `lt`, `lte`, `gt`, `gte`. Prefer the long, English forms
(`and`, `less-than`) — they read better next to the prose.

Examples:

```yaml
equals: [status, "approved"]

all-of:
  - less-than: [notional, 1,000,000]
  - less-than: [leverage, 2]

not:
  equals: [side, "sell"]
```

## Extracting `src` — the heart of the skill

`src` is what makes interpretation valuable. The viewer renders each
`src` entry as a hover-linked anchor between the visual element and the
prose span, so every node should point to the prose that justifies it.

When deciding what `src` to attach:

- **Use a literal substring of the prose.** Do not rephrase. If the
  prose says "risk score is under 0.5.", the `src` is
  `"risk score is under 0.5."` — keep the trailing period or omit it
  consistently, but never invent words.
- **Anchor at the right level.** The `src` on a `match` case is the
  full sentence describing that case. The `src` on the inner condition
  is just the predicate clause inside that sentence.
- **Attach multiple anchors when prose supports a node from several
  places.** Use a sequence:
  ```yaml
  src:
    - "first supporting phrase"
    - "second supporting phrase"
  ```
- **Anchor variants too.** Each `one-of` variant should carry the
  noun the prose used: `equities`, `bonds`, `derivatives`.
- **Anchor literal thresholds.** When the prose says "under one million",
  attach that phrase to the `less-than` apply, not just to the
  enclosing case.

If a node has no supporting prose, omit `src:` for that node rather than
faking one. A missing `src` is honest; a wrong `src` is misleading.

## Workflow

When the user points you at a markdown file:

1. **Read the file end to end first.** Build a mental model of what
   types and values it implies before writing any YAML.
2. **Identify the type enumerations.** Phrases like "we deal with X, Y,
   and Z", "there are three kinds of …", "the status can be …" become
   `one-of` types.
3. **Identify the rules / formulas / decisions.** Each becomes a value
   definition. Decision-by-case (per type variant) becomes a `match`.
   Threshold rules become `if` / operator chains.
4. **Pick names that match the prose.** If the prose says
   "auto-approve", the value is `auto-approve`. If a field is referred
   to as "risk score", use `risk_score` (or `risk-score`) consistently.
5. **Draft the YAML block(s).** One block per markdown section that
   carries meaning. Place each block at the end of its section.
6. **Walk back over every node and attach `src:` from the prose.** This
   is not an afterthought — it is the deliverable. If you can't find a
   phrase to support a node, ask whether the node should exist.
7. **Sanity-check operator arity.** Binary ops want exactly two
   operands; `not` wants one; `and` / `or` / `concat` want a sequence.
8. **Verify in the dev UI when possible.** The `substrate dev` command
   boots the interpretation view; its diagnostics panel will surface any
   structural mistakes. The parser never throws — broken blocks degrade
   gracefully, but you should still resolve diagnostics before declaring
   done.

## Anti-patterns

- Inventing fields or variants the prose doesn't mention.
- Using `src:` to *describe* the node ("the equity case") instead of
  quoting the prose.
- Wrapping everything in a single giant `and:` instead of letting the
  `match` / `if` structure mirror the prose.
- Quoting bare identifiers (`"risk_score"`) — that makes them string
  literals, not variable references.
- Using operators not in the closed set above. There is no `between`,
  no `in`, no `length`. Express them with the primitives (`and` of two
  comparisons; `or` of `equals`; etc.).
- Skipping `src:` because "the structure is obvious". The whole point
  of interpretation is the anchored link back to prose.
