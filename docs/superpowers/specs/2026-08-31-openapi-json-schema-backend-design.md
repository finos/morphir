# OpenAPI and JSON Schema backend design

Status: draft design, approved in brainstorming on 2026-08-31.

## Summary

Add one WASM backend extension, `morphir-openapi`, that exposes two generation
targets: `openapi` and `json-schema`. The extension projects public Morphir
types into JSON Schema 2020-12, and projects public types plus declared entry
points into an OpenAPI document. It follows the shape the Avro backend
established: a portable guest, host-owned file writing, options through
`morphir.toml` and `--option`, golden tests, and a registry-driven release.

The work also closes a protocol gap. The Morphir Extension Protocol (MEP)
generation request carries no target, so an extension that advertises more than
one target cannot tell which one the host selected. This design adds a required
`target` field to the generation request.

## Goals

- One extension that serves `openapi` and `json-schema` as separate, host-
  selectable targets.
- One shared schema projection, so the two targets cannot drift.
- OpenAPI 3.1 by default, with OpenAPI 3.0 available through an option.
- A released `0.1.0` WASM artifact, published the same way the Avro extension
  was published.

## Non-goals

- A public extension index. Installation stays local, as
  `docs/generate/avro.md` documents today.
- Reading OpenAPI or JSON Schema into Morphir. This is a backend only.
- Evaluating Morphir values. The backend projects specifications, not
  computation.
- AsyncAPI, GraphQL SDL, or other schema targets.

## Protocol change: target selection

### Current state

`GenerateRequest` is `{ ir, options }`. It is defined in
`ecosystem/morphir-rust/crates/morphir-extension-sdk/src/types.rs:318`.
`docs/design/draft/extensions/protocol.md:352` states that target selection is
a host concern that does not appear in the guest request. `BackendCapability`
already carries a list of targets, so an extension can advertise two targets,
but the guest receives no way to distinguish them.

The umbrella CLI depends on the SDK by path through the submodule
(`crates/morphir/Cargo.toml:41`), so the type change lands in morphir-rust and
reaches this repository through a submodule pin bump.

### Change

`GenerateRequest` becomes `{ ir, target, options }`. `target` is a required
`String`. There is no serde default: a missing key is a decode error, because
the host always knows which target it selected.

MEP stays at `0.1`. The host side has not been released, so this breaking change
does not need a version bump.

Rules:

- The host sends the exact negotiated target ID it used for provider selection,
  not a raw user string.
- A single-target guest ignores the field.
- A multi-target guest treats an unadvertised target value as a hard error
  diagnostic. It never falls back to a default target, because writing OpenAPI
  artifacts when the host asked for JSON Schema would be a silent wrong answer.
- The published `morphir-avro` 0.1.0 artifact keeps working with a new host,
  because its request struct has no `target` field and serde ignores unknown
  keys.

### Affected code and documents

- `ecosystem/morphir-rust/crates/morphir-extension-sdk/src/types.rs` — add the
  field.
- `ecosystem/morphir-rust/crates/morphir-avro-extension` — construct and ignore
  the new field; no behavior change.
- `crates/morphir/src/commands/generate.rs:116` — set `target` when building the
  request.
- `crates/morphir/src/commands/generate/provider.rs` — update the
  `GenerateRequest::default()` call sites in tests. Capability comparison
  already rejects a provider that does not advertise the selected target, and
  does not change.
- `docs/design/draft/extensions/protocol.md` — rewrite the paragraph at line
  352. The host still selects the target; it now also states the selection in
  the request. Input paths, output paths, and IR-version detection stay
  host-only. Add `"target"` to the example request under "Backend generation".

## Extension design

### Identity

- Extension ID: `morphir-openapi`
- Crate: `morphir-openapi-extension` in morphir-rust
- Capability: `BackendCapability { targets: ["openapi", "json-schema"],
  ir_versions: ["3", "4"], generate: true }`

One `Extension` implementation and one `Backend::generate` that dispatches on
`request.target`.

### Pipeline

```
IR JSON
  -> morphir-projection::normalize   (IR v3/v4 -> body-free package model)
  -> schema projector                (dialect-neutral schema model)
  -> renderer: json_schema | openapi_31 | openapi_30
```

`morphir-projection` is a new crate in morphir-rust holding the `normalize` and
`model` modules lifted out of `morphir-avro-extension` (about 1.8k lines).
`morphir-avro-extension` switches to depend on it. The extraction preserves
behavior, and the existing Avro golden files must stay byte-identical to prove
it.

The dialect-neutral schema model is the point of the design. Type mapping is
written once. The `json-schema` output and the `components/schemas` block of an
OpenAPI 3.1 document come from the same projection, so they cannot disagree.

### Target: `json-schema`

Dialect JSON Schema 2020-12. One `.schema.json` file per public root type. The
type closure goes under `$defs` with local `$ref` pointers. File names come
deterministically from the Morphir FQName. A name collision is an error, not an
implicit rename, matching the Avro rule.

### Target: `openapi`

OpenAPI 3.1 by default. The `version = "3.0"` option selects a downgrade
renderer.

Public types become `components/schemas`. In the 3.1 case, a schema object is
identical in content to what the `json-schema` target produces for the same
type, differing only in the `$ref` base.

Projection modes mirror Avro's:

| Mode | Types | Paths |
|---|---|---|
| `schemas` | Public type definitions | None |
| `operations-entry-points` | Public type definitions | Declared v4 Application entry points |
| `operations-public` | Public type definitions | Every public value specification |

### HTTP mapping

Default, with no configuration: `POST /{module}/{entryPoint}`. The request body
is an object of named arguments. The `200` response is the result type.

`[codegen.openapi.operations."pkg:mod#name"]` overrides the method, the path,
and parameter binding for one entry point. Keys use the canonical
`package:module#local` Morphir FQName, the same key form the Avro backend uses
for type mappings.

`Result error value` is ordinary data by default: a schema returned in the `200`
response, consistent with the Avro backend's rule that a Morphir result is
return data rather than a transport failure. The `result_responses = "split"`
option puts the `Ok` branch in the `200` response and the `Err` branch in a
configurable error status.

### Type mapping

Shared by both targets:

| Morphir form | JSON Schema / OpenAPI 3.1 | OpenAPI 3.0 difference |
|---|---|---|
| `Bool` | `boolean` | — |
| `Int` | `integer`, format `int64` | — |
| `Float` | `number`, format `double` | — |
| `String` | `string` | — |
| `Char` | `string` with `maxLength: 1` | — |
| `Unit` | `{"type": "null"}` | `nullable` empty schema |
| `Maybe a` | type union with `null` | `nullable: true` |
| `List a` | `array` | — |
| `Set a` | `array` with `uniqueItems: true` | — |
| `Dict String a` | `object` with `additionalProperties` | — |
| Record alias | `object` with `required` | — |
| Nullary custom type | `enum` | — |
| Custom type with payloads | `oneOf` with a discriminator property | — |
| Tuple | fixed-length `prefixItems` array | positional `items` list |

Morphir identity is preserved in `x-morphir-*` extension keys, which play the
same role as the Avro backend's `morphir.*` properties.

### Options and diagnostics

Options live under `[codegen.openapi]` and `[codegen.json-schema]` in
`morphir.toml`, and can be overridden with repeated `--option KEY=VALUE`.
Precedence matches Avro exactly: backend defaults, then the config table, then
CLI options in command-line order, last value wins. Option names use
`snake_case`.

`unsupported = "error" | "warn-and-skip"` matches the Avro semantics. The
default `error` emits no artifacts when any projection fails.

Diagnostic codes are per target, so a diagnostic names the target that produced
it: `OAS001` and onward for `openapi`, `JSC001` and onward for `json-schema`.

## Testing

The crate follows the Avro test layout
(`tests/{golden,projection,options,guest}.rs` plus `tests/support/mothers`).

- Projection tests cover the shared schema model, one case per Morphir form.
  This is a single suite serving both targets.
- Golden tests hold checked-in `.schema.json`, `openapi-3.1.json`, and
  `openapi-3.0.json` files per fixture.
- A cross-target assertion checks that, for a given type, the `json-schema`
  document's `$defs` entry and the OpenAPI 3.1 `components/schemas` entry are
  the same object apart from the `$ref` base. This assertion is what keeps the
  shared core honest.
- Dev-dependencies include a JSON Schema 2020-12 validator and an OpenAPI
  validator, so goldens are checked against real parsers rather than only
  against each other. The Avro crate sets this precedent with its
  `apache-avro` dev-dependency.
- Option tests cover precedence, unknown keys, wrong JSON types, invalid enum
  values, and the per-operation override table.
- Guest tests cover capability metadata with both targets advertised, dispatch
  on `request.target`, and the hard error for a missing or unadvertised target.
- Normalization tests move to `morphir-projection` with the code.
- In this repository, an end-to-end test alongside
  `crates/morphir/tests/generate_extension.rs` installs the one built guest and
  runs both `--target openapi` and `--target json-schema` against it. This is
  the first proof that one extension serves two targets end to end.

## Release

Version `0.1.0`, published through the existing registry-driven workflow. The
Avro extension proved this path: tag `extension/avro/v0.1.0` exists on the
morphir-rust remote at the pinned commit.

New registry entry in `ecosystem/morphir-rust/.github/extensions.toml`:

```toml
[extensions.openapi]
package = "morphir-openapi-extension"
artifact = "morphir-openapi-extension"
extension_id = "morphir-openapi"
mep_versions = ["0.1"]
targets = ["openapi", "json-schema"]
ir_versions = ["3", "4"]
release_with_workspace = true
```

`scripts/extension_packaging/model.py:106` reads `targets` through
`require_string_list`, so a two-target row already flows into the release
descriptor. The packaging tests under `tests/ci/` still need a two-target case,
because Avro never exercised one.

The packaging helpers hardcode Avro in staging paths:
`scripts/extension_packaging/paths.py` defines `validate_avro_staging` and
`clean_avro_staging` around a literal `avro` directory, and matches a
`morphir-avro-head\.[A-Za-z0-9]+` snapshot name. These become short-ID
parameterized rather than copied.

Tag `extension/openapi/v0.1.0` publishes the WASM asset, `release.json`, and
the SHA-256 digest through the existing `release.yml` matrix. No new workflow is
needed.

Because the SDK change alters the Avro crate, `morphir-avro` gets a `0.1.1`
re-release from its existing registry entry once the SDK change lands, so the
published pair stays coherent.

Installation stays local. There is no public index, and the user documentation
must say so plainly rather than implying an available release.

## Documentation

- New proposal at `docs/design/proposals/openapi-and-json-schema-backend.md`,
  following the section shape of the accepted Avro proposal.
- New user guides `docs/generate/openapi.md` and `docs/generate/json-schema.md`,
  each following `docs/generate/avro.md`: local build and install, running the
  generator, the options table, the type mapping table, and the diagnostic
  codes.
- Protocol document edits described above.

## Delivery order

Each step is a separate pull request.

1. morphir-rust: add the required `target` field to `GenerateRequest`; update
   the Avro crate to the new struct shape. Breaking, stays at MEP `0.1`.
2. This repository: submodule pin bump, host sends `target`, protocol document
   rewrite.
3. morphir-rust: extract `morphir-projection`; Avro goldens unchanged.
4. morphir-rust: `morphir-openapi-extension` with normalization wiring, the
   schema projector, the `json-schema` renderer, and its goldens.
5. morphir-rust: OpenAPI 3.1 renderer, paths and operations, options.
6. morphir-rust: OpenAPI 3.0 downgrade renderer.
7. This repository: end-to-end two-target test, user guides, proposal document.
8. Release: registry entry, packaging generalization, tag
   `extension/openapi/v0.1.0`, and the Avro `0.1.1` re-release.

## Open questions

None blocking. Two items to confirm during implementation:

- The exact discriminator form for custom types with payload constructors, once
  the OpenAPI 3.0 downgrade constraints are tested against a real validator.
- Whether `operations-public` should be a released mode or deferred, decided
  after the entry-point mode has golden coverage.
