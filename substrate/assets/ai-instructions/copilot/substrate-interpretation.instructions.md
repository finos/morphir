---
applyTo: "**/*.md"
description: "How to annotate Substrate markdown documents with `substrate:` YAML blocks so the interpretation view can render them."
---

# Substrate interpretation — instructions for GitHub Copilot

Substrate markdown documents become executable when each meaningful
section carries a fenced `substrate:` YAML block describing its types
and values. This file tells you how to produce those blocks from prose.

The canonical example is
`examples/trade-auto-approval-risk-logic/original.md`. The AST spec is
`specs/language/interpretation-ast.md`. The authoritative grammar is
the parser at `web/src/substrate/parse.ts` and the type definitions at
`web/src/substrate/ast.ts`.

## When to add YAML

Add a `substrate:` YAML block to a markdown section when the prose
contains domain meaning the interpretation view should render:

- type enumerations ("we handle equities, bonds, and derivatives"),
- rules / formulas ("approve if the risk score is under 0.5"),
- decision logic that branches on a type variant or a predicate.

Skip narrative, history, motivation, and meta sections. One markdown
file may carry several `substrate:` blocks — one per meaningful section.

Never edit or rephrase the prose to fit the YAML. The prose is the
source of truth; the YAML is its interpretation.

## Block shape

````markdown
```yaml
substrate:
  types:
    <type-name>:
      one-of:
        - tag: <variant>
          src: "<exact phrase from prose>"
      src: "<exact phrase from prose>"
  values:
    <value-name>:
      # either an inline expression…
      match:
        on: <variable>
        cases:
          - when: <variant>
            then: <expression>
            src: "<exact sentence from prose>"
      # …or the explicit form with params + body
      params: [a, b]
      body:
        multiply: [a, b]
      src: "<exact phrase from prose>"
  src: "<phrase justifying the section as a whole>"
```
````

### Expressions

- **Literal**: a bare scalar (`true`, `0.5`, `"hello"`, `null`). Use
  `lit: <value>` when you need to be explicit. Numbers may use thousands
  separators (`1,000,000`).
- **Variable**: unquoted identifier (`risk_score`, `notional`). Quoted
  strings are always string literals — never quote a variable. Explicit
  form: `var: name`.
- **If**: `{ if: <cond>, then: <expr>, else: <expr> }`.
- **Match**: `{ match: { on: <expr>, cases: [{ when, then }] } }`.

### Operators (closed set)

- Binary (`[left, right]` or `{ left, right }`): `equals`, `not-equals`,
  `less-than`, `less-than-or-equal`, `greater-than`,
  `greater-than-or-equal`, `add`, `subtract`, `multiply`, `divide`,
  `contains`, `starts-with`, `ends-with`.
- Unary (single operand): `not`.
- N-ary (sequence of operands): `and`, `or`, `concat`.

Aliases also accepted: `all-of` → `and`, `any-of` → `or`, `eq`, `neq`,
`lt`, `lte`, `gt`, `gte`. Prefer the long forms; they read better.

There is no `between`, `in`, `length`, etc. Compose with the primitives.

## `src:` — extract every phrase you can

The `src` field is the deliverable, not an afterthought. The interpretation
viewer renders each `src` entry as a hover-linked anchor between the AST
node and the prose. Every node should have one when prose supports it.

- The value of `src` must be an **exact substring of the prose** — never
  a paraphrase. Either a single string or a YAML sequence of strings.
- Anchor at the right level: the `match` case carries the full sentence
  for that case; the inner predicate carries just the predicate clause.
- Variants carry the noun the prose used (`"equities"`, `"bonds"`).
- Literal thresholds carry the phrase that names them
  (`"under one million"`).
- If no phrase supports a node, omit `src:`. Do not invent one.

## Names

Type names, value names, and variant tags use kebab-case identifiers
matching `^[A-Za-z_][A-Za-z0-9_-]*$`. Pick names that mirror the prose
(`auto-approve`, `risk_score`, `asset`).

## Anti-patterns

- Inventing variants or fields the prose doesn't mention.
- Using `src:` to describe the node instead of quoting the prose.
- Quoting a variable reference (turns it into a string literal).
- Replacing `match` / `if` structure with one giant `and:`.
- Using operators outside the closed set.
- Omitting `src:` because "the structure is obvious".

## Validating

`npm run dev:web` boots the interpretation view; the diagnostics panel
flags structural problems. The parser never throws — a broken block
degrades gracefully — but resolve every diagnostic before declaring the
file done.
