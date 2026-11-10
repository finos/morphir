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
| `operations` | Required operations, in workflow order, at least one: `{ "operation": "compile", "language": "fsharp" }`, `{ "operation": "generate", "target": "fsharp" }`. The `fsharp` preset's readiness workflow runs these operations on the [F# readiness workflow case](./readiness-workflow.md) |
| `hosts` | Host offerings, at least one |
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
| `builtIns` | Built-in providers, at most one per operation: `operation`, `extensionId`, `version`, `modelInput` |
| `platforms` | The authenticated artifact (`target`, `sha256`) for each supported platform |

A `tool-release` source names a tool release metadata v1 tool id. Each separately published offering has its own tool id, so implementation and deployment are never inferred from an executable name. A v1 platform states no C library, so a `tool-release` offering lists no `linux-musl-*` platform. A `dotnet-tool` source binds the package bytes per platform like any other host artifact.

### Providers

Each provider has `operation`, `delivery` (`process`, `wasm` or `dotnet-tool`; built-ins belong to a host), `extensionId`, `version`, optional `prerequisites`, and the protocol members described for the [lock](./toolchain-lock.md#members). Delivery identities:

| `delivery` | Members |
| --- | --- |
| `process` | `repositoryId`, `descriptorTarget`, `descriptorSha256`, `platforms.<id>.artifactTarget`, `platforms.<id>.artifactSha256` |
| `wasm` | `abi`, `repositoryId`, `descriptorTarget`, `descriptorSha256`, `artifactTarget`, `artifactSha256` |
| `dotnet-tool` | `repositoryId`, `descriptorTarget`, `descriptorSha256`, `packageId`, `command`, `packageTarget`, `packageSha256` |

A `dotnet-tool` provider binds the extension release descriptor of the same release. The version-2 descriptor has no runtime for .NET tool packages, so the descriptor's claims are the authenticated statement of what the guest does, whichever delivery runs it.

An external provider never reuses a built-in identity. The standalone F# backend is `morphir-fsharp-backend`, not `morphir.fsharp`.

Understood critical paths: `schemaVersion`, `critical`, `preset`, `version`, `operations`, `hosts` and `hosts.<member>` for each host member above, `hosts.platforms.*`, `hosts.platforms.*.target`, `hosts.platforms.*.sha256`, `providers` and `providers.<member>` for each provider member above, `providers.platforms.*`, `providers.platforms.*.artifactTarget`, `providers.platforms.*.artifactSha256`.

## Consistency rules

A reader refuses each of these with `inconsistent_document`. The fixture under `fixtures/0.1.0-draft.1/recipe/negative/` that pins each rule is named after it:

| Rule | Path | Fixture |
| --- | --- | --- |
| At least one operation | `operations` | `no-operations.json` |
| At least one host offering | `hosts` | `no-hosts.json` |
| No duplicate operation | `operations[i]` | `duplicate-operation.json` |
| One offering per implementation and deployment | `hosts[i]` | `duplicate-offering.json` |
| At most one built-in per operation in an offering | `hosts[i].builtIns[j]` | `second-built-in.json` |
| No duplicate provider (same operation, identity, delivery and version) | `providers[i]` | `duplicate-provider.json` |
| An external provider never uses a built-in identity | `providers[i].extensionId` | `external-impersonates-built-in.json` |
| A `tool-release` offering lists no musl platform | `hosts[i].platforms.<id>` | `musl-bound-to-tool-release.json` |
| Every offering can perform every operation with a built-in or a fitting provider | `operations[i]` | `operation-without-candidate.json` |
| A `modelTuple` operation performs the provider's operation | `providers[i].modelTuple.operation` | `tuple-operation-mismatch.json` |
| The compatibility member matches `protocolVersion` | `providers[i].modelTuple` | `legacy-protocol-with-model-tuple.json` |
| A process provider lists at least one platform | `providers[i].platforms` | `process-without-platforms.json` |

A provider *fits* a host offering on a platform when the host speaks its MEP version, a process provider has an artifact for that platform, and a WASM provider's ABI is one the host lists in `wasmAbis`.

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

`schemaVersion` here is the recipe contract version, not the version 1 profile's numeric `schemaVersion`. Channel membership and `status` (`active`, `yanked` or `revoked`) are current authenticated state, with the version 1 rules: a moving channel selects the greatest `active` recipe for the preset on that channel, and `stable` admits only final versions. A recipe on no channel is reachable only by its exact target path. A recipe target whose path breaks the [target path rules](./index.md#target-paths) is refused with `non_portable_path`.

The TUF client authenticates the metadata. A manager then checks the recipe target, in this order, and refuses with the first failure. Refusals about the recipe target itself have the empty path:

| Check | Code | Path |
| --- | --- | --- |
| The recipe is an authenticated target whose bytes have the authenticated length and digest | `target_not_authenticated`, `target_length_mismatch`, `target_digest_mismatch` | empty |
| Its `custom.morphir` has `kind` `toolset-recipe`, `schemaVersion` `0.1.0-draft.1`, a preset token, a SemVer version, channels and a known status | `release_descriptor_mismatch` | empty |
| Its status is not `revoked` | `release_revoked` | empty |
| The document reads as a `0.1.0-draft.1` recipe | the reader's codes | the member |
| The document's `preset` and `version` equal the authenticated ones | `release_descriptor_mismatch` | empty |

Then each host offering, in order:

| Check | Code | Path |
| --- | --- | --- |
| A `tool-release` offering's descriptor `releases/<toolId>/<version>.json` is an authenticated `tool-release` target for that tool and version | `target_not_authenticated` | `hosts[i].source` |
| That release's current status is not `revoked` | `release_revoked` | `hosts[i].version` |
| The descriptor reads as a version 1 tool release | `release_descriptor_mismatch` | `hosts[i].source` |
| Each platform's `target` is an authenticated target | `target_not_authenticated` | `hosts[i].platforms.<id>.target` |
| Its `sha256` equals the authenticated digest | `target_digest_mismatch` | `hosts[i].platforms.<id>.sha256` |
| The release lists the target | `release_descriptor_mismatch` | `hosts[i].platforms.<id>.target` |
| The listed artifact's version 1 platform is the bound platform | `artifact_platform_mismatch` | `hosts[i].platforms.<id>.target` |
| The target's `custom.morphir` is `kind` `tool-artifact` with the release's tool id, version and that platform | `release_descriptor_mismatch` | `hosts[i].platforms.<id>.target` |

Then each provider, in order:

| Check | Code | Path |
| --- | --- | --- |
| `descriptorTarget` is authenticated with `descriptorSha256` | `target_not_authenticated`, `target_digest_mismatch` | `providers[i].descriptorTarget`, `providers[i].descriptorSha256` |
| The descriptor reads, with the existing reader, as an extension release descriptor | `release_descriptor_mismatch` | `providers[i].descriptorTarget` |
| The descriptor's own `extensionId` is the provider's `extensionId` | `release_descriptor_mismatch` | `providers[i].extensionId` |
| The descriptor's `version` is the provider's `version` | `release_descriptor_mismatch` | `providers[i].version` |
| Every artifact's claims name the descriptor's `extensionId` and `version`, as publication already requires | `release_descriptor_mismatch` | `providers[i].descriptorTarget` |
| Each bound artifact (`artifactTarget`) and package (`packageTarget`) is authenticated with its digest | `target_not_authenticated`, `target_digest_mismatch` | the bound member |
| The descriptor lists the artifact in its own directory | `release_descriptor_mismatch` | `…artifactTarget` |
| The listed artifact has the delivery's runtime (`process` or `wasm`) | `release_descriptor_mismatch` | `…artifactTarget` |
| The listed artifact has the bound digest | `target_digest_mismatch` | `…artifactSha256` |
| A process artifact's target triple is the bound platform's | `artifact_platform_mismatch` | `…artifactTarget` |
| The claims list the capability kind: `frontend` for `compile`, `backend` for `generate` | `release_descriptor_mismatch` | `providers[i].operation` |
| The claims list the provider's MEP version in `protocolVersions` | `release_descriptor_mismatch` | `providers[i].protocolVersion` |
| The claims support the language (`capabilities.frontend.compile` is `true` and `languages` has its `id`) or the target (`capabilities.backend.generate` is `true` and `targets` has it) | `release_descriptor_mismatch` | `providers[i].language` or `providers[i].target` |
| For MEP `0.2.0-draft.1`, `capabilities.modelTransport.tuples` contains the provider's `modelTuple` exactly; for MEP `0.1`, the capability's `irVersions` contains the IR version or its major | `release_descriptor_mismatch` | `providers[i].modelTuple` or `providers[i].modelInput.irVersion` |

A `dotnet-tool` provider's capability is checked against every artifact's claims in its descriptor. Authentication alone is never enough: the signed fixtures publish a validly signed recipe for each refusal above.

### What revocation reaches

Version 1 release status exists only for `tool-release` targets, so a learned revocation reaches a `tool-release` host offering directly. A `dotnet-tool` host and every provider have no version 1 release status: revocation reaches them only through the recipe target that binds them, by revoking that recipe and publishing a corrected one.

### Claim checks and publisher authentication

These are separate facts and stay separate. A recipe digest authenticates an extension's bytes: it says the repository's publisher bound exactly these bytes to this toolset. It says nothing about whether anyone ran the artifact to compare its capability claims. A descriptor written by bundle authoring keeps `claimCheck: unchecked`, and a recipe never changes that. The install-time probe, or `--no-probe`, decides the installed record's `claimCheck`, and the [receipt](./installation-receipt.md#installation) records it beside `authentication`. A probed artifact is not thereby authenticated; an unsigned developer artifact can be probed and is still `local-developer`. No recipe can bind an unsigned developer artifact, because it is not an authenticated target, so it can appear in a local receipt under explicit developer policy and never in a portable lock.

## Selecting a closure

Resolution is pure: it reads a recipe, a request and a platform and performs no I/O.

1. The request's preset is the recipe's preset. Take the offering whose `implementation` and `deployment` equal the request's. An exact request also requires an equal `version`.
2. Take the offering's artifact for the platform. No other platform, deployment or implementation is substituted.
3. For each operation, in order:
   - With an explicit request choice, take the offering's built-in for the operation if the choice allows it (its `delivery` is absent or `built-in`, its `extensionId` is absent or the built-in's, and it names no `abi`). Otherwise take the first recipe provider for the operation whose delivery, identity and ABI match the choice. That provider must fit.
   - Without a choice, take the offering's built-in for the operation. Without one, take the recipe's first provider for the operation. That provider must fit.
   - A provider that does not fit is never skipped in favor of another. Resolution fails, naming why.
4. Write the host and each selected provider into the lock closure.

| Failure | Code | Path |
| --- | --- | --- |
| The recipe is for another preset | `unsupported_artifact` | `toolset.preset` |
| No offering for the implementation and deployment | `unsupported_artifact` | `host` |
| The offering's release is not the exact requested one | `unsupported_artifact` | `host.version` |
| The offering has no artifact for the platform | `unsupported_artifact` | `platforms` |
| The preferred provider needs a WASM ABI the host lacks | `abi_unavailable` | `toolset` |
| The preferred provider does not fit for another reason, or no provider performs the operation | `unsupported_artifact` | `toolset` |
| No built-in or provider matches an explicit choice | `unsupported_artifact` | `toolset.providers[i]` |
| The chosen provider needs a WASM ABI the host lacks | `abi_unavailable` | `toolset.providers[i]` |
| The chosen provider does not fit for another reason | `unsupported_artifact` | `toolset.providers[i]` |

A WASM guest for another ABI is therefore chosen only when the request names that ABI. Otherwise setup reports the missing ABI and does not report ready. Plan-only setup may refresh metadata, but it never runs an acquired artifact. Readiness probes happen after staging, under the existing launch controls.

## Open questions for the maintainer

- **Dotted provider identities.** The approved lock example and morphir-dotnet's real frontend guest use the dotted identity `org.finos.morphir.fsharp-frontend`. The version-2 extension release descriptor requires a single portable token for `extensionId`, and publication requires artifact claims to name that same identity. A recipe binding therefore cannot bind an external provider whose identity is dotted; the lock grammar still accepts dotted identities, and built-in identities such as `morphir.fsharp` are unaffected. Supporting dotted identities for external providers would need a separately reviewed change to the descriptor contract. The signed fixtures use `morphir-fsharp-frontend` for both the descriptor and the claims.
- **`compatibility.morphirCli` for offerings.** Version 1 requires every release descriptor to state the Morphir CLI versions that may acquire it, and its resolver filters by the acquiring CLI's version. A manager is not the Morphir CLI and has no honest value to pass. The comparator `>=0.0.0` used by the fixture offerings matches no prerelease CLI, so it does not mean "any". A manager does not use version 1 channel resolution for offerings: it resolves the recipe, then checks each host binding against the authenticated release and its targets as above, which never evaluates `morphirCli`. What offering descriptors should publish there is undecided. The fixtures' `referenceClient.cliVersion` exists only to drive this repository's existing v1 client in its own test.

## Fixtures

`fixtures/0.1.0-draft.1/recipe/fsharp-synthetic.json` describes the four .NET offerings on the six first-delivery platforms, the F# frontend as a process guest and as the existing framework-dependent .NET tool, and the standalone F# backend process guest. Every offering keeps the built-in `morphir.fsharp` generator. It is unsigned and binds nothing, so it keeps the dotted frontend identity of the approved example. `wasm-abi-alternatives.json` offers a backend for two WASM ABIs to a host that supports only `morphir-bytes-v1`; its `resolve` cases show that resolution reports `abi_unavailable` unless the request chooses the other ABI. `critical-nested-platform-member.json` names a platform member as critical. `recipe/negative/` has the fixtures in the consistency table plus a later draft, an unknown critical member and an unknown nested critical member, a WASM provider without an ABI, an uppercase identity, an identity token over 64 characters, an unknown source kind and a credential member.

The TEST-ONLY signed repository in `fixtures/0.1.0-draft.1/signed/repository.json` publishes the three archive offerings as version 1 tool releases on the six first-delivery platforms, the `Morphir.Tool` package, the F# frontend `morphir-fsharp-frontend` 0.6.0 and the standalone backend `morphir-fsharp-backend` 0.1.0 as version-2 extension releases, the `fsharp-builtin` and `fsharp` recipes, and a validly signed recipe for each refusal in the tables above. `signed/cases.json` lists them in `recipeChecks`, together with the trust cases, frozen locks and lock-against-recipe cases described in the [overview](./index.md#fixtures-and-conformance). Three frozen requests and their locks record complete closures on all six first-delivery platforms:

| Files | Selection |
| --- | --- |
| `fsharp-native-aot.toml`, `.lock.json` | Native AOT host, process frontend, built-in `morphir.fsharp` backend |
| `fsharp-native-aot-external-backend.toml`, `.lock.json` | The same host and frontend, explicit external backend process guest |
| `fsharp-framework-dependent-tool-frontend.toml`, `.lock.json` | Framework-dependent host, explicit .NET tool frontend, built-in backend |

Every key in that repository is derived from a public label recorded in `testOnlyKeys`, so anyone can sign with it. Never trust that repository, its keys or its `repositoryId` outside tests.
