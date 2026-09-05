---
type: Decision Record
title: DocumentLiteral is in v4, with a raw payload and a deliberately small SDK
description: "IR v4.0.0 adds DocumentLiteral, a seventh literal holding a schema-less JSON-like tree typed as the opaque SDK type morphir/SDK:document#document; its payload is the document verbatim, it cannot be pattern matched, it refuses to downgrade, and the SDK exposes construction, inspection and navigation but no merge, equality or ordering."
state: Accepted
decided: 2026-09-04
tags: [ir, ir-v4, literal, document, sdk, mck]
status: draft
---

# DocumentLiteral is in v4, with a raw payload and a deliberately small SDK

v4.0.0 adds a seventh literal, `DocumentLiteral`, whose value is a schema-less tree of `null`, booleans, integers,
floats, strings, arrays, and string-keyed objects. Its type is the opaque SDK type `morphir/SDK:document#document`.
No `Type` variant and no `Value` variant are added.

```yaml
Literal:
  DocumentLiteral:
    type: user
    id: 12345
    roles: [admin, editor]
    settings:
      theme: dark
      notifications: true
    note: null
```

| Option | Outcome | Why |
| ------ | ------- | --- |
| Raw JSON payload, no `Doc*` wrappers | Chosen | Inside a `DocumentLiteral` everything is data, so raw JSON has one expansion; the wrappers are the ambiguous form (a document key named `DocInt`) |
| Explicit `Doc*` wrappers canonical, raw JSON as a shorthand (the design draft) | Rejected | Two spellings where one is unambiguous; the wrapper spelling can misread a document |
| Defer the feature to a later v4 revision | Rejected | The type gives boundary data an honest representation now; every mirror already carries a JSON tree |
| A `Type` variant instead of an SDK type | Rejected | Complicates the closed `Type` sum for no operation a reference cannot express |

## Why

Morphir carries business logic between platforms with the types intact, and every deployment has edges where the
data has no agreed shape: an API response before validation, configuration, metadata tooling reads and the model
does not. Without a representation, models fake a record they do not believe in or keep that code outside Morphir.
An opaque `Document` with total accessors (`get` and `asInt` return a `Maybe`) names the edge and still forces the
model to say what happens when the shape is not what it hoped, which is the discipline Elm's `Json.Decode.Value`
imposes.

The feature is an escape hatch, and escape hatches get used to avoid modeling. The encoding cannot prevent that;
the SDK's surface and the tooling can discourage it, which is why the SDK is kept to construction, inspection, and
navigation.

The literal is the smaller half. Construction is what the SDK functions are for; a literal is needed to embed
constants, mostly configuration and fixtures. Given the type, the literal is the consistent way to write one.

## Rules

1. The payload of `DocumentLiteral` is the document verbatim. Scalars resolve as in
   [decision 0009](/decisions/0009-bare-arrays-are-lists-and-bare-scalars-are-literals-at-value-position.md): YAML
   1.2 core schema only; a number is an integer when its lexeme has no point or exponent, else a float, and the
   lexeme is preserved. Object keys are arbitrary strings; order is preserved; duplicates are rejected by the parser.
2. `LiteralPattern` does not admit `DocumentLiteral`. Documents are inspected through the SDK, not matched by deep
   equality.
3. A v4-to-v3 writer refuses a `DocumentLiteral` with the same diagnostic it uses for `Hole`.
4. The SDK module `Morphir.SDK.Document` provides `null`, `bool`, `int`, `float`, `string`, `array`, `object`,
   `asBool`, `asInt`, `asFloat`, `asString`, `asArray`, `asObject`, `get`, `getPath`, `isNull`, `isBool`, `isInt`,
   `isFloat`, `isString`, `isArray`, `isObject`, `encode`, and `decoder`, as specifications with native bodies. It
   provides no `merge`, no equality, and no ordering in 4.0.0.
5. The design draft's optional extensions (`DocBinary`, `DocTimestamp`, `DocDecimal`, `DocReference`) are not in
   4.0.0.
6. Visualizers render a document as opaque.

## Consequences

1. `Literal` gains one member in the reference model, Rust, Gleam, and Python; morphir-elm gains
   `Morphir.SDK.Document` before any frontend can emit a document-typed value (a morphir-elm follow-up, not a codec
   blocker).
2. The what's-new page's "Literals: same as V3" becomes seven literals; the design page's `Doc*` encoding section is
   rewritten to the raw payload.
3. Kit `patterns-and-literals-0005` pins the document above as canonical in both profiles, a large-integer lexeme
   case so backends that lose precision fail visibly, and a `rejected` fence for `LiteralPattern` on a document.
4. Bead `.7`'s remaining design-only features (layered decorations, `$meta`, `$ref`, `session.jsonl`) stay out of
   4.0.0 and are recorded separately.

## Revisit when

- A use case needs a document node kind beyond JSON's seven, at which point the extensions list is the place to
  start.
- Real models show documents used as a substitute for modeling, at which point a lint in the kit or the CLI is the
  remedy, not a change to the encoding.
