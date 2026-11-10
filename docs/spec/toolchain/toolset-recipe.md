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
| `protocolVersions` | MEP versions the host speaks, each on the [supported 0.2 line](./index.md#mep-versions) and each once. A version off the line is `unsupported_case` at that element, and a string that is not SemVer `invalid_value` |
| `wasmAbis` | WASM ABIs the host's qualified engine supports, each once. Optional; absent or empty when it has none |
| `prerequisites` | Runtime, SDK and native prerequisites. Optional; absent means none |
| `builtIns` | Built-in providers, at most one per operation: `operation`, `extensionId`, `version`, and the model the built-in exchanges with the host. That is `modelOutput` for a `compile` built-in, which writes the model, and `modelInput` for a `generate` built-in, which reads it; the other member is `inconsistent_document`. Optional; absent means none |
| `platforms` | The authenticated artifact (`target`, `sha256`) for each supported platform |

For the `fsharp` preset, every .NET offering has the built-in generator `morphir.fsharp`. The three managed offerings (`self-contained`, `framework-dependent` and `dotnet-tool`) also have the in-process F# frontend `morphir-dotnet.fsharp` as a `compile` built-in, so resolution selects it by default, as morphir-dotnet's `cli-model-compilation` specification requires. The Native AOT offering excludes the compiler services and has no frontend built-in, so it resolves the recipe's process frontend.

A `tool-release` source names a tool release metadata v1 tool id. Each separately published offering has its own tool id, so implementation and deployment are never inferred from an executable name. A v1 platform states no C library, so a `tool-release` offering lists no `linux-musl-*` platform. A `dotnet-tool` source binds the package bytes per platform like any other host artifact.

### Providers

Each provider has `operation`, `delivery` (`process`, `wasm` or `dotnet-tool`; built-ins belong to a host, so a provider with `delivery` `built-in` names a known case in the wrong place and is `inconsistent_document` at its `delivery`, `recipe/negative/provider-built-in-delivery.json`), `extensionId`, `version`, optional `prerequisites`, and the protocol members described for the [lock](./toolchain-lock.md#members). Delivery identities:

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

The first five rules marked *while reading* concern one object and are checked as that object is read, in [reading order](./index.md#order-of-checks). The others are checked once the whole document has been read, in the order of this table; each of them is checked over its whole array, in index order, before the next rule is checked. So a recipe whose second host repeats the first offering and whose first host has a second built-in is refused at `hosts[1]` (`precedence-consistency-table-order.json`).

| Rule | Checked | Path | Fixture |
| --- | --- | --- | --- |
| A `tool-release` offering lists no musl platform | while reading | `hosts[i].platforms.<id>` | `musl-bound-to-tool-release.json` |
| An offering lists each MEP version and each WASM ABI once; a repeated entry is refused at the repetition | while reading | `hosts[i].protocolVersions[j]`, `hosts[i].wasmAbis[j]` | `duplicate-protocol-version.json`, `duplicate-wasm-abi.json` |
| A process provider lists at least one platform | while reading | `providers[i].platforms` | `process-without-platforms.json` |
| A `modelTuple` operation performs the provider's operation | while reading | `providers[i].modelTuple.operation` | `tuple-operation-mismatch.json` |
| A provider has only its delivery's members: an external provider declares no `modelInput` or `modelOutput`, which only a built-in has, and a built-in declares no `protocolVersion` or `modelTuple`, because it has no MEP session | while reading | `providers[i].modelInput`, `providers[i].modelOutput`, `hosts[i].builtIns[j].protocolVersion`, `hosts[i].builtIns[j].modelTuple` | `external-provider-with-model-input.json`, `external-provider-with-model-output.json`, `built-in-with-model-tuple.json` |
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

A recipe is published as a TUF target at `toolchains/recipes/<preset>/<version>.json` in a repository that follows [tool release metadata v1](../tool-release-metadata/index.md#offering-specific-tool-ids).

The manager's TUF client is decided (9 November 2026, [finos/morphir#1146](https://github.com/finos/morphir/issues/1146#issuecomment-6760090078)). It is project-owned, in `Morphir.Toolchain` in finos/morphir-dotnet, implements only the subset of TUF that the tool release metadata profile uses, and has BouncyCastle's Ed25519 as its only cryptographic dependency. It is tested against the signed fixtures in this repository, the cases of the evaluation in finos/morphir-dotnet#568 and the upstream `tuf-conformance` suite, and it needs the maintainer's security review before any production use. This repository's reference checker uses tough 0.24 instead; the cases do not depend on which client runs them.

### Metadata rules for toolchain readers

A reader under these contracts, a manager or this repository's checker, loads a repository by the tool release metadata v1 rules, including its [signed text](../tool-release-metadata/index.md#signed-text) rules for NFC text and target paths. It then applies two more rules to the text of every role's `signed` object, as served, in every repository it loads, and refuses each with `metadata_signature_invalid`. These rules belong to these contracts, not to version 1 (maintainer decision of 10 November 2026, [Decision 12](https://github.com/finos/morphir/issues/1146#issuecomment-6772788150)), so a version 1 client outside them may accept such metadata:

- **A case variant of a defined member.** A member whose name differs only in ASCII letter case from a member that TUF 1.0 or the profile defines for that object, such as `Version` beside `version`, or `Length` in a target entry. A case-sensitive reader ignores it as an unknown member, as TUF says, but a reader that binds JSON names without case reads it instead of the real member. Other unknown members are still ignored.
- **An integer past 2<sup>53</sup> − 1**, the [integer bound](./index.md#numbers) of these documents, so that every reader language holds a metadata integer exactly. Versions, thresholds and lengths are all integers.

The defined members are those of TUF 1.0 for each role, key, role entry, meta entry, hashes object and target entry, and for `custom.morphir`. For `custom.morphir` they are `schemaVersion`, `kind`, `toolId`, `version`, `channels`, `status`, `compatibility` (`morphirCli`), `platforms` and `platform` (`os`, `arch`), and `preset`.

The signed set `caseVariantMember` pins the first rule. Trust cases at a timestamp version of 2<sup>53</sup> − 1, which loads, and 2<sup>53</sup>, which is refused, pin the second.

The recipe's `custom.morphir` object is:

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
| A `tool-release` offering's descriptor `releases/<toolId>/<version>.json` is an authenticated `tool-release` target for that tool and version, whose state has a known `status` (`active`, `yanked` or `revoked`) | `target_not_authenticated` | `hosts[i].source` | `host-release-authenticated` |
| That release's current status is not `revoked` | `release_revoked` | `hosts[i].version` | `host-release-revoked` |
| The descriptor's authenticated length is at most 1 MiB (1,048,576 bytes), the profile's descriptor bound, checked before any byte is read | `release_descriptor_mismatch` | `hosts[i].source` | No fixture: a descriptor over 1 MiB would add more than 1 MiB to the committed signed repository |
| The descriptor bytes have the authenticated length and digest | `target_length_mismatch`, `target_digest_mismatch` | `hosts[i].source` | `host-release-read` |
| The descriptor reads as a version 1 tool release, and its `compatibility.morphirCli` is in the binding check's [CLI requirement grammar](#cli-requirement-grammar) | `release_descriptor_mismatch` | `hosts[i].source` | `host-release-v1` |
| The descriptor's own `tool.id` and `version` are the offering's tool id and version. The profile calls a descriptor that differs from its authenticated state in those immutable values a `release_descriptor_mismatch` | `release_descriptor_mismatch` | `hosts[i].source` | `host-release-identity` |
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
| The descriptor's authenticated length is at most 1 MiB (1,048,576 bytes), checked before any byte is read | `release_descriptor_mismatch` | `providers[i].descriptorTarget` | No fixture: a descriptor over 1 MiB would add more than 1 MiB to the committed signed repository |
| The descriptor bytes have the authenticated length and digest | `target_length_mismatch`, `target_digest_mismatch` | `providers[i].descriptorTarget` | `provider-descriptor-read` |
| The descriptor reads as an extension release descriptor at `schemaVersion` `2.0.0-draft.2`, and each artifact's claim set at `claimsVersion` `0.1.0-draft.2`. An earlier or later draft is refused, never converted | `release_descriptor_mismatch` | `providers[i].descriptorTarget` | `provider-descriptor-parses` |
| Every path in the descriptor's `critical`, then in each artifact's, then in that artifact's claim set's, is one a binding check [understands](#what-a-binding-check-reads) | `release_descriptor_mismatch` | `providers[i].descriptorTarget` | `provider-descriptor-critical` |
| The descriptor lists each `filename` once: a bundle directory holds one file per name | `release_descriptor_mismatch` | `providers[i].descriptorTarget` | `provider-descriptor-filenames` |
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
| `capabilities.modelTransport.tuples` contains the provider's `modelTuple` exactly | `release_descriptor_mismatch` | `providers[i].modelTuple` | `provider-claims-model` |

A process provider's platforms are checked in platform table order, and for each platform the artifact rows and then the claim rows apply in the order above, all of them before the next platform: each platform's artifact carries its own claim set. So a `win-x64` artifact whose claims lack the language is refused at `providers[i].language` before an `osx-x64` artifact with a wrong digest is checked (`negative-claims-per-platform`). A `wasm` provider has one artifact, at `providers[i].artifactTarget` and `providers[i].artifactSha256`. A `dotnet-tool` provider's package is checked by the bound-member row, and its capability rows are checked against every artifact's claims in its descriptor.

Authentication alone is never enough: for each refusal in these three tables the signed fixtures publish a validly signed recipe, or declare a trust case, that is refused for exactly that reason. The coverage test in this repository fails when a row names no case and is not marked as having none.

### What a binding check reads

The binding rows read three documents that other contracts define, each only at the version in the [table of referenced contracts](./index.md#version-authorities). The version 1 descriptor has a published schema and profile, both pinned with these contracts. The version-2 descriptor and the claim set are defined by design drafts, which these contracts do not pin. A binding check relies on exactly these members and on nothing else in those documents:

| Document | Members a binding check reads |
| --- | --- |
| Tool release descriptor, `schemaVersion` `1` | `tool.id`, `version`, `compatibility.morphirCli` (its grammar only; a manager never evaluates it), and each artifact's `targetPath` and `platform`. The rest is read only as far as the version 1 schema requires |
| Extension release descriptor, `2.0.0-draft.2` | `schemaVersion`, `extensionId`, `version`, `critical`, and in each artifact `runtime`, `platform`, `filename`, `sha256`, `claims` and `critical` |
| Capability claim set, `0.1.0-draft.2` | `claimsVersion`, `protocolVersions`, `extension.id`, `extension.version`, `extension.types`, `critical`, and in `capabilities`: `frontend.compile`, `frontend.languages[].id`, `backend.generate`, `backend.targets` and `modelTransport.tuples` |

**Critical paths.** The extension documents follow the same rule as these contracts: a reader refuses a `critical` path it does not understand. A binding check understands a path only when it names a member that the check reads, written as the `critical` list that holds it writes it:

- in the descriptor's `critical`: `schemaVersion`, `extensionId`, `version`, `artifacts`, `artifacts.runtime`, `artifacts.platform`, `artifacts.filename`, `artifacts.sha256`, `artifacts.claims`;
- in an artifact's `critical`: `runtime`, `platform`, `filename`, `sha256`, `claims`;
- in a claim set's `critical`: `claimsVersion`, `protocolVersions`, `extension`, `extension.id`, `extension.version`, `extension.types`, `capabilities.frontend.compile`, `capabilities.frontend.languages`, `capabilities.frontend.languages.id`, `capabilities.backend.generate`, `capabilities.backend.targets`, `capabilities.modelTransport.tuples`.

Any other path is refused by the `provider-descriptor-critical` row, even one a host understands, such as `capabilities.frontend.incremental` (`negative-claims-critical-unread`). A binding check does not use a member it does not read, so it cannot honour a critical one.

**`requires.host`** is a claim set member that the extension contract requires to be listed in `critical`. No binding row evaluates it, so the critical rule refuses it. Whether a binding check should instead evaluate it against the recipe's host offerings is [open question Q4](./index.md#open-questions).

**What the claim set's own validity leaves alone.** A binding check adds no rule to the claim set's lists. An empty `protocolVersions` lists no MEP version, so it fails the `provider-claims-protocol` row at `providers[i].protocolVersion` (`negative-claims-no-protocol`), not the reading. A repeated `protocolVersions` entry or capability kind changes no binding outcome, and a binding check does not refuse it. Whether those lists may repeat is the claim set contract's rule.

**`claimCheck`** is not read. The receipt records the installed record's `claimCheck`, which the install-time probe decides ([claim checks and publisher authentication](#claim-checks-and-publisher-authentication)). A descriptor without one is not refused.

**Descriptor consistency on an exact request.** Tool release metadata v1 says an exact request still enforces "immutable descriptor consistency". For a recipe's host offering, that is the host rows above: a manager never runs version 1 resolution for an offering, and the `host-release-identity` row and the artifact rows compare the descriptor with the authenticated state. A resolver run under these contracts, as for the `v1Client` cases, reads only `custom.morphir`, and these rows compare the descriptor when it is read. This states where these contracts check consistency; it does not change the version 1 profile.

The member table and schema of the version-2 descriptor and of the claim set as wholes belong to the extension contracts, not to these pages.

### CLI requirement grammar

A binding check, and a resolver run under these contracts, accepts a `compatibility.morphirCli` only in this grammar. This rule belongs to these contracts. It is **stricter than tool release metadata v1**, which gives the member one example and no grammar, and whose schema requires only a non-blank string. Whether the profile itself should adopt the grammar is [open question Q5](./index.md#open-questions); until it is answered, a version 1 client outside these contracts may accept more.

- The requirement is one or more single comparators, separated by a comma and exactly one space, such as `>=0.4.0-alpha.5, <0.5.0`.
- A comparator is the same as one in a prerequisite's `versions` ([versions](./index.md#versions)): one of `=`, `>`, `>=`, `<` or `<=`, then a complete version in canonical SemVer spelling, with no space between them, within the bound on a version.
- There is no other form. `^0.4.0`, `~0.4.0`, `*`, a partial version such as `>=0.4`, a bare version, `||`, a space-separated list and a comma without its space are refused. The Rust `semver` crate, `@std/semver` and npm `semver` read several of those forms differently.
- A CLI version meets the requirement when it satisfies every comparator by SemVer precedence and, if it is a prerelease, at least one comparator names a prerelease of the same major, minor and patch version: the npm `semver` and Rust `semver` crate rule, and the rule for [prerequisite versions](./index.md#tagged-cases). So `0.4.0-beta.12` meets `>=0.4.0-0, <0.5.0`, `0.5.0-alpha.1` does not, although it is below `0.5.0`, and no version meets `<0.0.0-0`.

A host descriptor whose requirement is outside the grammar is refused by the `host-release-v1` row (`negative-host-release-cli-range`, with `^0.4.0`). A manager never evaluates an offering's requirement; it checks only the grammar. A resolver under these contracts evaluates the `custom.morphir` requirement with the same grammar and rule, and refuses a record outside the grammar with `release_descriptor_mismatch`. The `cli-requirement` binding cases pin the grammar and the rule. Every requirement in the signed repository is in the grammar except that deliberate negative, so no `v1Client` case depends on which reading a resolver applies.

### What revocation reaches

Version 1 release status exists only for `tool-release` targets, so a learned revocation reaches a `tool-release` host offering directly. A `dotnet-tool` host and every provider have no version 1 release status: revocation reaches them only through the recipe target that binds them, by revoking that recipe and publishing a corrected one.

### Claim checks and publisher authentication

These are separate facts and stay separate. A recipe digest authenticates an extension's bytes: it says the repository's publisher bound exactly these bytes to this toolset. It says nothing about whether anyone ran the artifact to compare its capability claims. A descriptor written by bundle authoring keeps `claimCheck: unchecked`, and a recipe never changes that. The install-time probe, or `--no-probe`, decides the installed record's `claimCheck`, and the [receipt](./installation-receipt.md#installation) records it beside `authentication`. A probed artifact is not thereby authenticated. No recipe can bind an unsigned developer artifact, because it is not an authenticated target, so no lock names it and it is never part of a toolchain generation; a receipt that labels a provider `local-developer` is refused ([receipt](./installation-receipt.md#installation)). Bytes that equal a locked digest were authenticated by that digest, whoever built them, and are labelled `recipe-digest`.

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
| The preferred provider needs a WASM ABI the host lacks, checked before any other misfit of the same provider | `abi_unavailable` | `toolset` | `resolve-preferred-abi` |
| The preferred provider does not fit for another reason | `unsupported_artifact` | `toolset` | `resolve-preferred-misfit` |
| No built-in or provider performs the operation | `unsupported_artifact` | `toolset` | No fixture: a recipe that passes its consistency rules has a built-in or a provider for every operation, so a reader refuses such a recipe before resolution can reach this row |
| No built-in or provider matches an explicit choice | `unsupported_artifact` | `toolset.providers[i]` | `resolve-choice-unmatched` |
| The chosen provider needs a WASM ABI the host lacks | `abi_unavailable` | `toolset.providers[i]` | `resolve-choice-abi` |
| The chosen provider does not fit for another reason | `unsupported_artifact` | `toolset.providers[i]` | `resolve-choice-misfit` |
| A choice names an operation the recipe does not require, checked after every required operation has resolved | `unsupported_artifact` | `toolset.providers[i]` | `resolve-choice-unrequired` |

A provider can misfit in more than one way. A missing WASM ABI is reported first, as `abi_unavailable`, because it is the misfit a request can fix by choosing the provider for another ABI. The other misfits are then checked in this order: the MEP version, then the platform (`recipe/wasm-abi-and-protocol-misfit.json` has a preferred provider whose ABI and protocol version both misfit, and is refused for its ABI).

A WASM guest for another ABI is therefore chosen only when the request names that ABI. Otherwise setup reports the missing ABI and does not report ready. Plan-only setup may refresh metadata, but it never runs an acquired artifact. Readiness probes happen after staging, under the existing launch controls.

## Limits of this contract version

- **Dotted provider identities are decided; the descriptor change is pending.** Release descriptors will allow dotted extension ids, with the descriptor id equal to the claims id, through the separately reviewed change finos/morphir#1149. The external F# guests are `org.finos.morphir.fsharp-frontend` and `org.finos.morphir.fsharp-backend`. Until #1149 lands, a version-2 descriptor accepts only a single token, so the TEST-ONLY signed fixtures bind `morphir-fsharp-frontend` and `morphir-fsharp-backend`. They move to the dotted ids in #1149's toolchain task, together with the provider identity grammar (see [identifiers](./index.md#identifiers)). Built-in identities such as `morphir.fsharp` and `morphir-dotnet.fsharp` are unaffected, because a built-in has no descriptor.
- **A provider must publish a version-2 descriptor.** Public toolset recipes bind extension artifacts and descriptors (approved toolchain management, "Explicit extension trust policy"), and a descriptor's claims are the only authenticated statement of what a guest does. A provider published only as a NuGet package, with no version-2 descriptor, therefore cannot be bound by a recipe or recorded in a lock in `0.1.0-draft.1`.
- **Offerings publish a `compatibility.morphirCli` that no version matches.** Version 1 requires every release descriptor to state the Morphir CLI versions that may acquire it, and its resolver filters by the acquiring CLI's version. The Morphir CLI must never select a .NET host offering, because there is no second installer. An offering descriptor therefore publishes `<0.0.0-0`, which no version satisfies: `>=0.0.0` would start matching at the first final CLI release. A manager never evaluates the member, and checks only that it is in the [CLI requirement grammar](#cli-requirement-grammar): it resolves the recipe, then checks each host binding against the authenticated release and its targets as above. The signed fixtures publish `<0.0.0-0`, and their `v1Client` cases show the version 1 client selecting no offering, while selecting a control release whose requirement admits the CLI.
- **One repository per binding check**, as stated [above](#one-repository-per-binding-check).
- **A multi-file extension is a package form that a separate change defines.** The self-contained F# frontend is a .NET program of 239 files, because the F# compiler inside it needs its reference assemblies as files on disk, while the shared extension store, records and activation assume one file per extension. The maintainer decided (9 November 2026, [finos/morphir#1146](https://github.com/finos/morphir/issues/1146#issuecomment-6760228228)) that the shared extension contract is extended so an extension can be a multi-file package, and that no self-unpacking single-file form of the frontend is built. That package form is a separately reviewed OpenSpec change in this repository, written for the .NET and MoonBit hosts first. Only the Native AOT offering needs an installed F# frontend, so the recipe's binding of the Native AOT offering's process frontend, one archive per platform in `artifactTarget`, is **provisional** on that change.

The maintainer decisions these pages follow are listed with their dates under [Decided](./index.md#decided).

## Fixtures

`fixtures/0.1.0-draft.1/recipe/fsharp-synthetic.json` describes the four .NET offerings on the six first-delivery platforms, the F# frontend as a process guest and as the existing framework-dependent .NET tool, and the standalone F# backend process guest. Every offering keeps the built-in `morphir.fsharp` generator, and the three managed offerings have the built-in frontend `morphir-dotnet.fsharp`; its `resolve` case for `self-contained` selects both built-ins. It is unsigned and binds nothing, so it keeps the dotted frontend identity of the approved example. `wasm-abi-alternatives.json` offers a backend for two WASM ABIs to a host that supports only `morphir-bytes-v1`; its `resolve` cases show that resolution reports `abi_unavailable` unless the request chooses the other ABI. `critical-nested-platform-member.json` names a platform member as critical. `protocol-membership-exact.json` has a preferred provider at MEP `0.2.0` for hosts that list only `0.2.0-draft.1`, and `wasm-abi-and-protocol-misfit.json` a WASM provider that misfits by both ABI and protocol; their `resolve` cases pin exact membership and the order of misfits. `provider-misfit.json` has a frontend that fits its host on one of the host's two platforms. `recipe/negative/` has the fixtures in the consistency table plus a later draft, an unknown critical member and an unknown nested critical member, a WASM provider without an ABI, an uppercase identity, an identity token over 64 characters, an unknown source kind, a `dotnet-tool` provider without its descriptor, a `compile` built-in with `modelInput` and one without `modelOutput`, a provider speaking MEP `0.1` (`protocol-version-0.1.json`, `unsupported_case`), credential members (`apiKey`, and `APIKEY` to pin case-insensitive matching), and two documents that break two rules at once (`precedence-*.json`).

The TEST-ONLY signed repository in `fixtures/0.1.0-draft.1/signed/repository.json` publishes:

- the three archive offerings as version 1 tool releases on the six first-delivery platforms, and the `Morphir.Tool` package;
- host releases that are each wrong in one way for the host rows: an unknown status, a descriptor for another tool or another version, and a caret `compatibility.morphirCli`; and `morphir-v1-control`, a release that is not an offering and that the version 1 client selects;
- the F# frontend `morphir-fsharp-frontend` 0.6.0 and the standalone backend `morphir-fsharp-backend` 0.1.0 as version-2 extension releases, with the frontend's .NET tool package;
- a portable WASM frontend for `morphir-bytes-v1`, and releases whose claims or descriptors are each wrong in one way, among them a frontend whose claims list MEP `0.2.0` while the recipe binds `0.2.0-draft.1`, one with no MEP version, descriptors at the first and at a later draft, a claim set with a critical member no binding row reads, a descriptor that lists one filename twice, and a two-platform release whose first platform's claims lack the language;
- the `fsharp-builtin` and `fsharp` recipes, six `channel-example` recipes on different channels and statuses, and a validly signed recipe for each refusal in the tables above.

`signed/cases.json` lists the recipes in `recipeChecks`, together with the trust cases, channel selection, version 1 client selections, frozen locks and lock-against-recipe cases described in the [overview](./index.md#fixtures-and-conformance). Four frozen requests and their locks record complete closures on all six first-delivery platforms:

| Files | Selection |
| --- | --- |
| `fsharp-self-contained.toml`, `.lock.json` | Self-contained host, its built-in frontend `morphir-dotnet.fsharp` and built-in `morphir.fsharp` backend; nothing is downloaded besides the host |
| `fsharp-native-aot.toml`, `.lock.json` | Native AOT host, process frontend, built-in `morphir.fsharp` backend |
| `fsharp-native-aot-external-backend.toml`, `.lock.json` | The same host and frontend, explicit external backend process guest |
| `fsharp-framework-dependent-tool-frontend.toml`, `.lock.json` | Framework-dependent host, explicit .NET tool frontend, built-in backend |

Every key in that repository is derived from a public label recorded in `testOnlyKeys`, so anyone can sign with it. Never trust that repository, its keys or its `repositoryId` outside tests.
