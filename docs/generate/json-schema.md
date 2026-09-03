---
title: Generate JSON Schema
sidebar_label: JSON Schema
sidebar_position: 2
---

# Generate JSON Schema

> The OpenAPI and JSON Schema backend ships as one WASM release bundle from
> [finos/morphir-rust](https://github.com/finos/morphir-rust/releases), tagged
> `extension/openapi/v<version>`. There is no public extension index yet, so
> you publish the bundle into a local repository with
> `morphir extension repository publish` and install from it. This guide also
> covers the contract for a locally built extension. Rename the downloaded
> `<artifact>.release.json` to `release.json` before publishing.

The `morphir-openapi` WASM extension turns public Morphir types into JSON
Schema 2020-12 documents. It also renders OpenAPI documents; see
[Generate OpenAPI](./openapi.md). Both targets come from the one
`morphir-openapi` extension, installed once. This guide covers the
`json-schema` target: `openapi` is documented separately because it adds
paths, operations, and a document-version choice that JSON Schema has no use
for.

The extension accepts Morphir IR v3 and v4. It projects public type
definitions. It does not evaluate Morphir values or translate computation.

## Install the published extension

Release bundles are published from
[finos/morphir-rust](https://github.com/finos/morphir-rust/releases) under
the tag `extension/openapi/v<version>`. Each release carries three assets: the
`.wasm` artifact, its `.sha256` checksum, and a `<artifact>.release.json`
descriptor. There is no public extension index yet, so you publish the bundle
into a local repository and install from it.

Download the assets into one directory, rename the descriptor to
`release.json`, and keep only those three files in the directory:

```console
mkdir -p bundles/openapi
gh release download extension/openapi/v0.1.0 -R finos/morphir-rust --dir bundles/openapi
mv bundles/openapi/*.release.json bundles/openapi/release.json
```

Then create a repository, register it, publish the bundle, and install:

```console
morphir extension repository init repositories/local
morphir extension repository add local --directory repositories/local
morphir extension repository publish local --bundle bundles/openapi
morphir extension install --repository local morphir-openapi
morphir extension list
```

`publish` verifies the SHA-256 in `release.json` against the artifact and the
checksum file before it writes anything. The descriptor's `targets` list
carries both `openapi` and `json-schema` into the repository record, so one
installed extension serves both. `install` verifies the artifact again, stores
the module by content digest, and writes matching lock and catalog state. After that the extension runs offline: the repository
directory is only needed to install or update.

Set `MORPHIR_HOME` to an empty directory first to keep this out of your
regular home, and keep the same value when running generation.

## Build and install a local extension

Contributors can build the bundle from `ecosystem/morphir-rust` with its
packaging task and publish it the same way. The task writes `release.json`,
the artifact, and the checksum into one directory:

```console
mise run extension:artifact:openapi
```

Publish `.morphir/build/extensions/openapi` with
`morphir extension repository publish` as shown above. These commands
do not publish the extension anywhere public.

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
`paths`, which JSON Schema documents never have. Option decoding runs before
the backend looks at the target, so a value one of these options accepts is
decoded and validated the same way for both targets; it is only the later use
of `projection`, `result_responses`, and `operations` to build `paths` that is
skipped for `json-schema`. A valid but target-irrelevant value — for example
`--option projection=operations-public --target json-schema` — is simply
ignored. An *invalid* value is not: `error_status` outside 400 through 599,
or an `operations` override `path` not starting with `/`, still fails
generation with `JSC002` regardless of `--target`. See
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

`kind` is reserved for the same reason: a custom type with payload
constructors carries a `kind` discriminator, so a constructor argument that
projects to the property name `kind` would have to be both the argument and
the discriminator. That is a `JSC003` naming the constructor; rename the
argument.

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
