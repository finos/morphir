---
title: OpenAPI and JSON Schema backend
sidebar_label: OpenAPI and JSON Schema
sidebar_position: 3
---

# OpenAPI and JSON Schema backend

**Status:** Accepted; not released.

This proposal defines the second backend built on the portable WASM extension
runtime described in the [WASM extension runtime and Avro backend
proposal](./wasm-extension-runtime-and-avro-backend.md). It spans
`ecosystem/morphir-rust` alone: the runtime, distribution, and installation
boundary that proposal established is reused unchanged. It is not yet a
released user feature. APIs may receive implementation-driven refinements
before release, but the boundaries and behavior described here are the
accepted design.

## What this design establishes

One extension crate, `morphir-openapi-extension`, advertises two generation
targets from the Morphir Extension Protocol capability negotiation:

```json
{"backend":{"targets":["openapi","json-schema"],"irVersions":["3","4"]}}
```

Both targets share one normalization step and one schema projection, so a
Morphir type has the same schema whether it is reached through
`--target json-schema` or through `components/schemas` in an
`--target openapi` document. `json-schema` renders standalone JSON Schema
2020-12 documents, one per public root type. `openapi` additionally
synthesizes `paths` operations from public value specifications, under a
configurable projection mode, and can render either OpenAPI 3.1 or an OpenAPI
3.0 document downgraded from the same 3.1 build. One installed extension,
`morphir-openapi`, serves both targets; there is no separate installation
step per target.

## Extension boundary

`morphir-openapi-extension`'s projection and rendering core is pure native
Rust, adapted to MEP by a thin `wasm32` guest, matching the shape
`morphir-avro-extension` already established. Its pipeline is:

```text
v3 or v4 IR -> normalized projection -> dialect-neutral Schema model
          -> JSON Schema or OpenAPI renderer -> MEP artifacts and diagnostics
```

The dialect-neutral `Schema` model is the seam between projection and
rendering: `render::json_schema` and `render::openapi` both consume it and
share the same schema-body conversion, differing only in the base a `$ref` is
written against (`#/$defs/` versus `#/components/schemas/`). The `openapi`
renderer always builds an OpenAPI 3.1 document first and, when
`options.version` asks for 3.0, rewrites that finished document — one
projection, one document builder, so the two versions cannot drift apart.

The extension projects types and value specifications. It does not evaluate
constants, translate computation, or serve as an API gateway, mock server, or
request validator.

## Projection modes

`options.projection` selects the public-model surface an OpenAPI document
carries. `json-schema` output is unaffected by this option, since it never
has `paths`.

| Mode | `components/schemas` | `paths` |
| --- | --- | --- |
| `schemas` | Public type roots | Empty object |
| `operations-entry-points` | Public type roots, plus any type an operation reaches | Declared entry points from a v4 Application only |
| `operations-public` | Public type roots, plus any type an operation reaches | Every public value specification |

Every selected value specification starts from one default HTTP mapping —
`POST`, path `/<module>/<value>`, arguments as a request-body object, the
output type as the `200` response — before `options.operations` applies a
per-FQName override to the method, the path, or individual parameter
bindings (`path`, `query`, `header`, `body`). `options.result_responses`
additionally decides whether a `Result`-shaped output stays one `200` body or
splits into a `200` success response and an error response at
`options.error_status`.

## Type projection

The projection uses `UpperCamelCase` for schema names, `lowerCamelCase` for
field names and `operationId`s, and keeps the source Morphir FQName as an
`x-morphir-fqname` extension on every named schema. Names are pure functions
of the canonical FQName, never of traversal order, so two declarations that
would collide on the same schema name produce a diagnostic rather than a
silent rename.

| Morphir form | Schema representation |
| --- | --- |
| `Bool`, `Int`, `Float`, `String` | `boolean`, `integer` (`int64`), `number` (`double`), `string` |
| `Char` | `string` with `maxLength: 1` |
| `Unit` | `{"type": "null"}` |
| `Maybe a` | `anyOf` of the projection of `a` and `null` |
| `List a` | Array |
| `Set a` | Array with `uniqueItems: true` |
| `Dict String a` | Object with `additionalProperties` |
| Record alias | Object with `properties` and `required` |
| Nullary custom type | Single-value string `enum` |
| Custom type with payload constructors | `oneOf`, each variant an object with a `kind` discriminator fixed by `const` |
| Tuple | Array with `prefixItems`, `items: false`, and matching `minItems`/`maxItems` |
| `Result error value` | `oneOf` of an `Err` object and an `Ok` object, both tagged by `kind` — or, in a split operation response, the `Ok` and `Err` members projected independently |

The backend cannot safely project a function used as data, an open
extensible record, an opaque or incomplete type, an unbound type parameter,
an unresolved type reference, or a `Dict` with a non-`String` key.

## Configuration and diagnostics

Backend options live under `[codegen.<target>]`, keyed by the exact target
name — `[codegen.json-schema]` or `[codegen.openapi]` — since both targets
come from the same extension but read independent option tables:

```toml
[codegen.openapi]
unsupported = "error"
version = "3.1"
projection = "operations-public"
result_responses = "split"
error_status = 422

[codegen.openapi.operations."acme/customer:domain#find-customer"]
method = "get"
path = "/customers/{id}"

[codegen.openapi.operations."acme/customer:domain#find-customer".parameters]
id = "path"
```

Precedence is guest defaults, then `[codegen.<target>]`, then repeatable CLI
`--option` values. The last CLI value wins. Each CLI value parses as JSON
when valid, otherwise as a string. The host transports options generically;
the guest validates `snake_case` keys, values, types, and ranges.

| Option | Values and default |
| --- | --- |
| `unsupported` | `error` by default; `warn-and-skip` |
| `version` | `3.1` by default; `3.0` |
| `projection` | `schemas` by default; `operations-entry-points`, `operations-public` |
| `result_responses` | `data` by default; `split` |
| `error_status` | `400` by default; any integer from 400 through 599 |
| `operations` | Empty map by default; per-FQName method, path, and parameter overrides |

`warn-and-skip` drops an unprojectable public form — a type, a value
specification, or an operation whose request or response reaches a form
dropped elsewhere — and emits a deterministic warning at its Morphir FQName,
returning only artifacts that remain independently valid. Strict mode emits
no artifacts if any projection error occurs.

| Code | Meaning |
| --- | --- |
| `JSC001` | Unsupported generation target |
| `JSC002` | Invalid backend option |
| `JSC003` | Unsupported Morphir form |
| `JSC004` | Schema name collision |
| `OAS001` | Operation path or `operationId` collision |
| `OAS002` | Invalid `operations` override |

`OAS001` and `OAS002` are always errors, regardless of `unsupported`: both
name a mistake in the Morphir source or the configuration itself — an
ambiguous projected package, or an override that describes an operation that
cannot exist as written — rather than a form the backend cannot represent.

## Distribution and release ownership

`morphir-rust` builds the extension and owns its publication, exactly as it
does for `morphir-avro-extension`. The registry entry, the packaging task, and
independent release routing for `morphir-openapi` are checked into
`ecosystem/morphir-rust`: `[extensions.openapi]` in `.github/extensions.toml`
and `.mise/tasks/extension/artifact/openapi`, invoked as
`mise run extension:artifact:openapi`. No release has been published and there
is no public extension index yet, so the guides linked below build the bundle
with that task and turn its `release.json` into a schema-v2 local index
record, the same way `morphir-avro-extension`'s guide does.

## Implementation workstreams

The work follows the same split the Avro proposal used, reusing its runtime
rather than repeating it:

1. Backend option surface: `unsupported`, `version`, `projection`,
   `result_responses`, `error_status`, and `operations`, decoded and
   validated independently of any one projection mode.
2. Shared schema projection and the OpenAPI 3.1 renderer, extracted from the
   JSON Schema renderer's already-parameterized schema-body conversion so
   the two dialects cannot drift.
3. Operation synthesis: the default HTTP mapping, per-operation overrides,
   and `Result` splitting.
4. The OpenAPI 3.0 downgrade pass, applied to the finished 3.1 document
   rather than re-projected.
5. CLI proof through an installed guest, and this documentation.

## Testing and acceptance

Acceptance covers native Rust unit and golden tests for the projection core
and both renderers; byte-pinned goldens for every public root the shared
fixture declares; downgrade coverage proving every 2020-12-only form (`type`
arrays, the scalar `type: "null"`, `prefixItems`, `$defs`) is absent from a
3.0 document and that every `$ref` still resolves inside
`components/schemas`; operation coverage for the default mapping, overrides,
collisions, and `warn-and-skip` sweep-through; validation of every rendered
OpenAPI document against the published OpenAPI metaschema for the version it
claims, 3.1 and 3.0 alike, so a golden is checked by a real parser rather than
only against its own previous bytes; and the full MEP lifecycle against an
installed real guest through the CLI, proving one installed extension serves
both targets.

## Alternatives and non-goals

This design reuses the Avro proposal's choice of Extism plus MEP over a new
WIT contract, and its choice to share one runtime crate across backends
rather than build a dedicated CLI backend for OpenAPI or JSON Schema.

Building both dialects as one extension, rather than two, was a deliberate
choice: `openapi`'s `components/schemas` and `json-schema`'s documents
already needed the same projection and the same schema-body renderer, so
splitting them into separate extensions would only have duplicated that core
without changing what either target validates against.

This backend does not translate or evaluate value bodies, does not generate
an OpenAPI document that is guaranteed complete for every hand-authored REST
API (the default HTTP mapping is a starting point, not an inference of an
existing API's real routing), and does not validate the emitted documents
against a JSON Schema or OpenAPI meta-schema at generation time.

## References

- [OpenAPI Specification 3.1.0](https://spec.openapis.org/oas/v3.1.0)
- [OpenAPI Specification 3.0.3](https://spec.openapis.org/oas/v3.0.3)
- [JSON Schema 2020-12](https://json-schema.org/draft/2020-12/schema)
