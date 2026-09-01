---
title: Generate JSON Schema
sidebar_label: JSON Schema
sidebar_position: 2
---

# Generate JSON Schema

> The OpenAPI and JSON Schema backend is not released. This guide describes
> the current contract for testing a locally built and installed extension.
> Do not treat it as an announcement of an available release. There is no
> public extension index; installation uses a locally built extension and a
> local schema-v2 index, as shown below.

The `morphir-openapi` WASM extension turns public Morphir types into JSON
Schema 2020-12 documents. It also renders OpenAPI documents; see
[Generate OpenAPI](./openapi.md). Both targets come from the one
`morphir-openapi` extension, installed once. This guide covers the
`json-schema` target: `openapi` is documented separately because it adds
paths, operations, and a document-version choice that JSON Schema has no use
for.

The extension accepts Morphir IR v3 and v4. It projects public type
definitions. It does not evaluate Morphir values or translate computation.

## Build and install the local extension

There is no published `morphir-openapi` extension to install yet, and no
packaging task for it in `mise` either — that lands with the release
automation work. Build the WASM guest directly with `cargo`, then hand-write a
schema-v2 local index record for it. From the repository root, run:

```console
cargo build --locked --release \
  --manifest-path ecosystem/morphir-rust/Cargo.toml \
  -p morphir-openapi-extension --target wasm32-unknown-unknown
```

Then, from the `ecosystem/morphir-rust` directory, stage the guest and its
index record:

```console
guest=target/wasm32-unknown-unknown/release/morphir_openapi_extension.wasm
index=.morphir/build/index
mkdir -p "$index/artifacts" "$index/extensions"
cp "$guest" "$index/artifacts/morphir_openapi_extension.wasm"
sha256=$(shasum -a 256 "$guest" | cut -d' ' -f1)

cat > "$index/extensions/morphir-openapi.jsonl" <<JSON
{"schemaVersion":2,"id":"morphir-openapi","name":"Morphir OpenAPI","version":"0.1.0","channels":["stable"],"mepVersions":["0.1"],"capabilities":["backend"],"backend":{"targets":["openapi","json-schema"],"irVersions":["3","4"]},"artifacts":[{"runtime":"wasm","source":{"kind":"local-file","path":"artifacts/morphir_openapi_extension.wasm"},"sha256":"$sha256","filename":"morphir_openapi_extension.wasm","args":[],"executable":false}]}
JSON
```

The record's `backend.targets` lists both `openapi` and `json-schema`: one
installed extension serves both. Install it into an isolated contributor home
with the root CLI:

```console
MORPHIR_HOME="$PWD/.morphir/local-home" \
  mise exec -- cargo run --manifest-path ../../Cargo.toml -p morphir -- \
  extension install --index "$PWD/.morphir/build/index" morphir-openapi

MORPHIR_HOME="$PWD/.morphir/local-home" \
  mise exec -- cargo run --manifest-path ../../Cargo.toml -p morphir -- \
  extension list
```

Keep the same `MORPHIR_HOME` value when running generation. Installation
verifies the SHA-256 recorded in the index, stores the module by content
digest, and writes matching lock and catalog state. These commands do not
publish the extension.

## Run the generator

Once `morphir-openapi` is installed, generate JSON Schema documents with:

```console
morphir generate --target json-schema --input morphir-ir.json --output generated/json-schema
```

Backend options live under `[codegen.json-schema]` in `morphir.toml`:

```toml
[codegen]
targets = ["json-schema"]

[codegen.json-schema]
unsupported = "error"
```

Repeat `--option <KEY=VALUE>` to override that table for one command:

```console
morphir generate --target json-schema --option unsupported=warn-and-skip
```

The backend starts with its defaults, then applies `[codegen.json-schema]`,
then applies CLI options in command-line order. The last CLI value for a key
wins. The CLI parses a value as JSON when possible; otherwise it passes a
string. Option names use `snake_case`.

The `json-schema` target only ever reads `unsupported` — `version`,
`projection`, `result_responses`, `error_status`, and `operations` all shape
`paths`, which JSON Schema documents never have. Setting them alongside
`--target json-schema` is harmless; they are simply unused. See
[Generate OpenAPI](./openapi.md) for what each of them controls.

## Options and defaults

| Option | Accepted values | Default |
|---|---|---|
| `unsupported` | `error`, `warn-and-skip` | `error` |

Unknown options, wrong JSON types, and invalid enum values fail with
`JSC002`.

## Unsupported forms and partial output

The default `unsupported = "error"` is strict. Any projection error makes the
result unsuccessful and emits no artifacts. `warn-and-skip` omits the
unprojectable public form, emits a deterministic warning naming its Morphir
FQName, and returns only artifacts that remain independently valid.

The backend cannot safely project a function used as data, an open
extensible record, an opaque or incomplete type, an unbound type parameter, an
unresolved type reference, or a `Dict` with a non-`String` key.

## Type mapping

| Morphir form | JSON Schema representation |
|---|---|
| `Bool` | `{"type": "boolean"}` |
| `Int` | `{"type": "integer", "format": "int64"}` |
| `Float` | `{"type": "number", "format": "double"}` |
| `String` | `{"type": "string"}` |
| `Char` | `{"type": "string", "maxLength": 1}` |
| `Unit` | `{"type": "null"}` |
| `Maybe a` | `{"anyOf": [<a>, {"type": "null"}]}` |
| `List a` | `{"type": "array", "items": <a>}` |
| `Set a` | `{"type": "array", "items": <a>, "uniqueItems": true}` |
| `Dict String a` | `{"type": "object", "additionalProperties": <a>}` |
| Record alias | `{"type": "object", "properties": {...}, "required": [...]}` |
| Nullary custom type | `{"type": "string", "enum": [...]}` |
| Custom type with payload constructors | `{"oneOf": [...]}`, each variant an object carrying a `kind` discriminator fixed by `const` |
| Tuple | `{"type": "array", "prefixItems": [...], "items": false, "minItems": n, "maxItems": n}` |
| `Result error value` | `{"oneOf": [<Err object>, <Ok object>]}`, each member's own field (`error` or `value`) holding the projected type, discriminated by `kind` |

Every Morphir record field is present; optionality is carried by the field's
own type (typically `Maybe a`), not by omitting the field. Every named schema
carries an `x-morphir-fqname` extension holding its canonical Morphir source
name, and a `description` when the declaration has Morphir documentation.
Names are derived deterministically from the canonical Morphir FQName —
`UpperCamelCase` for a schema name, `lowerCamelCase` for a field name — never
from traversal order, so two declarations that would produce the same schema
name are `JSC004` name collisions rather than a silent rename.

A `Dict` with a non-`String` key has no object schema and fails with `JSC003`.

## Diagnostic codes

| Code | Meaning |
|---|---|
| `JSC001` | The host asked for a target this extension does not advertise |
| `JSC002` | A backend option was unknown, of the wrong type, or out of range |
| `JSC003` | A Morphir form has no safe schema projection |
| `JSC004` | Two projected declarations claimed the same schema name |

## File layout

One JSON Schema document is written per public root type. Its name is
`<module path, lowercased and dot-joined>.<SchemaName>.schema.json` — for
example, a `Customer` type declared in the `customer` module becomes
`customer.Customer.schema.json`. Each document is
self-contained: `$schema` is
`https://json-schema.org/draft/2020-12/schema`, `$id` is
`<SchemaName>.schema.json`, `title` is the schema name, and `$defs` holds
exactly the transitive closure of definitions the root's own `$ref`s reach —
no unused definition, no dangling reference.

For runtime boundaries and release status, see the accepted [WASM extension
runtime and Avro backend proposal](../design/proposals/wasm-extension-runtime-and-avro-backend.md)
and the [OpenAPI and JSON Schema backend proposal](../design/proposals/openapi-and-json-schema-backend.md).
