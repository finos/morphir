---
title: Toolset recipe 0.1.0-draft.1
sidebar_label: Toolset recipe
status: draft
---

# Toolset recipe 0.1.0-draft.1

A toolset recipe is an ordinary authenticated TUF target in a tool repository, for example `toolchains/recipes/fsharp/1.0.0.json`. It says which host offerings support a preset, where each offering is published, and which built-in or independently released provider performs each required operation, with exact digests. It does not change the extension descriptor format and does not claim that an extension repository signs its own releases. Version authority: this page. Schema: [toolset-recipe-0.1.0-draft.1.schema.json](/schemas/toolset-recipe-0.1.0-draft.1.schema.json).

## Members

| Member | Meaning |
| --- | --- |
| `schemaVersion`, `critical` | As for every toolchain document |
| `preset` | Preset token, such as `fsharp` |
| `version` | Recipe release |
| `operations` | Required operations, in workflow order: `{ "operation": "compile", "language": "fsharp" }`, `{ "operation": "generate", "target": "fsharp" }` |
| `hosts` | Host offerings |
| `providers` | Independently released providers, in preference order |

### Host offerings

| Member | Meaning |
| --- | --- |
| `implementation`, `version`, `deployment` | The offering's identity. A recipe has one offering per implementation and deployment |
| `execution` | `native-aot` or `jit` |
| `source` | `{ "kind": "tool-release", "toolId": … }` or `{ "kind": "dotnet-tool", "packageId": …, "command": … }` |
| `protocolVersions` | MEP versions the host speaks |
| `wasmAbis` | WASM ABIs the host's qualified engine supports; empty when it has none |
| `prerequisites` | Runtime, SDK and native prerequisites |
| `builtIns` | Built-in providers: `operation`, `extensionId`, `version`, `modelInput` |
| `platforms` | The authenticated artifact (`target`, `sha256`) for each supported platform |

A `tool-release` source names a tool release metadata v1 tool id. Each separately published offering has its own tool id, so implementation and deployment are never inferred from an executable name. A v1 platform states no C library, so a `tool-release` offering lists no `linux-musl-*` platform. A `dotnet-tool` source binds the package bytes per platform like any other host artifact.

### Providers

Each provider has `operation`, `delivery` (`process`, `wasm` or `dotnet-tool`; built-ins belong to a host), `extensionId`, `version`, optional `prerequisites`, and the protocol members described for the [lock](./toolchain-lock.md#members). Delivery identities:

| `delivery` | Members |
| --- | --- |
| `process` | `repositoryId`, `descriptorTarget`, `descriptorSha256`, `platforms.<id>.artifactTarget`, `platforms.<id>.artifactSha256` |
| `wasm` | `abi`, `repositoryId`, `descriptorTarget`, `descriptorSha256`, `artifactTarget`, `artifactSha256` |
| `dotnet-tool` | `repositoryId`, `packageId`, `command`, `packageTarget`, `packageSha256` |

An external provider never reuses a built-in identity. The standalone F# backend is `morphir-fsharp-backend`, not `morphir.fsharp`.

Understood critical paths: `schemaVersion`, `critical`, `preset`, `version`, `operations`, `hosts` and `hosts.<member>` for each host member above, `providers` and `providers.<member>` for each provider member above.

## Consistency rules

A reader refuses with `inconsistent_document`:

- a duplicate operation, a second offering for one implementation and deployment, or a second built-in for one operation;
- a duplicate provider (same operation, identity, delivery and version);
- an external provider whose `extensionId` is a built-in identity;
- a `tool-release` offering with a musl platform;
- an operation that some offering can perform neither with a built-in nor with a compatible provider;
- a `modelTuple` whose method does not perform the provider's operation, or compatibility members that do not match `protocolVersion`.

## Fixtures

`fixtures/0.1.0-draft.1/recipe/fsharp-synthetic.json` describes the four .NET offerings on the six first-delivery platforms, the F# frontend as a process guest and as the existing framework-dependent .NET tool, and the standalone F# backend process guest. Every offering keeps the built-in `morphir.fsharp` generator. `wasm-abi-alternatives.json` offers a backend for two WASM ABIs to a host that supports only `morphir-bytes-v1`. `recipe/negative/` covers each consistency rule plus a later draft, an unknown critical member, a WASM provider without an ABI, an uppercase identity, a process provider without platforms and an unknown source kind.
