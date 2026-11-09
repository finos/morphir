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

A reader ignores any member it does not understand, at any depth. `critical` is an optional array of unique member paths, written as dotted member names from the document root without array indices (`toolset.providers.delivery`). A reader refuses a critical path it does not understand with `unsupported_critical_member` and names the path. A critical path that names an understood member is accepted. Each page lists the paths a `0.1.0-draft.1` reader understands, and each schema enumerates them under `critical`.

### Tagged cases

Members that select a case are closed sets: `delivery`, `operation`, prerequisite and authentication `kind`, ownership `kind`, readiness, check and diagnostic `kind`. A reader refuses a case it does not know with `unsupported_case` instead of guessing.

The provider delivery cases are:

| `delivery` | Meaning | Identities it requires |
| --- | --- | --- |
| `built-in` | Compiled into the host | `modelInput` only; no artifact |
| `process` | A native process speaking Content-Length framed MEP | Descriptor and per-platform artifact digests |
| `wasm` | A portable module for one named ABI | `abi`, descriptor and artifact digests |
| `dotnet-tool` | A .NET tool package installed into an isolated tool path | `packageId`, `command`, package digest |

The public runtime name for WASM stays `wasm`. The ABI, such as `morphir-bytes-v1` or `extism-kernel-v1`, is a separate member, and a host that supports one ABI never accepts a guest for another.

Prerequisites are `runtime`, `sdk` (with `phase` `install` or `run`) and `native` (optionally limited to `platforms`). Versions are lists of single SemVer comparators, `[">=10.0.0", "<11.0.0"]`, because Rust and TypeScript separate combined ranges differently.

### Identifiers

| Value | Rule |
| --- | --- |
| Implementation, deployment, preset, language, target, ABI, generation id | A lowercase portable token: `[a-z]`, then `[a-z0-9-]`, ending in a letter or digit, at most 64 characters |
| Provider identity (`extensionId`) | Portable tokens joined by `.`: `morphir.fsharp`, `org.finos.morphir.fsharp-frontend`, `morphir-fsharp-backend` |
| Tool id | The tool release metadata v1 tool id grammar |
| Digest | 64 lowercase hexadecimal digits of SHA-256 over exact bytes |
| Target path | A relative forward-slash TUF target path. Absolute, drive, rooted, backslash, empty, `.` and `..` segments are `non_portable_path` |
| Version | Canonical SemVer |

The `extensionId` of a toolchain document is the identity the host registry and the MEP handshake use. It is deliberately wider than the extension release descriptor's `extensionId`, which names a store entry and allows only one portable token.

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

### Paths and credentials

Portable documents (recipe, request, lock) contain only relative target paths. Absolute launch paths appear only in local receipts and in `show` results. No document carries a credential: a receipt or result refuses a member named `password`, `passwd`, `secret`, `token`, `apikey`, `api-key`, `authorization`, `credential`, `credentials` or `cookie` at any depth with `credential_in_document`, and a reported mirror URL has no user information, query or fragment.

## Stable diagnostic codes

Readers report one code and the member path it concerns. Paths use dotted member names with `[index]` for array elements, for example `platforms.win-x64.providers[0].artifactTarget`.

| Code | Meaning |
| --- | --- |
| `invalid_document` | Not the document's syntax, a required member is absent, or a member has the wrong JSON type |
| `unsupported_contract_version` | `schemaVersion` is not a listed version |
| `unsupported_critical_member` | `critical` names a path the reader does not understand |
| `unsupported_case` | A tagged member has an unknown case |
| `invalid_value` | A scalar fails its validated type |
| `non_portable_path` | An absolute, rooted or traversing target path |
| `credential_in_document` | A credential member or a URL carrying credentials |
| `inconsistent_document` | Valid members that contradict each other |
| `request_changed` | A lock's `requestSha256` differs from the SHA-256 of the request bytes |
| `platform_not_locked` | Frozen restore needs a platform closure the lock does not record |
| `lock_changed` | A receipt's `lockSha256` differs from the SHA-256 of the lock bytes |
| `receipt_lock_mismatch` | A receipt identity differs from the lock's closure for its platform |
| `unsupported_artifact` | No artifact matches the requested implementation, deployment, platform, ABI or protocol |

## Fixtures and conformance

The fixed cases are under [`fixtures/0.1.0-draft.1/`](https://github.com/finos/morphir/tree/main/docs/spec/toolchain/fixtures/0.1.0-draft.1). `cases.json` lists every fixture document with the contract it claims to follow and either `valid` or the exact code and path a reader must report, and whether the JSON Schema accepts it. Its `bindings` cases check request, lock and receipt identities against each other. Every fixture file is listed; none is an example download.

Digests and versions in these fixtures are synthetic. A repeated-character digest (`aaaa…`) or the SHA-256 of a `synthetic:<label>` string names no released artifact, and version `1.2.3` is illustrative.

The reference readers live in the `morphir-toolchain-contract` crate. They parse each document into domain types and implement no acquisition. Run the cases with:

```sh
cargo test --locked --package morphir-toolchain-contract
```

CI runs the same command through `mise run ci:validate-toolchain-contracts`. The JSON Schemas are also checked by `mise run fmt-check:schema` and `mise run lint:schema`. An implementation in another language reads the same fixture files and must report the same codes and paths. This is ordinary contract testing; it is not a second compatibility runner, and IR or MEP behavior is still qualified through `morphir mck`.
