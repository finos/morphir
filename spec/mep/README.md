# Morphir Extension Protocol (MEP)

## What MEP is

The Morphir Extension Protocol is the contract between a Morphir host and a Morphir extension. The host, for example the `morphir` CLI, starts the extension, negotiates a protocol version, and sends it requests. The extension is a frontend, backend, transform, validator or workspace provider, and it answers those requests. Today the messages travel as JSON-RPC 2.0. A WIT world generated from the same contract will follow.

This folder holds the contract as a Morphir model. [`contract/src/mep.gleam`](contract/src/mep.gleam) is the source of truth, and [`generated/mep.ir.json`](generated/mep.ir.json) is its compiled Morphir IR (IR package `morphir/mep`). JSON Schema, WIT and language types are to be derived from that IR, not from the Gleam source.

## Versioning

Before 1.0.0:

- A breaking change bumps the minor version, for example 0.2.x to 0.3.0.
- An additive or backward-compatible change bumps the patch version.
- Published contracts carry no prerelease tags.

The handshake sends the canonical `MAJOR.MINOR` form of the version. `SUPPORTED_MEP_VERSIONS` in `morphir-extension-sdk` lists canonical versions; today it holds `0.1`. After 1.0.0, MEP follows standard SemVer.

The capability claims format has its own version, separate from MEP. Writers send `claimsVersion` `0.1.0-draft.2`, and readers also accept `0.1.0-draft.1`.

## Layout

```text
spec/mep/
  README.md                 this file
  contract/                 Gleam project, the source of truth
    morphir.toml
    gleam.toml
    src/mep.gleam
  generated/                committed; CI checks it for drift
    mep.ir.json
    json-schema/            later: finos/morphir-rust#242
    wit/morphir-mep/        later: finos/morphir-rust#243
  mck/                      later: host and guest conformance suites, finos/morphir#965
```

## Wire mapping

The default rule: a Gleam label in snake_case is a JSON member in lowerCamelCase (`protocol_versions` is `protocolVersions`), every member is required, and every member is written. A constructor without arguments is not a default: each enum-like type states its wire values.

Each exception below is also written in the doc comment of its type. The test `every_wire_exception_is_documented` checks that the doc comments keep them.

| Type | Exception |
| --- | --- |
| `Json` | Any JSON value, written as that value, not as a tagged constructor. |
| `PeerKind` | Wire values `cli`, `unspecified`. An unknown value is read as `Unspecified`. |
| `PeerInfo` | `kind` can be absent; an absent kind is read as `Unspecified`. |
| `ExtensionType` | Wire values `frontend`, `backend`, `transform`, `validator`, `workspace`. |
| `ExtensionInfo` | Members stay snake_case (`min_sdk_version`). `description`, `author`, `homepage`, `license` and `min_sdk_version` are left out when absent. |
| `Method` | Written as the JSON-RPC `method` string, for example `morphir.initialize`. `morphir.initialized` and `morphir.exit` are notifications. |
| `ErrorCode` | Written as the integer code, for example `-32011`. |
| `RpcError` | `data` is left out when absent. |
| `FrontendCapability` | `multiDocument` is written only when true; absent means false. |
| `WorkspaceCapability` | `protocolVersions` are full SemVer strings (`0.1.0`), not MEP versions. |
| `ExtensionCapabilities` | `frontend`, `backend` and `workspace` are left out when absent. The four flags are always written; an absent flag is read as false. `extra` members sit beside the named members, and a writer refuses an `extra` key that reuses a named member's name. |
| `ClaimsRequirements` | Each `host` entry is one SemVer comparator. `host` is left out when empty and read as empty when absent. |
| `CapabilityClaimSet` | `claimsVersion` is the claims format version, and draft.1 names it `statementVersion`. A claim set with both names is refused. In draft.1, `statementVersion` in `critical` is read as `claimsVersion`, and `claimsVersion` in `critical` is refused. `protocolVersions` are MEP `MAJOR.MINOR` versions. Unknown top-level members are dropped when read. `capabilities` is open, and its named members are not checked against `ExtensionCapabilities` when read. `requires` is left out when absent, and `critical` is left out when empty. A reader refuses a `critical` path it does not understand. |
| `CompilePackage` | `exposedModules` is left out when absent. Absent exposes every module; an empty list exposes none. |
| `CompileOptions` | `extra` members sit beside `typesOnly` and `irVersion`. A writer refuses `extra` keys `typesOnly`, `irVersion`, `sourceRootUri` and `sourceRoot`; a reader refuses `sourceRootUri` and `sourceRoot`. |
| `SourceSet` | `root` is left out when absent. |
| `CompileRequest` | `dependencies` is read as empty when absent. `baseline` is left out when absent. Unknown members, including a top-level `documents`, are ignored. |
| `CompileResult` | `irVersion`, `ir` and `contextDigest` are left out when absent. `diagnostics` and `modules` are read as empty when absent. `moduleResults` is left out when empty. |
| `BaselineModule` | `dependsOn` is read as empty when absent. `frontendState` is left out when absent. |
| `CompileBaseline` | `modules` is read as empty when absent. `contextDigest` is left out when absent. |
| `ModuleStatus` | Wire values `compiled`, `unchanged`, `failed`, `blocked`. |
| `ModuleResult` | `sourceDigest`, `interfaceDigest`, `ir` and `frontendState` are left out when absent. `dependsOn` and `diagnostics` are read as empty when absent. |
| `GenerateRequest` | `options` is read as empty when absent. |
| `GenerateResult` | `artifacts` and `diagnostics` are read as empty when absent. |
| `Artifact` | When `binary` is true, `content` is base64. `binary` is read as false when absent. |
| `Diagnostic` | `code` and `location` are left out when absent. `related` is left out when empty. |
| `DiagnosticSeverity` | Wire values `error`, `warning`, `info`, `hint`. |
| `SourcePosition` | Zero-based. `character` counts UTF-16 code units, as in the Language Server Protocol. |

A later codec bead generates this mapping. Until then, this table and the doc comments are the record.

## Regenerate

After you change `contract/src/mep.gleam`:

```sh
mise run spec:mep        # compile the contract and refresh generated/mep.ir.json
mise run spec:mep-check  # run the contract tests, including the drift check
```

Commit `generated/mep.ir.json` with the change. The CLI compiles the contract with its built-in Gleam frontend (`--ir-version 4 --types-only`), so you do not need a Gleam toolchain. The `morphir CLI (test + integration)` CI job runs the same tests when `spec/mep/**` changes.

CI does not run `gleam format`, because CI has no Gleam toolchain. If you have Gleam installed, run `gleam format` in `spec/mep/contract` before you commit.

## Scope

The contract covers the types that `morphir-extension-sdk` defines today:

- the handshake: peers, `morphir.extension.describe`, `morphir.initialize` and extension identity
- capabilities and capability claim sets
- compile requests and results, including incremental baselines
- generate requests and results, and diagnostics
- method names and error codes

Not covered yet:

- Rust, TypeScript and Python types generated from the IR
- JSON Schema and WIT output (`generated/json-schema/`, `generated/wit/`)
- the MEP conformance suite (`mck/`)
- a typed IR payload in place of `Json`
- workspace discovery payloads, which live in `morphir_workspace`
- validate and transform payloads
- the JSON-RPC 2.0 envelope, which is a standard and not part of MEP
