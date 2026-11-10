---
title: Toolchain acquisition contracts
sidebar_label: Overview
status: draft
---

# Toolchain acquisition contracts

`morphirup` installs a Morphir host and language toolsets from authenticated metadata. This section defines the five runtime-neutral documents it reads and writes. The .NET manager and any later MoonBit or Rust manager implement them; none of them is a Morphir CLI command today.

These contracts implement the approved OpenSpec change `add-deployment-and-acquisition` (decisions DEP-1, UP-1, UP-2, FS-1, LOCK-1, PATH-1 and QUAL-1). The commands named on these pages are that change's proposed interface.

## The five documents

| Document | Location | Written by | Read by | Contract |
| --- | --- | --- | --- | --- |
| [Toolset recipe](./toolset-recipe.md) | Authenticated TUF target, for example `toolchains/recipes/fsharp/1.0.0.json` | Release assembly | Manager resolution | [schema](/schemas/toolset-recipe-0.1.0-draft.1.schema.json) |
| [Project toolchain request](./toolchain-request.md) | `.morphir/toolchain.toml`, checked in | The user | Manager setup, restore and selection | [schema](/schemas/toolchain-request-0.1.0-draft.1.schema.json) |
| [Portable lock](./toolchain-lock.md) | `.morphir/toolchain.lock.json`, checked in | Explicit setup or update | Frozen and offline restore | [schema](/schemas/toolchain-lock-0.1.0-draft.1.schema.json) |
| [Installation receipt](./installation-receipt.md) | `MORPHIR_HOME/toolchains/generations/<id>/` | The manager, for one installed generation | Activation, `run`, `show`, `doctor`, repair and rollback | [schema](/schemas/toolchain-receipt-0.1.0-draft.1.schema.json) |
| [Manager result](./manager-result.md) | Standard output of `morphirup --json` | The manager | Automation | [schema](/schemas/morphirup-result-0.1.0-draft.1.schema.json) |

The request is what a project asks for. The lock is the exact answer, portable across machines. The receipt is what one machine installed from that answer. Keeping the three apart lets a colleague on another platform restore the same lock without inheriting anyone's local paths.

## Version authorities

Each document starts at `0.1.0-draft.1`, and each page above is the authority for its own version. Changing one document's version does not change another's.

The contracts these documents refer to keep their own versions. Nothing here renames them in place:

| Referenced contract | Version | Authority |
| --- | --- | --- |
| Tool release descriptor and TUF profile | `schemaVersion: 1` | [Tool release metadata v1](../tool-release-metadata/index.md) |
| Extension release descriptor | `2.0.0-draft.2` | [Extension distribution](../../design/draft/extensions/distribution-and-acquisition.md) |
| Capability claim set | `claimsVersion` `0.1.0-draft.2` | [Extension protocol](../../design/draft/extensions/protocol.md#capability-claims) |
| MEP | `0.1` and `0.2.0-draft.1` | [Extension protocol](../../design/draft/extensions/protocol.md) and [model transport](https://github.com/finos/morphir/blob/main/spec/mep/model-transport.md) |
| Model envelope | `0.1.0-draft.1` | [Model transport](https://github.com/finos/morphir/blob/main/spec/mep/model-transport.md) |
| Morphir IR | `formatVersion` | [IR format version](../ir/format-version.md) |

## Rules shared by all five

### Versions

`schemaVersion` is a SemVer string. A reader lists the versions it supports as SemVer requirements and refuses anything else before it reads another member. A `0.1.0-draft.1` reader lists exactly `=0.1.0-draft.1`, so it refuses `0.1.0-draft.2` and the released `0.1.0` with `unsupported_contract_version`. A string that is not SemVer, such as `0.1`, is `invalid_value`. Drafts promise no compatibility with each other. Use a SemVer library, never a hand-written version type.

### Unknown and critical members

A reader ignores any member it does not understand, at any depth. `critical` is an optional array of unique member paths. A path is a dotted list of member names from the document root. Array elements are named through the array's member name, without an index: `toolset.providers.delivery` names `delivery` in every element of `toolset.providers`. Entries of a map whose keys are data are named by `*`: `platforms.*.providers.modelTuple` names `modelTuple` in every provider of every platform closure.

A reader refuses a critical path it does not understand with `unsupported_critical_member` and names the path. A critical path that names an understood member is accepted. Each page lists the paths a `0.1.0-draft.1` reader understands, and each schema enumerates exactly those under `critical`.

### Tagged cases

Members that select a case are closed sets: `delivery`, `operation`, prerequisite, source, ownership and authentication `kind`, readiness, check, status, command, outcome and diagnostic `kind`. A reader refuses a case it does not know with `unsupported_case`. There is no default case: an unknown tag never stands for a known one.

The provider delivery cases are:

| `delivery` | Meaning | Identities it requires |
| --- | --- | --- |
| `built-in` | Compiled into the host | `modelInput` only; no artifact |
| `process` | A native process speaking Content-Length framed MEP | Descriptor and per-platform artifact digests |
| `wasm` | A portable module for one named ABI | `abi`, descriptor and artifact digests |
| `dotnet-tool` | A .NET tool package installed into an isolated tool path | `packageId`, `command`, package digest, and the release's descriptor digest |

The public runtime name for WASM stays `wasm`. The ABI, such as `morphir-bytes-v1` or `extism-kernel-v1`, is a separate member, and a host that supports one ABI never accepts a guest for another.

Prerequisites are `runtime`, `sdk` (with `phase` `install` or `run`) and `native` (optionally limited to `platforms`). Versions are lists of single SemVer comparators, `[">=10.0.0", "<11.0.0"]`, because Rust and TypeScript separate combined ranges differently. A native library's version is written as SemVer with missing parts as zero: glibc 2.28 is `2.28.0`, so the comparator is `>=2.28.0`.

### Identifiers

| Value | Rule |
| --- | --- |
| Implementation, deployment, preset, language, target, ABI, generation id, workflow, package manager, command | A lowercase portable token: `[a-z]`, then `[a-z0-9-]`, ending in a letter or digit, at most 64 characters |
| Provider identity (`extensionId`) | Portable tokens joined by `.`, at most 238 characters: `morphir.fsharp`, `morphir-fsharp-backend` |
| NuGet package id | Segments of `[A-Za-z0-9_]` joined by `.` or `-`, at most 100 characters |
| Tool id | The tool release metadata v1 tool id grammar |
| Digest | 64 lowercase hexadecimal digits of SHA-256 over exact bytes |
| Version | Canonical SemVer |

### Target paths

A target path names an authenticated TUF target. It is relative, uses `/` as its separator, has at most 512 UTF-8 bytes and at most 240 UTF-16 code units, and has no NUL, control character (U+0000 to U+001F), U+2028 or U+2029. Each `/`-separated component:

- is not empty, `.` or `..`;
- does not end in `.` or a space;
- contains none of `\ < > : " | ? *`;
- is at most 255 UTF-8 bytes and 255 UTF-16 code units;
- is not a Windows device name. A component is a device name when the part before its first `.`, with trailing spaces removed and compared ASCII case-insensitively, is `CON`, `PRN`, `AUX`, `NUL`, `CONIN$`, `CONOUT$`, or `COM` or `LPT` followed by one of `1` to `9`, `¹`, `²` or `³`. So `artifacts/CON/win-x64.zip` and `con.tar.gz` are refused.

A path that breaks any of these rules is `non_portable_path`. These are the rules the existing tool and extension stores apply to every stored path, so a target that passes can be stored on every first-delivery platform.

### Local paths

Only receipts and `show` results hold local paths. A local path is absolute: a drive letter, `:`, `\` or `/` and at least one more character (`C:\Users\fixture\morphir.exe`), a UNC path `\\` followed by at least one more character, or `/` followed by at least one more character. A receipt uses its platform's syntax; a result's project path may use either. No `\`- or `/`-separated segment is `.` or `..`, and the path has no NUL. Anything else is `invalid_value`.

### Platforms

Platform identifiers use .NET runtime identifier spelling, which states the C library on Linux:

| Platform | Tool release v1 platform | Extension descriptor target triple |
| --- | --- | --- |
| `win-x64` | `windows` / `x86_64` | `x86_64-pc-windows-msvc` |
| `win-arm64` | `windows` / `aarch64` | `aarch64-pc-windows-msvc` |
| `osx-x64` | `macos` / `x86_64` | `x86_64-apple-darwin` |
| `osx-arm64` | `macos` / `aarch64` | `aarch64-apple-darwin` |
| `linux-x64` | `linux` / `x86_64` | `x86_64-unknown-linux-gnu` |
| `linux-arm64` | `linux` / `aarch64` | `aarch64-unknown-linux-gnu` |
| `linux-musl-x64` | none | `x86_64-unknown-linux-musl` |
| `linux-musl-arm64` | none | `aarch64-unknown-linux-musl` |

The first six are the first-delivery platforms. The two musl identifiers exist so a musl machine can name itself and be told that no matching artifact exists. Tool release metadata v1 platforms do not state a C library, so a recipe binds a v1 Linux artifact only to a glibc platform.

### Credentials

No document carries a credential. Every reader refuses, at any depth and including inside members it otherwise ignores, a member whose name equals one of `password`, `passwd`, `secret`, `token`, `apiKey`, `api-key`, `api_key`, `authorization`, `credential`, `credentials` or `cookie`, compared ASCII case-insensitively, with `credential_in_document`. A reported mirror URL has no user information, query or fragment.

## Stable codes

Readers and checks report one code and the member path it concerns. Paths use dotted member names with `[index]` for array elements, for example `platforms.win-x64.providers[0].artifactTarget`. The empty path means the document itself, or, for an authenticated-target check, the target itself.

Every code has exactly one result diagnostic kind, so a [manager result](./manager-result.md#diagnostics) can report any refusal:

| Code | Result diagnostic kind | Meaning |
| --- | --- | --- |
| `invalid_document` | `unsupported-contract` | Not the document's syntax, a required member is absent, or a member has the wrong JSON type |
| `unsupported_contract_version` | `unsupported-contract` | `schemaVersion` is not a listed version |
| `unsupported_critical_member` | `unsupported-contract` | `critical` names a path the reader does not understand |
| `unsupported_case` | `unsupported-contract` | A tagged member has an unknown case |
| `invalid_value` | `unsupported-contract` | A scalar fails its validated type |
| `non_portable_path` | `unsupported-contract` | A target path breaks the target path rules |
| `credential_in_document` | `unsupported-contract` | A credential member or a URL carrying credentials |
| `inconsistent_document` | `unsupported-contract` | Valid members that contradict each other |
| `request_changed` | `lock-binding` | A lock's `requestSha256` differs from the SHA-256 of the request bytes |
| `platform_not_locked` | `lock-binding` | Frozen restore needs a platform closure the lock does not record |
| `lock_changed` | `lock-binding` | A receipt's `lockSha256` differs from the SHA-256 of the lock bytes |
| `receipt_lock_mismatch` | `lock-binding` | A receipt identity differs from the lock's closure for its platform |
| `lock_recipe_mismatch` | `lock-binding` | A lock closure is not one its recipe allows |
| `unsupported_artifact` | `unsupported-artifact` | No artifact matches the requested implementation, deployment, release, platform or protocol |
| `abi_unavailable` | `unsupported-artifact` | The preferred provider needs a WASM ABI the host does not support |
| `no_compatible_release` | `unsupported-artifact` | Tool release metadata v1: no release matches the selection |
| `missing_prerequisite` | `missing-prerequisite` | A declared prerequisite is absent |
| `offline_content_unavailable` | `offline-content-unavailable` | Locked content is absent from the verified store while offline |
| `ownership_conflict` | `ownership-conflict` | Another owner manages the installation |
| `readiness_failed` | `readiness-failed` | A readiness check failed |
| `generation_not_installed` | `selection-unavailable` | The selected generation is not installed |
| `target_not_authenticated` | `trust-failure` | A target is not listed by the authenticated targets metadata |
| `target_length_mismatch` | `trust-failure` | Tool release metadata v1: bytes disagree with the authenticated length |
| `target_digest_mismatch` | `trust-failure` | Tool release metadata v1: bytes or a bound digest disagree with the authenticated digest |
| `release_descriptor_mismatch` | `trust-failure` | Tool release metadata v1: a binding disagrees with the authenticated release, descriptor or target state |
| `artifact_platform_mismatch` | `trust-failure` | A platform is bound to another platform's artifact |
| `release_revoked` | `trust-failure` | Tool release metadata v1: the authenticated state is revoked |
| `metadata_signature_invalid` | `trust-failure` | Tool release metadata v1: a signature or threshold check failed |
| `metadata_expired` | `trust-failure` | Tool release metadata v1: metadata has expired |
| `metadata_rollback` | `trust-failure` | Tool release metadata v1: a metadata version went backwards |
| `metadata_link_mismatch` | `trust-failure` | Tool release metadata v1: metadata bytes disagree with the role that links them |
| `metadata_root_rotation_invalid` | `trust-failure` | Tool release metadata v1: a root rotation was refused |
| `offline_metadata_unavailable` | `trust-failure` | Tool release metadata v1: required metadata is unavailable offline |
| `repository_unavailable` | `trust-failure` | The repository could not be read for a reason no other code names |

## Fixtures and conformance

The contract is the specification pages, the JSON Schemas, the fixture files and the case manifests. They are language-neutral: an implementation in any language reads the same files and must report the same outcome, code and path for every case. The schemas check document shape; rules a schema cannot express are stated on these pages and covered by cases marked `"schema": "accepts"`.

[`fixtures/0.1.0-draft.1/cases.json`](https://github.com/finos/morphir/tree/main/docs/spec/toolchain/fixtures/0.1.0-draft.1) lists every unsigned fixture document with the contract it claims to follow and either `valid` or the exact code and path, and whether the JSON Schema accepts it. Its `bindings` cases check documents against each other:

| `kind` | Inputs | Check |
| --- | --- | --- |
| `lock-request` | `lock`, `request` | The lock binds the exact request bytes |
| `lock-platform` | `lock`, `platform` | Frozen restore finds the platform's closure |
| `receipt-lock` | `receipt`, `lock` | The receipt binds the exact lock bytes and repeats its closure |
| `resolve` | `recipe`, `request`, `platform` | [Resolution](./toolset-recipe.md#selecting-a-closure) gives the listed providers, or the code and path |
| `plan-canonical` | `result`, `canonical` | The plan's canonical bytes are exactly `canonical`, and `planSha256` is their SHA-256 |

`fixtures/0.1.0-draft.1/signed/` holds a TEST-ONLY repository in the tool release metadata v1 profile. Its `cases.json` has these sections:

| Section | Each case | Check |
| --- | --- | --- |
| `selection` | `recipe` target, `request` text, `platform` | Resolution against the authenticated recipe |
| `recipeChecks` | `recipe` target | The [authenticated recipe checks](./toolset-recipe.md#authenticated-recipe-targets) |
| `trust` | `metadata` set, `mutations`, `action` | The outcome of loading or reading the mutated repository |
| `frozen` | `request`, `lock`, `recipe` | The lock equals the resolution of the request on every platform it records |
| `lockRecipe` | `lock`, `recipe` | The lock's closures are ones the recipe allows |

A trust case starts from the committed `repository.json`, takes the named metadata set (`metadata` or `learnedRevocation`), applies its `mutations` in order and serves the result as a consistent-snapshot repository trusted from `trustedRoot`:

| Mutation `op` | Effect |
| --- | --- |
| `set-signed-member` | Set the member at the RFC 6901 `pointer` inside `role`'s `signed` object to `value`, without signing again |
| `relink` | Recompute the snapshot's `targets.json` and the timestamp's `snapshot.json` length, SHA-256 and version over their canonical bytes, and sign the snapshot and timestamp again with the fixture keys |
| `replace-role` | Replace `role`'s envelope with the one at the dotted path `from` in `repository.json` |
| `replace-target-bytes` | Serve the bytes of target `with` in place of target `target` |
| `replace-target-text` | Serve `target` with the first `find` replaced by `replace` |

The `action` is `load` (load the repository), `read` (read `target` through the TUF client), `authenticate` (compare `text` with `target`), `check-recipe` (the authenticated recipe checks) or `check-recipe-bindings` (the binding checks on `recipe` after its `documentMutations`, without authenticating the recipe document).

Every key in the signed repository is the Ed25519 key whose 32-byte seed is the SHA-256 of a public UTF-8 label recorded in `testOnlyKeys`. Anyone can therefore sign with it, which is what makes the `relink` mutation reproducible in any language and why the keys can never serve as a production root. A production configuration must refuse that `repositoryId` and those keys.

Digests and versions in these fixtures are synthetic. A repeated-character digest (`aaaa…`) or the SHA-256 of a `synthetic:<label>` string names no released artifact, and version `1.2.3` is illustrative.

## The reference reader

This repository checks the cases with the `morphir-toolchain-contract` crate. It is this repository's reference reader for these document contracts: it parses each document into domain types and runs the cases above. It is ordinary schema and conformance testing, not a compatibility runner, and it implements no acquisition. IR and MEP behavior is qualified separately; where that shared kit will live is being decided.

Resolution (`resolve_closure`), recipe selection and the authenticated-target checks make resolution behavior normative. Each rule they apply is therefore stated on the [toolset recipe](./toolset-recipe.md) page and pinned by fixtures, so an implementation never has to read the Rust code. Whether the reference reader stays in Rust is a maintainer decision.

```sh
cargo test --locked --package morphir-toolchain-contract
```

CI runs the same command through `mise run ci:validate-toolchain-contracts`, and checks the schemas with `mise run fmt-check:schema` and `mise run lint:schema`.
