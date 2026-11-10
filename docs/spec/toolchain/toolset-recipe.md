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
| `wasmAbis` | WASM ABIs the host's qualified engine supports. Optional; absent or empty when it has none |
| `prerequisites` | Runtime, SDK and native prerequisites. Optional; absent means none |
| `builtIns` | Built-in providers, at most one per operation: `operation`, `extensionId`, `version`, and the model the built-in exchanges with the host. That is `modelOutput` for a `compile` built-in, which writes the model, and `modelInput` for a `generate` built-in, which reads it; the other member is `inconsistent_document`. Optional; absent means none |
| `platforms` | The authenticated artifact (`target`, `sha256`) for each supported platform |

For the `fsharp` preset, every .NET offering has the built-in generator `morphir.fsharp`. The three managed offerings (`self-contained`, `framework-dependent` and `dotnet-tool`) also have the in-process F# frontend `morphir-dotnet.fsharp` as a `compile` built-in, so resolution selects it by default, as morphir-dotnet's `cli-model-compilation` specification requires. The Native AOT offering excludes the compiler services and has no frontend built-in, so it resolves the recipe's process frontend.

A `tool-release` source names a tool release metadata v1 tool id. Each separately published offering has its own tool id, so implementation and deployment are never inferred from an executable name. A v1 platform states no C library, so a `tool-release` offering lists no `linux-musl-*` platform. A `dotnet-tool` source binds the package bytes per platform like any other host artifact.

### Providers

Each provider has `operation`, `delivery` (`process`, `wasm` or `dotnet-tool`; built-ins belong to a host), `extensionId`, `version`, optional `prerequisites`, and the protocol members described for the [lock](./toolchain-lock.md#members). Delivery identities:

| `delivery` | Members |
| --- | --- |
| `process` | `repositoryId`, `descriptorTarget`, `descriptorSha256`, `platforms.<id>.artifactTarget`, `platforms.<id>.artifactSha256` |
| `wasm` | `abi`, `repositoryId`, `descriptorTarget`, `descriptorSha256`, `artifactTarget`, `artifactSha256` |
| `dotnet-tool` | `repositoryId`, `descriptorTarget`, `descriptorSha256`, `packageId`, `command`, `packageTarget`, `packageSha256` |

A `dotnet-tool` provider binds the extension release descriptor of the same release. The version-2 descriptor has no runtime for .NET tool packages, so the descriptor's claims are the authenticated statement of what the guest does, whichever delivery runs it. `descriptorTarget` and `descriptorSha256` are therefore required for a `dotnet-tool` provider, in a recipe and in a lock; a provider without them is `invalid_document` at the missing member. A provider shipped only as a NuGet tool cannot be bound until its release also publishes a version-2 descriptor (see [limits](#limits-of-this-contract-version)).

An external provider never reuses a built-in identity. The standalone F# backend is `org.finos.morphir.fsharp-backend` (bound as `morphir-fsharp-backend` until finos/morphir#1149 lands), not `morphir.fsharp`.

Understood critical paths: `schemaVersion`, `critical`, `preset`, `version`, `operations`, `hosts` and `hosts.<member>` for each host member above, `hosts.platforms.*`, `hosts.platforms.*.target`, `hosts.platforms.*.sha256`, `providers` and `providers.<member>` for each provider member above, `providers.platforms.*`, `providers.platforms.*.artifactTarget`, `providers.platforms.*.artifactSha256`. These exact strings are the understood forms; see [unknown and critical members](./index.md#unknown-and-critical-members).

## Consistency rules

A reader refuses each of these with `inconsistent_document`. The fixture under `fixtures/0.1.0-draft.1/recipe/negative/` that pins each rule is named after it.

The first four rules marked *while reading* concern one object and are checked as that object is read, in [reading order](./index.md#order-of-checks). The others are checked once the whole document has been read, in the order of this table; each of them is checked over its whole array, in index order, before the next rule is checked. So a recipe whose second host repeats the first offering and whose first host has a second built-in is refused at `hosts[1]` (`precedence-consistency-table-order.json`).

| Rule | Checked | Path | Fixture |
| --- | --- | --- | --- |
| A `tool-release` offering lists no musl platform | while reading | `hosts[i].platforms.<id>` | `musl-bound-to-tool-release.json` |
| A process provider lists at least one platform | while reading | `providers[i].platforms` | `process-without-platforms.json` |
| A `modelTuple` operation performs the provider's operation | while reading | `providers[i].modelTuple.operation` | `tuple-operation-mismatch.json` |
| The compatibility member matches `protocolVersion` | while reading | `providers[i].modelTuple` | `legacy-protocol-with-model-tuple.json` |
| At least one operation | after reading | `operations` | `no-operations.json` |
| At least one host offering | after reading | `hosts` | `no-hosts.json` |
| No duplicate operation | after reading | `operations[i]` | `duplicate-operation.json` |
| One offering per implementation and deployment | after reading | `hosts[i]` | `duplicate-offering.json` |
| At most one built-in per operation in an offering | after reading | `hosts[i].builtIns[j]` | `second-built-in.json` |
| No duplicate provider (same operation, identity, delivery and version) | after reading | `providers[i]` | `duplicate-provider.json` |
| An external provider never uses a built-in identity | after reading | `providers[i].extensionId` | `external-impersonates-built-in.json` |
| Every offering can perform every operation with a built-in or a provider that fits it on some platform | after reading | `operations[i]` | `operation-without-candidate.json`, `operation-without-candidate-no-shared-platform.json` |

A provider *fits* a host offering on a platform when the host speaks its MEP version, a process provider has an artifact for that platform, and a WASM provider's ABI is one the host lists in `wasmAbis`. A `dotnet-tool` provider has no platform artifacts, so only the MEP version decides its fit.

The last consistency rule asks about a recipe, not about one platform, so it uses fit without a platform: a process provider fits an offering when the host speaks its MEP version and the provider has an artifact for at least one platform the offering also lists. The provider need not fit on every platform. `recipe/provider-misfit.json` is valid although its frontend has an artifact only for `win-x64` and its host also lists `osx-arm64`; resolution on `osx-arm64` then fails with `unsupported_artifact` at `toolset`. `recipe/negative/operation-without-candidate-no-shared-platform.json` has a frontend whose only platform the host does not list, and is refused.

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

`schemaVersion` here is the recipe contract version, not the version 1 profile's numeric `schemaVersion`. Channel membership and `status` (`active`, `yanked` or `revoked`) are current authenticated state, with the version 1 rules:

- a moving channel selects, among the recipe targets of the preset whose status is `active` and that are on that channel, the one with the greatest SemVer `version`;
- `stable` admits only final versions, so a prerelease listed on `stable` is never selected for it;
- `preview` and `insiders` select from every recipe on `preview`, any `preview/<name>` channel or `insiders`; a named `preview/<name>` selects only recipes on exactly that channel;
- a `yanked` recipe is skipped by channels and is still read by its exact target path; a `revoked` one is refused;
- when nothing is selected, the result is `unsupported_artifact` at `toolset.preset`.

A recipe on no channel is reachable only by its exact target path. The `channelSelection` cases pin each of these rules.

### One repository per binding check

The checks below run against one authenticated repository: the one whose metadata the TUF client loaded from an out-of-band trusted root. Its identity is the [tool release metadata v1 repository identity](../tool-release-metadata/index.md): the lowercase SHA-256 of the [canonical JSON](./manager-result.md#the-plan-digest) bytes of the trusted root's `signed` object. The root's signatures are not part of it, and a later root rotation does not change it. For the TEST-ONLY signed repository it is the `repositoryId` recorded in `signed/repository.json`.

The recipe target, every host release and artifact, and every provider descriptor, artifact and package are authenticated by that repository. A provider whose `repositoryId` names any other repository is refused with `repository_mismatch` at `providers[i].repositoryId`, before its descriptor is read, so a recipe cannot bind a provider to a trust root other than the one that authenticated the bytes. Host offerings name no repository: their releases and artifacts are this repository's targets. The lock and receipt checks apply the same rule.

Binding providers from several repositories in one recipe is not part of this contract version; it is later work. A provider published in another repository is bound by a recipe in that repository. Target path layouts name an extension by its descriptor's `shortId`, such as `extensions/fsharp-frontend/0.6.0/release.json`, never by its extension id, so a long or dotted id never lengthens a target path.

The TUF client authenticates the metadata. A manager then checks the recipe target, in this order, and refuses with the first failure. Refusals about the recipe target itself have the empty path; the empty path is never used for any other target. The Cases column names the `rule` of the cases in `signed/cases.json` and `cases.json` that pin each row.

| Check | Code | Path | Cases |
| --- | --- | --- | --- |
| The recipe target path follows the [target path rules](./index.md#target-paths). This is checked before anything is read | `non_portable_path` | empty | `recipe-target-portable` |
| The recipe is an authenticated target whose bytes have the authenticated length and digest | `target_not_authenticated`, `target_length_mismatch`, `target_digest_mismatch` | empty | `recipe-target-authenticated` |
| Its `custom.morphir` has `kind` `toolset-recipe`, `schemaVersion` `0.1.0-draft.1`, a preset token, a SemVer version, channels and a known status | `release_descriptor_mismatch` | empty | `recipe-target-state` |
| Its status is not `revoked` | `release_revoked` | empty | `recipe-target-revoked` |
| The document reads as a `0.1.0-draft.1` recipe | the reader's codes | the member | `recipe-document-reads` |
| The document's `preset` and `version` equal the authenticated ones | `release_descriptor_mismatch` | empty | `recipe-document-identity` |

A target's bytes are checked for length before digest, whether they are read through the TUF client or compared with [`authenticate`](./index.md#fixtures-and-conformance): bytes longer or shorter than the authenticated length are `target_length_mismatch`, and bytes of that length with another SHA-256 are `target_digest_mismatch`.

Then each host offering, in order. A failed read of a target that a binding names is reported at that binding member, never at the empty path:

| Check | Code | Path | Cases |
| --- | --- | --- | --- |
| A `tool-release` offering's descriptor `releases/<toolId>/<version>.json` is an authenticated `tool-release` target for that tool and version | `target_not_authenticated` | `hosts[i].source` | `host-release-authenticated` |
| That release's current status is not `revoked` | `release_revoked` | `hosts[i].version` | `host-release-revoked` |
| The descriptor bytes have the authenticated length and digest | `target_length_mismatch`, `target_digest_mismatch` | `hosts[i].source` | `host-release-read` |
| The descriptor reads as a version 1 tool release | `release_descriptor_mismatch` | `hosts[i].source` | `host-release-v1` |
| Each platform's `target` is an authenticated target | `target_not_authenticated` | `hosts[i].platforms.<id>.target` | `host-target-authenticated` |
| Its `sha256` equals the authenticated digest | `target_digest_mismatch` | `hosts[i].platforms.<id>.sha256` | `host-target-digest` |
| The release lists the target | `release_descriptor_mismatch` | `hosts[i].platforms.<id>.target` | `host-target-listed` |
| The listed artifact's version 1 platform is the bound platform | `artifact_platform_mismatch` | `hosts[i].platforms.<id>.target` | `host-target-platform` |
| The target's `custom.morphir` is `kind` `tool-artifact` with the release's tool id, version and that platform | `release_descriptor_mismatch` | `hosts[i].platforms.<id>.target` | `host-target-metadata` |

A `dotnet-tool` offering has no version 1 release, so only its platform `target` and `sha256` rows apply. The platforms of an offering are checked in [platform table order](./index.md#order-of-checks).

Then each provider, in order:

| Check | Code | Path | Cases |
| --- | --- | --- | --- |
| `repositoryId` is the identity of the authenticated repository the checks run against | `repository_mismatch` | `providers[i].repositoryId` | `provider-repository` |
| `descriptorTarget` is authenticated with `descriptorSha256` | `target_not_authenticated`, `target_digest_mismatch` | `providers[i].descriptorTarget`, `providers[i].descriptorSha256` | `provider-descriptor-bound` |
| The descriptor bytes have the authenticated length and digest | `target_length_mismatch`, `target_digest_mismatch` | `providers[i].descriptorTarget` | `provider-descriptor-read` |
| The descriptor reads, with the existing reader, as an extension release descriptor | `release_descriptor_mismatch` | `providers[i].descriptorTarget` | `provider-descriptor-parses` |
| The descriptor's own `extensionId` is the provider's `extensionId` | `release_descriptor_mismatch` | `providers[i].extensionId` | `provider-descriptor-identity` |
| The descriptor's `version` is the provider's `version` | `release_descriptor_mismatch` | `providers[i].version` | `provider-descriptor-version` |
| Every artifact's claims name the descriptor's `extensionId` and `version`, as publication already requires | `release_descriptor_mismatch` | `providers[i].descriptorTarget` | `provider-claims-identity` |
| Each bound artifact (`artifactTarget`) and package (`packageTarget`) is authenticated with its digest | `target_not_authenticated`, `target_digest_mismatch` | the bound member | `provider-artifact-bound` |
| The descriptor lists the artifact in its own directory | `release_descriptor_mismatch` | `…artifactTarget` | `provider-artifact-listed` |
| The listed artifact has the delivery's runtime (`process` or `wasm`) | `release_descriptor_mismatch` | `…artifactTarget` | `provider-artifact-runtime` |
| The listed artifact has the bound digest | `target_digest_mismatch` | `…artifactSha256` | `provider-artifact-digest-listed` |
| A process artifact's target triple is the bound platform's | `artifact_platform_mismatch` | `…artifactTarget` | `provider-artifact-platform` |
| The claims list the capability kind: `frontend` for `compile`, `backend` for `generate` | `release_descriptor_mismatch` | `providers[i].operation` | `provider-claims-kind` |
| The claims list the provider's MEP version in `protocolVersions` | `release_descriptor_mismatch` | `providers[i].protocolVersion` | `provider-claims-protocol` |
| The claims support the language (`capabilities.frontend.compile` is `true` and `languages` has its `id`) or the target (`capabilities.backend.generate` is `true` and `targets` has it) | `release_descriptor_mismatch` | `providers[i].language`, `providers[i].target` | `provider-claims-operand` |
| For MEP `0.2.0-draft.1`, `capabilities.modelTransport.tuples` contains the provider's `modelTuple` exactly; for MEP `0.1`, the capability's `irVersions` contains the IR version or its major | `release_descriptor_mismatch` | `providers[i].modelTuple`, `providers[i].modelInput.irVersion` | `provider-claims-model` |

A process provider's platforms are checked in platform table order, and for each platform the artifact rows apply in the order above. A `wasm` provider has one artifact, at `providers[i].artifactTarget` and `providers[i].artifactSha256`. A `dotnet-tool` provider's package is checked by the bound-member row, and its capability rows are checked against every artifact's claims in its descriptor.

Authentication alone is never enough: for each refusal in these three tables the signed fixtures publish a validly signed recipe, or declare a trust case, that is refused for exactly that reason. The coverage test in this repository fails when a row names no case and is not marked as having none.

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

The failures are checked in this order, and the operations in the recipe's order. `toolset.providers[i]` names the request's choice for the operation.

| Failure | Code | Path | Cases |
| --- | --- | --- | --- |
| The recipe is for another preset | `unsupported_artifact` | `toolset.preset` | `resolve-preset` |
| No offering for the implementation and deployment | `unsupported_artifact` | `host` | `resolve-offering` |
| The offering's release is not the exact requested one | `unsupported_artifact` | `host.version` | `resolve-release` |
| The offering has no artifact for the platform | `unsupported_artifact` | `platforms` | `resolve-platform` |
| The preferred provider needs a WASM ABI the host lacks | `abi_unavailable` | `toolset` | `resolve-preferred-abi` |
| The preferred provider does not fit for another reason | `unsupported_artifact` | `toolset` | `resolve-preferred-misfit` |
| No built-in or provider performs the operation | `unsupported_artifact` | `toolset` | No fixture: a recipe that passes its consistency rules has a built-in or a provider for every operation, so a reader refuses such a recipe before resolution can reach this row |
| No built-in or provider matches an explicit choice | `unsupported_artifact` | `toolset.providers[i]` | `resolve-choice-unmatched` |
| The chosen provider needs a WASM ABI the host lacks | `abi_unavailable` | `toolset.providers[i]` | `resolve-choice-abi` |
| The chosen provider does not fit for another reason | `unsupported_artifact` | `toolset.providers[i]` | `resolve-choice-misfit` |

A WASM guest for another ABI is therefore chosen only when the request names that ABI. Otherwise setup reports the missing ABI and does not report ready. Plan-only setup may refresh metadata, but it never runs an acquired artifact. Readiness probes happen after staging, under the existing launch controls.

## Limits of this contract version

- **Dotted provider identities are decided; the descriptor change is pending.** Release descriptors will allow dotted extension ids, with the descriptor id equal to the claims id, through the separately reviewed change finos/morphir#1149. The external F# guests are `org.finos.morphir.fsharp-frontend` and `org.finos.morphir.fsharp-backend`. Until #1149 lands, a version-2 descriptor accepts only a single token, so the TEST-ONLY signed fixtures bind `morphir-fsharp-frontend` and `morphir-fsharp-backend`. They move to the dotted ids in #1149's toolchain task, together with the provider identity grammar (see [identifiers](./index.md#identifiers)). Built-in identities such as `morphir.fsharp` and `morphir-dotnet.fsharp` are unaffected, because a built-in has no descriptor.
- **A provider must publish a version-2 descriptor.** Public toolset recipes bind extension artifacts and descriptors (approved toolchain management, "Explicit extension trust policy"), and a descriptor's claims are the only authenticated statement of what a guest does. A provider published only as a NuGet package, with no version-2 descriptor, therefore cannot be bound by a recipe or recorded in a lock in `0.1.0-draft.1`.
- **Offerings publish a `compatibility.morphirCli` that no version matches.** Version 1 requires every release descriptor to state the Morphir CLI versions that may acquire it, and its resolver filters by the acquiring CLI's version. The Morphir CLI must never select a .NET host offering, because there is no second installer. An offering descriptor therefore publishes `<0.0.0-0`, which no version satisfies: `>=0.0.0` would start matching at the first final CLI release. A manager never evaluates the member: it resolves the recipe, then checks each host binding against the authenticated release and its targets as above. The signed fixtures publish `<0.0.0-0`, and their `v1Client` cases show the version 1 client selecting no offering.
- **One repository per binding check**, as stated [above](#one-repository-per-binding-check).

## Questions for the maintainer

These are open. Rules that depend on them are marked provisional where they appear.

- **M2: what is installed from a multi-file process artifact?** A recipe binds one archive per platform, and the self-contained F# frontend archive is a folder of about 240 files, while the shared extension store, catalog, lock and activation hold one file per extension. **Recommended default:** for first delivery, a single-file self-extracting frontend at the archive's root, so the store holds one executable, and the recipe and lock bind the archive digest. A package form for multi-file guests would be a separate, reviewed descriptor change. The rule that a process provider's `artifactTarget` is one archive per platform is **provisional** until M2 is answered.

## Fixtures

`fixtures/0.1.0-draft.1/recipe/fsharp-synthetic.json` describes the four .NET offerings on the six first-delivery platforms, the F# frontend as a process guest and as the existing framework-dependent .NET tool, and the standalone F# backend process guest. Every offering keeps the built-in `morphir.fsharp` generator, and the three managed offerings have the built-in frontend `morphir-dotnet.fsharp`; its `resolve` case for `self-contained` selects both built-ins. It is unsigned and binds nothing, so it keeps the dotted frontend identity of the approved example. `wasm-abi-alternatives.json` offers a backend for two WASM ABIs to a host that supports only `morphir-bytes-v1`; its `resolve` cases show that resolution reports `abi_unavailable` unless the request chooses the other ABI. `critical-nested-platform-member.json` names a platform member as critical. `provider-misfit.json` has a frontend that fits its host on one of the host's two platforms. `recipe/negative/` has the fixtures in the consistency table plus a later draft, an unknown critical member and an unknown nested critical member, a WASM provider without an ABI, an uppercase identity, an identity token over 64 characters, an unknown source kind, a `dotnet-tool` provider without its descriptor, a `compile` built-in with `modelInput` and one without `modelOutput`, credential members (`apiKey`, and `APIKEY` to pin case-insensitive matching), and two documents that break two rules at once (`precedence-*.json`).

The TEST-ONLY signed repository in `fixtures/0.1.0-draft.1/signed/repository.json` publishes:

- the three archive offerings as version 1 tool releases on the six first-delivery platforms, and the `Morphir.Tool` package;
- the F# frontend `morphir-fsharp-frontend` 0.6.0 and the standalone backend `morphir-fsharp-backend` 0.1.0 as version-2 extension releases, with the frontend's .NET tool package;
- a portable WASM frontend for `morphir-bytes-v1`, two MEP `0.1` frontends whose claims list IR `3` and IR `4`, and releases whose claims or descriptors are each wrong in one way;
- the `fsharp-builtin` and `fsharp` recipes, six `channel-example` recipes on different channels and statuses, and a validly signed recipe for each refusal in the tables above.

`signed/cases.json` lists the recipes in `recipeChecks`, together with the trust cases, channel selection, version 1 client selections, frozen locks and lock-against-recipe cases described in the [overview](./index.md#fixtures-and-conformance). Four frozen requests and their locks record complete closures on all six first-delivery platforms:

| Files | Selection |
| --- | --- |
| `fsharp-self-contained.toml`, `.lock.json` | Self-contained host, its built-in frontend `morphir-dotnet.fsharp` and built-in `morphir.fsharp` backend; nothing is downloaded besides the host |
| `fsharp-native-aot.toml`, `.lock.json` | Native AOT host, process frontend, built-in `morphir.fsharp` backend |
| `fsharp-native-aot-external-backend.toml`, `.lock.json` | The same host and frontend, explicit external backend process guest |
| `fsharp-framework-dependent-tool-frontend.toml`, `.lock.json` | Framework-dependent host, explicit .NET tool frontend, built-in backend |

Every key in that repository is derived from a public label recorded in `testOnlyKeys`, so anyone can sign with it. Never trust that repository, its keys or its `repositoryId` outside tests.
