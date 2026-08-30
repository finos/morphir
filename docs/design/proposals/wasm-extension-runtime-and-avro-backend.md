---
title: WASM extension runtime and Avro backend
sidebar_label: WASM runtime and Avro
sidebar_position: 2
---

# WASM extension runtime and Avro backend

**Status:** Accepted; not released.

This proposal defines a portable Morphir extension runtime and its first backend,
Avro. It spans the root Morphir CLI and `ecosystem/morphir-rust`. It is not yet a
released user feature. APIs may receive implementation-driven refinements before
release, but the boundaries and behavior described here are the accepted design.

The public runtime names are `process` and `wasm`. Extism runs WASM extensions,
but it is an engine detail, not a configuration or manifest runtime target.

This accepted proposal specializes the [extension protocol draft](../draft/extensions/protocol.md)
and [distribution and acquisition draft](../draft/extensions/distribution-and-acquisition.md)
for portable WASM and Avro. If either draft conflicts with this proposal, this
proposal controls.

## What this design establishes

Both runtime kinds use the same Morphir Extension Protocol, or MEP, JSON-RPC
lifecycle:

```text
install and select extension
        |
initialize -> exact identity and capability negotiation -> generate
                                                        |
                         diagnostics and validated artifacts <-+
                                                        |
                                                    shutdown
```

Capability negotiation is typed. A backend can, for example, report:

```json
{"backend":{"targets":["avro"],"irVersions":["3","4"],"generate":true}}
```

The generic generation request is `GenerateRequest { ir, options }`. Reading
input files and writing output files belong to the host, not the guest.

## Portable extensions and safety boundary

A schema-v2 WASM record retains the artifact source, digest, and filename. It
omits a platform, requires empty arguments, and rejects `executable = true`.
Materialization verifies the declared SHA-256 and atomically publishes the bytes
to the content-addressed store. Transactional installation writes the lock and
catalog, including the materialized store path.

Offline activation atomically loads the catalog and lock snapshot before
validating their agreement and runtime invariants. It canonicalizes the artifact
under the Morphir home, rehashes it, verifies its mode, and returns a verified
artifact. Only then does transport initialization compare the extension's
identity and backend metadata with the locked metadata.

A WASM guest has no direct filesystem or network access. It returns a complete
set of relative artifacts, which the host validates, stages, and publishes with
rollback for failures detected in the running process. Files and relevant
directories are synced where practical, but the writer has no durable journal
and is not crash-atomic. The host rejects absolute paths, traversal, duplicates
including case-only collisions, malformed binary content, and file/directory
contradictions. Process extensions intentionally retain the ambient filesystem
and network rights of the user who launches the CLI.

The current WASM host also limits a guest to 256 MiB of linear memory, a
30-second call deadline, and a 100-million-instruction fuel budget. MEP requests
and responses are limited to 64 MiB. Guest discovery and invocation run on
blocking workers so a slow or defective guest cannot occupy a Tokio runtime
worker; response size is checked before accepted bytes are copied into a
host-owned buffer.

This makes process and WASM execution share the same protocol while preserving a
stricter boundary for portable guests.

## Avro extension boundary

`morphir-avro-extension` is the first guest crate in `morphir-rust`. Its
projection and rendering core is pure native Rust. A thin `wasm32` guest adapts
that core to MEP.

The extension accepts Morphir IR v3 and v4, normalizes both into a common
definitions/specifications model, and drops value bodies. Its pipeline is:

```text
v3 or v4 IR -> normalized projection -> Avro semantic model
          -> JSON or IDL renderer -> MEP artifacts and diagnostics
```

It projects types and value specifications. It does not evaluate constants or
translate computation.

## Projection modes

Use this v4 Application as a reference point. It declares `findCustomer` as a
`command` entry point:

```text
type Customer = { id : String, name : String }
findCustomer : String -> Maybe Customer
defaultCustomer : Customer
```

| Mode | Message projection |
| --- | --- |
| `schemas` | None. |
| `protocol-entry-points` | `findCustomer` only. |
| `protocol-public` | `findCustomer` and zero-argument constant `defaultCustomer`. |

`schemas` produces JSON `.avsc` files. Its IDL `.avdl` output has a message-free
wrapper protocol for each root. The two protocol modes produce JSON `.avpr` or
IDL `.avdl`, with one protocol per Morphir module. Every `.avdl` contains exactly
one protocol. Libraries and specifications in `protocol-entry-points` produce a
type-only protocol rather than invented messages.

Generated protocol IDL uses annotations on messages whose responses can be
named types. Avro Tools 1.12.2's default ANTLR reader rejects that valid output
with `Type references may not be annotated`; consumers must compile affected
protocol artifacts with `avro-tools idl --useJavaCC`. Each affected `.avdl`
starts with a deterministic compatibility comment stating this requirement.
Message-free `*Schemas.avdl` wrappers remain supported by the default reader and
by `avro-tools idl2schemata`. Release validation exercises both reader paths:
the default-reader failure is accepted only for the documented affected shape,
while every protocol must compile through JavaCC and preserve its annotations.

A function specification becomes an Avro message: its input becomes request
fields and its result becomes the response. In this example, `findCustomer`
gets an `id` request field and a nullable `Customer` response.

Constants become zero-argument messages. They include
`morphir.value-kind = constant` and never embed or evaluate the constant's
value. Ordinary functions use `morphir.value-kind = function`. Declared entry
points include `morphir.entry-point = true` and
`morphir.entry-point-kind = command` in this example. The kind value is exactly
one of the lowercase strings `main`, `command`, or `handler`.

Morphir `Result` is represented as a named outer record. Its `value` field is a
union of named `Err` and `Ok` records that contain the projected error and
success values. It does not use Avro protocol errors, because a Morphir result
is part of the ordinary return value rather than a transport failure.

## Type projection

The projection uses UpperCamelCase for types and constructors, lowerCamelCase
for fields and messages, and normalized dotted namespaces. It keeps source FQN
metadata. Synthetic names derive from the full projected type, never traversal
order. A collision produces a diagnostic; the renderer never silently renames a
source declaration.

| Morphir form | Avro representation |
| --- | --- |
| `Bool`, `Int`, `Float`, `String` | `boolean`, `long`, `double`, `string` |
| `Char` | Annotated `string` |
| `Unit` | `null` |
| `Maybe a` | Nullable union |
| `List a` | Array |
| `Set a` | Annotated array |
| `Dict String a` | Map |
| Record alias | Record |
| Nullary custom type | Enum |

Payload custom-type constructors use wrapper records. Tuples and generic
specializations receive stable generated records or names. An unbound generic
parameter is unsupported.

When logical types are enabled, Local date uses `int`/`date`, Local time uses
`long`/`time-micros`, Instant and DateTime use
`long`/`timestamp-micros`, UUID uses `string`/`uuid`, and Decimal uses
`bytes`/`decimal`. Decimal defaults to precision 38 and scale 10, both
configurable.

The following forms cannot be projected safely: function-as-data, open
extensible records, opaque, unresolved, or incomplete types, unsafe recursion,
and non-string `Dict` keys unless an explicit mapping override is supplied.

## Configuration and diagnostics

Project configuration keeps Avro choices under `codegen.avro`:

```toml
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

The CLI can override these settings:

```sh
morphir generate --target avro \
  --option representation=idl \
  --option projection=protocol-public \
  --option dependencies=linked
```

Precedence is guest defaults, then `[codegen.avro]`, then repeatable CLI
`--option` values. The last CLI value wins. Each CLI value parses as JSON when
valid, otherwise as a string. The host transports options generically; the guest
validates snake_case keys, values, types, and ranges.

| Option | Values and default |
| --- | --- |
| `representation` | `json` by default; `idl` |
| `projection` | `schemas` by default; `protocol-entry-points`, `protocol-public` |
| `dependencies` | `self-contained` by default; `linked` |
| `aliases` | `inline` by default; `wrapper-record` |
| `unsupported` | `error` by default; `warn-and-skip` |
| `logical_types` | `true` by default |
| `decimal_precision`, `decimal_scale` | `38`, `10` by default |
| `type_mappings` | Explicit source-type mappings |

`warn-and-skip` emits independently valid artifacts and deterministic warnings.
Strict mode emits no artifacts if projection errors occur.

| Code | Meaning |
| --- | --- |
| `AVRO001` | Unsupported type |
| `AVRO002` | Unbound parameter |
| `AVRO003` | Name collision |
| `AVRO004` | Invalid option |
| `AVRO005` | Unsafe recursion |
| `AVRO006` | Missing linked dependency |

## Distribution and release ownership

`morphir-rust` builds the extension and owns its future publication. From the
root repository, the registry is checked in at
`ecosystem/morphir-rust/.github/extensions.toml`. It records the extension as
portable WASM:

```toml
[extensions.avro]
package = "morphir-avro-extension"
artifact = "morphir-avro-extension"
extension_id = "morphir-avro"
mep_versions = ["0.1"]
targets = ["avro"]
ir_versions = ["3", "4"]
release_with_workspace = true
```

The workspace release uses tag `v0.2.0`. An independently released Avro
extension uses `extension/avro/v0.1.0`.

`mise run extension:artifact:avro` writes local or workflow build artifacts for
the WASM file, checksum, and `release.json`. The workflow build job has read-only
repository permissions. The publication job alone has release-writing
permission. It downloads the exact prior artifact output, verifies it, and
never rebuilds it.

## Implementation workstreams

The work is intentionally split so runtime correctness and backend behavior can
move independently:

1. Portable runtime, typed capabilities, distribution, installation, activation,
   and conformance provide the verified execution boundary.
2. Avro normalization, projection, rendering, WASM guest, and golden tests build
   on that boundary.
3. CLI target discovery, option transport, artifact safety, and release
   automation connect the extension to users and publication.
4. Public documentation and examples explain the installed feature.

The runtime boundary precedes the guest, the guest precedes CLI integration, and
the user documentation and examples follow the installed feature. This proposal
intentionally does not track live delivery. Contributors should use current
repository issues and pull requests for progress.

## Testing and acceptance

Acceptance covers native Rust unit and golden test gates for the projection core;
v3/v4 normalization equivalence; six representation and projection-mode goldens;
official Avro tool validation pinned to 1.12.2, including default-reader schema
validation and JavaCC protocol validation; the full MEP lifecycle against an
installed real guest; CLI and artifact-security edge cases; and release routing,
checksum verification, and no-rebuild tests.

## Alternatives and non-goals

This design chooses Extism plus MEP over introducing a new WIT contract now.
A WIT adapter remains possible later. A dedicated CLI Avro backend was rejected
because it would not prove the portable extension model.

It does not translate or evaluate value bodies, allow direct WASM guest I/O, or
claim lossless Avro mappings for every Morphir construct. Process extensions are
not claimed to be OS-sandboxed.

## References

- [Apache Avro specification](https://avro.apache.org/docs/current/specification/)
- [Apache Avro IDL language](https://avro.apache.org/docs/current/idl-language/)
- [Apache Avro 1.12.2 release, pinned validation-tool context](https://avro.apache.org/blog/2026/08/12/avro-1.12.2/)
