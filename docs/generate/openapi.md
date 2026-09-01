---
title: Generate OpenAPI
sidebar_label: OpenAPI
sidebar_position: 3
---

# Generate OpenAPI

> The OpenAPI and JSON Schema backend has no published release. The
> extension is registered for independent release and has its own packaging
> task, but no release has been cut and there is no public extension index,
> so installation uses a locally built bundle and a local schema-v2 index,
> as shown below. This guide describes the current contract for testing that
> locally built and installed extension. Do not treat it as an announcement
> of an available release.

The `morphir-openapi` WASM extension turns a public Morphir package into an
OpenAPI document: its public types become `components/schemas`, and,
depending on the chosen projection mode, its public value specifications
become `paths` operations. It also renders standalone JSON Schema documents;
see [Generate JSON Schema](./json-schema.md). Both targets come from the one
`morphir-openapi` extension, installed once — install it once and both
`--target openapi` and `--target json-schema` are available.

The extension accepts Morphir IR v3 and v4. It projects types and value
specifications. It does not evaluate Morphir values or translate computation.

## Build and install the local extension

There is no published `morphir-openapi` extension to install yet, and no
public extension index to install it from. Contributors build the bundle
with its packaging task, create a schema-v2 local index, and install from
that index. From the `ecosystem/morphir-rust` directory, run:

```console
mise run extension:artifact:openapi

bundle=.morphir/build/extensions/openapi
index=.morphir/build/index
mkdir -p "$index/artifacts" "$index/extensions"

python3 - "$bundle/release.json" "$index" <<'PY'
import json
import pathlib
import shutil
import sys

descriptor_path = pathlib.Path(sys.argv[1])
index = pathlib.Path(sys.argv[2])
descriptor = json.loads(descriptor_path.read_text(encoding="utf-8"))
artifact = descriptor["artifact"]
shutil.copy2(descriptor_path.parent / artifact, index / "artifacts" / artifact)

record = {
    "schemaVersion": 2,
    "id": descriptor["extensionId"],
    "name": "Morphir OpenAPI",
    "version": descriptor["version"],
    "channels": ["stable"],
    "mepVersions": descriptor["mepVersions"],
    "capabilities": ["backend"],
    "backend": {
        "targets": descriptor["targets"],
        "irVersions": descriptor["irVersions"],
    },
    "artifacts": [{
        "runtime": "wasm",
        "source": {"kind": "local-file", "path": f"artifacts/{artifact}"},
        "sha256": descriptor["sha256"],
        "filename": artifact,
        "args": [],
        "executable": False,
    }],
}

history = index / "extensions" / "morphir-openapi.jsonl"
history.write_text(json.dumps(record, separators=(",", ":")) + "\n", encoding="utf-8")
PY
```

`release.json` describes the release bundle, and its `targets` list carries
both `openapi` and `json-schema` straight through into the index record: one
installed extension serves both. The install command needs the schema-v2
JSONL record created above, so the descriptor cannot be passed to the CLI
directly. Install into an isolated contributor home with the root CLI:

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

Once `morphir-openapi` is installed, generate the default OpenAPI document
with:

```console
morphir generate --target openapi --input morphir-ir.json --output generated/openapi
```

The generator writes a single artifact, `openapi.json`, into the output
directory. Backend options live under `[codegen.openapi]` in `morphir.toml`:

```toml
[codegen]
targets = ["openapi"]

[codegen.openapi]
unsupported = "error"
version = "3.1"
projection = "schemas"
result_responses = "data"
error_status = 400

[codegen.openapi.operations."acme/customer:domain#find-customer"]
method = "get"
path = "/customers/{id}"

[codegen.openapi.operations."acme/customer:domain#find-customer".parameters]
id = "path"
```

Repeat `--option <KEY=VALUE>` to override that table for one command:

```console
morphir generate --target openapi \
  --option projection=operations-public \
  --option result_responses=split \
  --option error_status=422
```

The backend starts with its defaults, then applies `[codegen.openapi]`, then
applies CLI options in command-line order. The last CLI value for a key wins.
The CLI parses a value as JSON when possible; otherwise it passes a string.
Option names use `snake_case`.

`version` is the one option where that JSON-first rule bites. Its values are
the *strings* `"3.1"` and `"3.0"`, but `3.0` and `3.1` are also valid JSON
numbers, so the CLI hands the backend a number and option decoding fails with
`JSC002`. Quote the value so it reaches the backend as a string, and quote the
whole argument so the shell keeps the inner quotes:

```console
morphir generate --target openapi --option 'version="3.0"'
```

`--option version=3.0` fails. In `morphir.toml` no extra quoting is needed:
TOML's `version = "3.0"` is already a string.

## Options and defaults

| Option | Accepted values | Default |
|---|---|---|
| `unsupported` | `error`, `warn-and-skip` | `error` |
| `version` | `"3.1"`, `"3.0"` (strings; on the CLI write `--option 'version="3.0"'`) | `"3.1"` |
| `projection` | `schemas`, `operations-entry-points`, `operations-public` | `schemas` |
| `result_responses` | `data`, `split` | `data` |
| `error_status` | Integer from 400 through 599 | `400` |
| `operations` | Map from an exact Morphir FQName to a per-operation override | Empty map |

Unknown options, wrong JSON types, invalid enum values, an `error_status`
outside 400–599, and an `operations` override `path` that does not start with
`/` all fail option decoding with `JSC002` — this check runs before
generation, against the option value alone, so it does not need to know
whether the override's key names a real value specification. Each
`operations` override key must separately name a value specification the
package actually declares, or generation fails with `OAS002`.

## Choose what to project

The three projection modes answer different questions. `schemas` only ever
populates `components/schemas` — `paths` is still emitted, as an empty
object, since some validators require the key even when there is nothing in
it.

| Projection | `components/schemas` | `paths` |
|---|---|---|
| `schemas` | Public type roots | Empty |
| `operations-entry-points` | Public type roots, plus any type an operation reaches | Declared entry points from a v4 Application only |
| `operations-public` | Public type roots, plus any type an operation reaches | Every public value specification |

A Library or a Specs distribution has no declared application entry points,
so `operations-entry-points` produces an operation-free `paths` for them —
it never invents operations from ordinary public values.

## Default HTTP mapping and per-operation overrides

Every selected value specification starts from the same default mapping,
before any override is applied:

- HTTP method: `POST`.
- Path: `/<module segments, lowercased and slash-joined>/<value name,
  lowerCamelCase>`. For example, `acme/customer:domain#find-customer` becomes
  `/domain/findCustomer`.
- Request body: every input becomes a required `application/json` property.
  A zero-argument constant has no request body at all.
- Response: the output type becomes the `200` response, described as
  "Successful result".

Each operation also carries `operationId` (everything after the package's
`:` — every module segment and the local value name — run together and
`lowerCamelCase`d: `acme/customer:domain#find-customer` becomes
`domainFindCustomer`), `x-morphir-fqname` naming its exact Morphir source, and
`x-morphir-value-kind`, either `constant` or `function`. A declared entry
point additionally carries `x-morphir-entry-point: true`,
`x-morphir-entry-point-id`, and a lowercase `x-morphir-entry-point-kind` of
`main`, `command`, or `handler`.

`options.operations`, keyed by the operation's canonical Morphir FQName,
overrides this default. A worked example, moving `findCustomer`'s `id` input
onto a path parameter:

```toml
[codegen.openapi.operations."acme/customer:domain#find-customer"]
method = "get"
path = "/customers/{id}"

[codegen.openapi.operations."acme/customer:domain#find-customer".parameters]
id = "path"
```

`method` replaces the default `POST`. `path` replaces the default path
template. Each entry under `parameters` moves one named request field out of
the request body: `path` binds it to a `{name}` path placeholder (which must
already appear in the resulting path, or the generation fails with `OAS002`),
`query` binds it to a query parameter, `header` binds it to a request header,
and `body` leaves it in the request body — useful for restating a field
explicitly without moving it. Every moved parameter is still required: moving
where a value is carried never makes it optional. A `query` or `header`
binding whose name matches no request field is silently ignored, since
neither location renders a path placeholder and leaving the field in the
request body is a safe default.

A path claimed by two operations, or an `operationId` claimed by two
operations, fails with `OAS001` naming both Morphir FQNames — this is always
an error, regardless of `unsupported`, because it is a genuine ambiguity in
the projected package rather than a form the backend cannot represent.

## `result_responses` and `error_status`

Morphir's `Result error value` is a common output type. `result_responses`
decides how it becomes HTTP responses:

- `data` (the default) keeps the whole `Result` as one `200` response body: a
  discriminated choice between an `Err` object (holding the error under an
  `error` field) and an `Ok` object (holding the success value under a
  `value` field), both tagged by a `kind` property.
- `split` projects the `Ok` member's own type directly as the `200` response
  and the `Err` member's own type as a separate error response, at the status
  code `error_status` names.

`Result` is detected by its exact Morphir source name
(`morphir/SDK:result#result`), never by shape, so a package-local type that
happens to look like an error/value choice is never mistaken for it and never
split. An output type that is not `Result`-shaped ignores `result_responses`
entirely and always becomes one `200` response.

`error_status` is any integer from 400 through 599 and defaults to `400`. It
only has an effect when `result_responses = "split"` and at least one
projected operation's output is `Result`-shaped.

## The `version` option and the OpenAPI 3.0 downgrade

`version` takes the strings `"3.1"` and `"3.0"`, never the bare numbers. On
the CLI that means `--option 'version="3.0"'`; `--option version=3.0` parses
as a JSON number and fails with `JSC002`.

`version = "3.1"` (the default) renders `"openapi": "3.1.0"` — the document
built from the projection, unchanged. `version = "3.0"` renders `"openapi":
"3.0.3"`: the same document is always built as 3.1 first, then rewritten,
so there is one projection and one document builder and the two versions
cannot drift apart. The rewrite replaces every 2020-12-only form the 3.0
dialect (JSON Schema Draft 4-based) does not accept:

- `{"const": v}` becomes `{"enum": [v]}` — a discriminated variant's `kind`
  property keeps its exact value, just spelled as a single-value enum
  instead of `const`, which 3.0 does not have.
- A field or output typed `Maybe a` — `{"anyOf": [<a>, {"type": "null"}]}` in
  3.1 — becomes `<a>` merged with `"nullable": true`.
- A bare `Unit` (`{"type": "null"}`, not part of any `Maybe`) becomes
  `{"nullable": true, "enum": [null]}`, since OAS 3.0.3 §4.4 has no `null`
  type at all and there is no other type for `nullable` to sit beside.
- A tuple (`{"prefixItems": [...], "items": false}`) becomes an array whose
  `items` is `{"anyOf": [...]}` over the tuple's member schemas, with
  `minItems`/`maxItems` still pinning the length exactly. This uses `anyOf`,
  not `oneOf`: two tuple members can share a schema (for example `(Int,
  Int)`), and `oneOf` would then reject every element, since it requires
  exactly one branch to match.
- A `$ref` that sits next to another keyword — original or produced by one
  of the rewrites above — becomes `{"allOf": [{"$ref": ...}], ...siblings}`,
  because 3.0 tooling ignores every sibling of a `$ref`.
- `x-morphir-*` extension keys are valid in 3.0 and are never touched.

These rewrites only ever fire on the keywords of a Schema Object — never on
the keys of a `properties` map or a `components/schemas` map, both of which
hold arbitrary Morphir-derived names. A record field genuinely named `const`
survives untouched.

## Diagnostic codes

| Code | Meaning |
|---|---|
| `JSC001` | The host asked for a target this extension does not advertise |
| `JSC002` | A backend option was unknown, of the wrong type, or out of range |
| `JSC003` | A Morphir type, value signature, or operation has no safe projection |
| `JSC004` | Two projected declarations claimed the same schema name |
| `OAS001` | Two synthesized operations claimed the same path and method, or the same `operationId` |
| `OAS002` | An `operations` override names no declared value specification, or one of its `Path`-bound parameters has no matching `{name}` placeholder in the operation's path |

Under the default `unsupported = "error"`, any `JSC003` fails the whole
generation and writes no artifact. Under `unsupported = "warn-and-skip"`, an
operation whose own signature cannot be projected is dropped from `paths`
with a `JSC003` warning naming its Morphir FQName, and the rest of the
document still renders; the same rule follows one hop further out, so an
operation that only references a type dropped elsewhere in the document is
also dropped rather than left pointing at a missing schema. `OAS001` and
`OAS002` are always errors, regardless of `unsupported`: both name a mistake
in the Morphir source or the configuration itself, not a form the backend
cannot represent.

For runtime boundaries and release status, see the accepted [WASM extension
runtime and Avro backend proposal](../design/proposals/wasm-extension-runtime-and-avro-backend.md)
and the [OpenAPI and JSON Schema backend proposal](../design/proposals/openapi-and-json-schema-backend.md).
