# Native IR authoring gate inventory

`morphir mck schema check` uses the selected kit for every entry below. It validates
the complete original schemas before checking instances. It does not link an IR
implementation, launch a validator process, or fetch referenced schemas.

| Schema | Dialect | Instance or entry point | Expected result |
| --- | --- | --- | --- |
| `spec/ir/mck/report.schema.json` | Draft 7 | Metaschema; `report.example.json` at root | Accept; retained legacy migration evidence |
| `spec/ir/mck/report-draft.schema.json` | Draft 7 | Metaschema; `report-draft.example.json` at root | Accept |
| `spec/ir/mck/protocol.schema.json` | Draft 7 | Metaschema; every `protocol.example.json` message at root and operation-specific definition | Accept, with request/response pairing |
| `spec/mck/vocabulary.schema.json` | Draft 2020-12 | Metaschema; `vocabulary.json` at root | Accept |
| `spec/mck/mck-kit.lock.schema.json` | Draft 2020-12 | Metaschema; `mck-kit.lock.example.json` at root | Accept |
| `spec/mck/provenance.schema.json` | Draft 2020-12 | Metaschema | Accept; retained legacy provenance contract |
| `website/static/schemas/morphir-ir-v4.json` | Draft 7 | Metaschema; active v4 canonical/accepted inline JSON fences at their node definition, Distribution at root | Accept, except legacy warning spellings below |
| `website/static/schemas/morphir-ir-v4-document-tree-files.json` | Draft 7 | Metaschema; the four document-tree file node definitions | Accept |

The protocol entry points are `Request`, `Capabilities`, `DecodeResponse` (for
`decode` and `readTree`) and `WriteTreeResponse`. `exit` has no response. Multiple
alternative responses may answer the same pending request in the example. An
unanswered request, mismatched ID, unknown direction, or root `oneOf` failure fails
the gate.

Pairing compares integer IDs without floating-point conversion. Integral decimal or
exponent spellings such as `1.0` retain the live transport's conversion bound (less
than `9e15`); larger decimal-spelled IDs are rejected rather than paired after rounding.

Fence targets match the frozen TypeScript `NODE_TARGETS`: Distribution, FormatVersion,
Name, Path, FQName, Type, Value, Pattern, Literal, TypeSpecification, TypeDefinition,
ValueSpecification, ValueDefinition, ModuleSpecification, ModuleDefinition,
AccessControlledTypeDefinition, AccessControlledValueDefinition,
DistributionManifestFile, ModuleManifestFile, TypeDefinitionFile and ValueDefinitionFile.
An unknown target is a coverage-loss failure. Pending cases, other IR versions,
rejected fences, YAML and referenced text fixtures retain their previous exclusion
from this JSON schema gate; they remain inputs to the runner.

An accepted fence carrying `warning=` must be rejected by the schema, except
`definitions-0006`, `definitions-0010` and `definitions-0018`: the documentation
wrapper remains schema-valid for its documented compatibility window. The fixed
corpus yields 181 accepted and 13 expected rejections, with no failed or skipped fences.

The pinned in-process library is `jsonschema` 0.26.2 (declared MSRV Rust 1.70), with
default HTTP/file resolution features disabled and an explicit rejecting retriever.
Its installed source documents Draft 7/2020-12 support and `with_resource`; compilation
validates metaschemas by default. Tests qualify both dialects with the actual catalog,
invalid schemas, missing inputs, external references and fixed positive/negative instances.
The closed catalog registers only selected-kit resources. New external references
require an explicit catalog and snapshot-closure update.

Two repository checks stay separate in `mise run mck:source-parity`: vocabulary
regeneration against the pinned TypeScript source, and byte comparison of the protocol
schema/example copies. These guard migration drift until IR-4; the installed CLI has
no TypeScript checkout dependency. Live runner parity and package gates also remain.
