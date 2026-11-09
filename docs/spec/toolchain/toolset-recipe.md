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

## Authenticated recipe targets

A recipe is published as a TUF target at `toolchains/recipes/<preset>/<version>.json` in a repository that follows [tool release metadata v1](../tool-release-metadata/index.md#offering-specific-tool-ids). Its `custom.morphir` object is:

```json
{
  "kind": "toolset-recipe",
  "schemaVersion": "0.1.0-draft.1",
  "preset": "fsharp",
  "version": "1.0.0",
  "channels": ["stable"],
  "status": "active"
}
```

`schemaVersion` here is the recipe contract version, not the version 1 profile's numeric `schemaVersion`. Channel membership and status are current authenticated state, with the version 1 rules: a moving channel selects the greatest `active` recipe for the preset on that channel, and `stable` admits only final versions. A recipe on no channel is reachable only by its exact target path.

The TUF client authenticates the metadata. A manager then checks the recipe and every host binding, in this order, and refuses with the first failure:

| Check | Code |
| --- | --- |
| The recipe bytes have the authenticated length and digest | `target_not_authenticated`, `target_length_mismatch`, `target_digest_mismatch` |
| A `tool-release` offering's descriptor `releases/<toolId>/<version>.json` is an authenticated `tool-release` target that is not revoked | `target_not_authenticated`, `release_revoked` |
| Each platform's `target` is an authenticated target | `target_not_authenticated` |
| Its `sha256` equals the authenticated digest | `target_digest_mismatch` |
| The offering's release lists the target | `release_descriptor_mismatch` |
| The artifact's version 1 platform is the bound platform | `artifact_platform_mismatch` |

Authentication alone is not enough: each refusal above has a fixture recipe that is validly signed and still wrong.
## Selecting a closure

Resolution is pure: it reads a recipe, a request and a platform and performs no I/O.

1. The request's preset is the recipe's preset. Take the offering whose `implementation` and `deployment` equal the request's. An exact request also requires an equal `version`. Otherwise report `unsupported_artifact` with the offerings that exist.
2. Take the offering's artifact for the platform. A missing platform is `unsupported_artifact`; no other platform, deployment or implementation is substituted.
3. For each operation, in order: an explicit request choice selects the first built-in or fitting provider with its `delivery` and `extensionId`; if none matches, the result is `unsupported_artifact`. Without one, a built-in for the operation wins. Otherwise the first provider, in recipe order, that fits the host: the host speaks its MEP version, a process provider has an artifact for the platform, and a WASM provider's ABI is one the host supports.
4. Write the host and each selected provider into the lock closure.

A refusal's path names the request member that cannot be met: `toolset.preset`, `host` (implementation or deployment), `host.version`, `platforms`, `toolset` (no provider for an operation) or `toolset.providers[i]` (an explicit choice).

Plan-only setup may refresh metadata, but it never runs an acquired artifact. Readiness probes happen after staging, under the existing launch controls.

## Fixtures

`fixtures/0.1.0-draft.1/recipe/fsharp-synthetic.json` describes the four .NET offerings on the six first-delivery platforms, the F# frontend as a process guest and as the existing framework-dependent .NET tool, and the standalone F# backend process guest. Every offering keeps the built-in `morphir.fsharp` generator. `wasm-abi-alternatives.json` offers a backend for two WASM ABIs to a host that supports only `morphir-bytes-v1`. `recipe/negative/` covers each consistency rule plus a later draft, an unknown critical member, a WASM provider without an ABI, an uppercase identity, a process provider without platforms and an unknown source kind.

The TEST-ONLY signed repository in `fixtures/0.1.0-draft.1/signed/repository.json` publishes the three archive offerings as version 1 tool releases on the six first-delivery platforms, the `Morphir.Tool` package, the `fsharp-builtin` recipe, and four validly signed recipes that each break one binding rule. `signed/cases.json` lists the selection cases and the recipe binding cases with their expected targets or codes. Every key in that repository derives from a public label recorded in `testOnlyKeys`, so anyone can sign with it. Never trust that repository, its keys or its `repositoryId` outside tests.
