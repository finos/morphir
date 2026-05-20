# Interpretation AST

The interpretation view in the substrate dev UI is driven by a typed
abstract syntax tree (AST) derived from a markdown document. The AST is
the target representation that an LLM (or human) produces by reading
the prose and structured `substrate:` YAML blocks, and that the viewer
renders as a side-by-side visualisation.

This document describes the AST. The parser that turns the authored
YAML into AST lives in `src/substrate/parse.ts`; the type definitions
are in `src/substrate/ast.ts`. Both files are imported by the Vite SPA
under `web/` and by the CLI (notably `substrate write interpretation`),
so authoring and rendering go through one parser.

## Module

A `Module` is the entry point. It has two maps from name to definition:

- `types: Map<string, TypeDefinition>` — type definitions keyed by name.
- `values: Map<string, ValueDefinition>` — value definitions keyed by name.

A module also carries its own list of source locations (see below), and
an optional `lastInterpretedAt: Date` recording when the interpretation
was last reviewed against the prose.

## Freshness: `last-interpreted-at`

The module mapping may carry a `last-interpreted-at` key immediately
under `substrate:`. Its value is an ISO-8601 timestamp (parsed via
`new Date(...)`) recording when an author or LLM last reconciled the
interpretation with the surrounding prose and section descriptions.

```yaml
substrate:
  last-interpreted-at: "2026-05-18T10:30:00Z"
  types: ...
  values: ...
```

The dev viewer compares this timestamp against the markdown file's
last-modified mtime: if the markdown was edited after the recorded
review timestamp, the interpretation is flagged as **Outdated** in the
UI. Both timestamps are compared at full resolution, not just date.

When the key is absent, the viewer makes no claim about freshness.

## Source locations

Every AST node carries `src: SourceLocation[]`. A `SourceLocation` is:

- `file` — the markdown file the YAML block came from.
- `sectionId` — the nearest heading anchor in that file.
- `text` — the exact prose span that supports the node.

A node may have multiple anchors (multi-paragraph definitions are
common). In the authored YAML the `src` key may be a single string or
a sequence of strings:

```yaml
src: "exact prose phrase"
# or
src:
  - "first supporting phrase"
  - "second supporting phrase"
```

The viewer renders each anchor as a hover-linked pairing between the
visual element and the prose span.

## Type definitions

The only type definition kind currently supported is `one-of`. A
`one-of` has an ordered list of `Variant`s. Each variant has a `name`,
an optional `payload` (a `TypeRef` referring to another type by name),
and its own source locations.

```yaml
types:
  asset:
    one-of:
      - tag: equity
        src: "equities"
      - tag: bond
        src: "bonds"
    src: "type of asset"
```

A bare-string variant is shorthand for `{ tag: <name> }`.

## Value definitions

A `ValueDefinition` has:

- `params: string[]` — formal parameter names (may be empty).
- `body: ValueExpression` — the expression.
- `src: SourceLocation[]`.

A value entry whose body is given inline (no explicit `params`/`body`
keys) is treated as a zero-parameter definition. The explicit form is:

```yaml
values:
  area:
    params: [width, height]
    body:
      multiply: [width, height]
```

## Value expressions

A `ValueExpression` is one of:

- **Literal** — `literal-string`, `literal-number`, `literal-boolean`,
  `literal-null`.
- **Variable** — `{ kind: "variable", name }`. Bare YAML identifiers
  matching `^[A-Za-z_][A-Za-z0-9_-]*$` are parsed as variables; quoted
  strings are always string literals.
- **If** — `{ condition, then, else }`. In YAML: a mapping with `if`,
  `then`, and `else` keys.
- **Match** — `{ on, cases: [{ when, then }] }`.
- **Apply** — operator applications (below).

## Apply: operator applications

`Apply` is a discriminated union — one variant per operator. Adding a
new operator means adding a variant, not a string registry lookup.

Operators fall into three structural categories:

- **Binary** (carry `left` and `right`): `equals`, `not-equals`,
  `less-than`, `less-than-or-equal`, `greater-than`,
  `greater-than-or-equal`, `add`, `subtract`, `multiply`, `divide`,
  `contains`, `starts-with`, `ends-with`.
- **Unary** (carry `operand`): `not`.
- **N-ary** (carry `args[]`): `and`, `or`, `concat`.

YAML forms for binary operators:

```yaml
equals: [a, b]
# or
equals:
  left: a
  right: b
```

Aliases recognised by the parser: `all-of` → `and`, `any-of` → `or`,
plus the conventional short forms `eq`, `neq`, `lt`, `lte`, `gt`,
`gte`.

## Diagnostics

Parsing never throws. The parser returns:

```ts
ParseResult = { module?: Module; diagnostics: ParseDiagnostic[] }
```

A YAML-level syntax error yields an empty `module` and one or more
error diagnostics. Semantic errors in individual nodes (unknown
operator key, wrong arity, missing required field) leave the rest of
the module intact — one broken value definition does not blank the
view. Each diagnostic carries `severity` (`error` or `warning`), a
`message`, optional line/column `position`, and an optional `path`
through mapping keys / sequence indexes to the offending node.

The viewer surfaces diagnostics through a dedicated panel above the
visualisation.
