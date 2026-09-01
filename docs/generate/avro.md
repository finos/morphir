---
title: Generate Apache Avro
sidebar_label: Apache Avro
sidebar_position: 1
---

# Generate Apache Avro

> The Avro backend is accepted but not released. This guide describes the
> current contract for testing a locally built and installed extension. Do not
> treat it as an announcement of an available release.

The `morphir-avro` WASM extension turns public Morphir types and value
specifications into Apache Avro schemas or protocols. It accepts Morphir IR v3
and v4. It does not evaluate Morphir values or translate computation.

## Build and install the local extension

There is no published Avro extension to install yet. Contributors can build the
WASM guest, create a schema-v2 local repository, and install from that
repository. From the `ecosystem/morphir-rust` directory, run:

```console
mise run extension:artifact:avro

bundle=.morphir/build/extensions/avro
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
    "name": "Morphir Avro",
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

history = index / "extensions" / "morphir-avro.jsonl"
history.write_text(json.dumps(record, separators=(",", ":")) + "\n", encoding="utf-8")
PY
```

`release.json` describes the release bundle. The install command needs the
schema-v2 JSONL record created above, so the descriptor cannot be passed to the
CLI directly. Register the directory as a named repository in an isolated
contributor home, then install with the root CLI:

```console
MORPHIR_HOME="$PWD/.morphir/local-home" \
  mise exec -- cargo run --manifest-path ../../Cargo.toml -p morphir -- \
  extension repository add local-avro --directory "$PWD/.morphir/build/index"

MORPHIR_HOME="$PWD/.morphir/local-home" \
  mise exec -- cargo run --manifest-path ../../Cargo.toml -p morphir -- \
  extension install --repository local-avro morphir-avro

MORPHIR_HOME="$PWD/.morphir/local-home" \
  mise exec -- cargo run --manifest-path ../../Cargo.toml -p morphir -- \
  extension list
```

Keep the same `MORPHIR_HOME` value when running generation. Installation
verifies the SHA-256 from the repository, stores the module by content digest,
and writes matching lock and catalog state. These commands do not publish the
extension.

## Run the generator

Once an Avro provider is installed, generate the default JSON schemas with:

```console
morphir generate --target avro --input morphir-ir.json --output generated/avro
```

Backend options live under `[codegen.avro]` in `morphir.toml`:

```toml
[codegen]
targets = ["avro"]

[codegen.avro]
representation = "json"
projection = "schemas"
dependencies = "self-contained"
aliases = "inline"
unsupported = "error"
logical_types = true
decimal_precision = 38
decimal_scale = 10

[codegen.avro.type_mappings."acme/customer:customer#customer-id"]
type = "string"
logical_type = "uuid"
```

Repeat `--option <KEY=VALUE>` to override that table for one command:

```console
morphir generate --target avro \
  --option representation=idl \
  --option projection=protocol-public \
  --option dependencies=linked
```

The backend starts with its defaults, then applies `[codegen.avro]`, then
applies CLI options in command-line order. The last CLI value for a key wins.
The CLI parses a value as JSON when possible. Otherwise it passes a string.
For example, `logical_types=false` is a Boolean and `representation=idl` is a
string. Option names use `snake_case`.

## Options and defaults

| Option | Accepted values | Default |
|---|---|---|
| `representation` | `json`, `idl` | `json` |
| `projection` | `schemas`, `protocol-entry-points`, `protocol-public` | `schemas` |
| `dependencies` | `self-contained`, `linked` | `self-contained` |
| `aliases` | `inline`, `wrapper-record` | `inline` |
| `unsupported` | `error`, `warn-and-skip` | `error` |
| `logical_types` | Boolean | `true` |
| `decimal_precision` | Positive integer | `38` |
| `decimal_scale` | Integer from zero through the effective precision | `10` |
| `type_mappings` | Map from an exact Morphir FQName to a mapping object | Empty map |

Unknown options, wrong JSON types, invalid enum values, and invalid decimal
ranges fail with `AVRO004`. A per-type decimal mapping must use physical type
`bytes`. Its scale must not exceed its effective precision. The allowed
physical mapping values are `null`, `boolean`, `int`, `long`, `float`,
`double`, `bytes`, and `string`.

## Choose what to project

The three projection modes answer different questions:

| Projection | Types | Messages |
|---|---|---|
| `schemas` | Public type definitions | None |
| `protocol-entry-points` | Public type definitions | Declared entry points from a v4 Application only |
| `protocol-public` | Public type definitions | Every public value specification |

A function message uses its arguments as request fields and its result type as
the response. Libraries and Specs have no declared application entry points, so
`protocol-entry-points` emits a type-only protocol for them. It does not invent
messages.

## Output files

The representation and projection together determine the suffix:

| Representation | `schemas` | Either protocol mode |
|---|---|---|
| `json` | One `.avsc` per public root type | One `.avpr` per Morphir module |
| `idl` | One message-free `.avdl` wrapper per public root type | One `.avdl` protocol per Morphir module |

Every IDL artifact contains exactly one `protocol` declaration. A schema-mode
wrapper ends in `Schemas` and can be converted with `avro-tools
idl2schemata`.

Some protocol IDL messages return named types and carry Morphir annotations.
Avro Tools 1.12.2 requires `avro-tools idl --useJavaCC` for those files. The
generator places a compatibility comment at the start of each affected `.avdl`.
Primitive-response and message-free schema wrappers continue to work with the
default reader.

## Morphir IR v3 and v4

The backend accepts baseline version spellings `3`, `"3.0.0"`, `4`, and
`"4.0.0"`. It rejects other major versions and revisions such as `3.1.0` or
`4.1.0`. Both supported versions normalize into the same body-free model.

| Input distribution | Public types | `protocol-entry-points` | `protocol-public` |
|---|---|---|---|
| v3 Library | Included | Type-only protocol | Public value signatures become messages |
| v4 Library | Included | Type-only protocol | Public value signatures become messages |
| v4 Specs | Specified types included | Type-only protocol | Specified values become messages |
| v4 Application | Included | Declared entry points become messages | All public value signatures become messages |

Normalization keeps package and module names, public declarations,
documentation, source FQNames, dependencies, and v4 entry-point metadata. It
drops value bodies.

## Type mapping

The default projection is:

| Morphir form | Avro representation |
|---|---|
| `Bool` | `boolean` |
| `Int` | `long` |
| `Float` | `double` |
| `String` | `string` |
| `Char` | `string` with `morphir.type = Char` |
| `Unit` | `null` |
| `Maybe a` | Union of `null` and the projection of `a` |
| `List a` | Array |
| `Set a` | Array with `morphir.collection-kind = set` |
| `Dict String a` | Map |
| Record alias | Named record |
| Nullary custom type | Enum |
| Custom type with payload constructors | Wrapper record and constructor records |
| Tuple or closed generic specialization | Stable generated record or name |
| `Result error value` | Named outer `Result` record whose `value` field is a union of named `Err` and `Ok` records |

The `Err` record contains the projected error and the `Ok` record contains the
projected success value. `Result` does not become an Avro protocol error. A
Morphir result is ordinary return data, not a transport failure.

When `logical_types = true`, recognized Morphir types use these Avro pairs:

| Morphir concept | Avro physical type | Avro logical type |
|---|---|---|
| Local date | `int` | `date` |
| Local time | `long` | `time-micros` |
| Instant or DateTime | `long` | `timestamp-micros` |
| UUID | `string` | `uuid` |
| Decimal | `bytes` | `decimal` |

Use `type_mappings` for an exact source FQName that needs another physical or
logical type:

```toml
[codegen.avro.type_mappings."acme/customer:customer#money"]
type = "bytes"
logical_type = "decimal"
precision = 20
scale = 4
```

Mapping keys use the canonical `package:module#local` Morphir FQName. They do
not match an anonymous or inline type expression. To handle one non-string
`Dict` without mapping every SDK dictionary, give that dictionary shape a named
declaration, reference the declaration where it is used, and map the exact
FQName of that declaration.

The generator uses UpperCamelCase for Avro types and constructors,
lowerCamelCase for fields and messages, and normalized dotted namespaces. It
keeps the original Morphir FQName as metadata. Stable synthetic names depend on
the projected type, not traversal order. A name collision is an error rather
than an implicit rename.

## Constants and entry points

`protocol-public` projects a zero-argument public value as a zero-argument
message. The message has `morphir.value-kind = constant`. It contains no
constant value because normalization never reads or evaluates the value body.
Functions use `morphir.value-kind = function`.

Declared application entry points also have `morphir.entry-point = true`, their
entry-point ID, and a lowercase `morphir.entry-point-kind` of `main`, `command`,
or `handler`.

## Dependencies and aliases

`dependencies = "self-contained"` embeds each referenced dependency schema in
the generated artifact closure. Use this when each artifact must compile on its
own.

`dependencies = "linked"` emits dependency declarations separately and refers
to them by full Avro name. IDL uses deterministic relative imports. A missing
linked dependency fails with `AVRO006`. Linked output is useful when a build
already packages shared schemas and wants to avoid duplicate definitions.

`aliases = "inline"` replaces an alias with its target unless that target is a
named record. `aliases = "wrapper-record"` preserves the alias as a generated
record with one `value` field. Wrapper records give the alias its own Avro name
at the cost of an extra record layer.

## Unsupported forms and partial output

The backend cannot safely project a function used as data, an open extensible
record, an opaque or incomplete type, an unresolved type, unsafe recursion, an
unbound generic parameter, or a `Dict` with a non-string key unless an explicit
mapping handles it.

The default `unsupported = "error"` is strict. Any projection error makes the
result unsuccessful and emits no artifacts. `warn-and-skip` omits the bad public
form, emits a deterministic warning at its Morphir FQName, and returns only
artifacts that remain independently valid.

| Code | Meaning |
|---|---|
| `AVRO001` | Unsupported Morphir type or form |
| `AVRO002` | Unbound type parameter |
| `AVRO003` | Avro name collision |
| `AVRO004` | Invalid backend option |
| `AVRO005` | Unsafe or unrepresentable recursion |
| `AVRO006` | Missing linked dependency |

For runtime boundaries and release status, see the accepted [WASM extension
runtime and Avro backend proposal](../design/proposals/wasm-extension-runtime-and-avro-backend.md).
