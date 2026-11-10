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

The contracts these documents refer to keep their own versions. Nothing here renames them in place. A reader reads each one only at the version listed, never an earlier draft of it, and nothing on these pages converts between drafts (maintainer decision of 9 November 2026: transient pre-1.0 formats are not read or converted):

| Referenced contract | Version | Authority |
| --- | --- | --- |
| Tool release descriptor and TUF profile | `schemaVersion: 1` | [Tool release metadata v1](../tool-release-metadata/index.md) |
| Extension release descriptor | `2.0.0-draft.2` | [Extension distribution](../../design/draft/extensions/distribution-and-acquisition.md) |
| Capability claim set | `claimsVersion` `0.1.0-draft.2` | [Extension protocol](../../design/draft/extensions/protocol.md#capability-claims) |
| MEP | The 0.2 line: every prerelease of `0.2.0` and every final `0.2.x` ([MEP versions](#mep-versions)) | [Extension protocol](../../design/draft/extensions/protocol.md) and [model transport](https://github.com/finos/morphir/blob/main/spec/mep/model-transport.md) |
| Model envelope | `0.1.0-draft.1` | [Model transport](https://github.com/finos/morphir/blob/main/spec/mep/model-transport.md) |
| Morphir IR | `formatVersion` | [IR format version](../ir/format-version.md) |

## Glossary

Some words are used with more than one meaning across the toolchain, MEP and morphir-dotnet documents. On these pages they mean:

| Word | Meaning here | Not to be confused with |
| --- | --- | --- |
| host | The Morphir CLI release a generation runs: an implementation, a version and a deployment (`dotnet` `1.2.3` `native-aot`). A recipe's `hosts` are host offerings | The command name a host's `extension list --json` reports (`morphir`, `dotnet-morphir`), and the MEP side that runs guests |
| deployment, offering | One separately published form of a host: `native-aot`, `self-contained`, `framework-dependent` or `dotnet-tool`. An offering is a recipe's entry for one implementation, release and deployment | A command name: `dotnet-morphir` is the command of the `dotnet-tool` deployment |
| readiness | The state one component or one generation reached on one machine: `acquired`, `integrity-verified`, `capability-checked` or `workflow-qualified` | The [readiness workflow case](./readiness-workflow.md), which is the data the workflow check runs |
| `workflow-qualified` | A readiness state: this generation, on this machine, passed the readiness workflow with its selected providers | A qualification claim. It says nothing about a release, an offering or a platform being qualified, which needs release evidence from acquired artifacts. A generation installed from a developer build can reach it |
| probe | The plan member `probe`: whether setup runs a component's code, and with what rights | The install-time `describe` claim check, the readiness handshake, and the AOT probe test projects in morphir-dotnet |
| extension id | A provider's registry and MEP identity, such as `morphir-dotnet.fsharp`, without any transport label or runtime version text | The frontend identity a compile report names, which includes runtime text, and an executable name such as `morphir-fsharp-frontend` |
| capability check | For a process, WASM or .NET tool provider, the session handshake comparing its claims with the locked model. For a built-in, the staged host's `extension list --json` reporting the built-in with the locked `extensionId`, `version`, language or target, and the IR version of its model | The claim check (`claimCheck`), which compares a probe's claims with the descriptor's |

## Rules shared by all five

### Versions

`schemaVersion` is a SemVer string. A reader lists the versions it supports as SemVer requirements and refuses anything else before it reads another member. A `0.1.0-draft.1` reader lists exactly `=0.1.0-draft.1`, so it refuses `0.1.0-draft.2` and the released `0.1.0` with `unsupported_contract_version`. A contract version carries no build metadata: `=0.1.0-draft.1` would match `0.1.0-draft.1+build.5` by SemVer precedence, so a reader also refuses any version with build metadata (`lock/negative/draft-build-metadata.json`). Every other version member is compared as exact text in canonical SemVer spelling, so `1.2.3` and `1.2.3+build` are different versions. A string that is not SemVer, such as `0.1`, is `invalid_value`. Drafts promise no compatibility with each other. Use a SemVer library, never a hand-written version type.

A version's major, minor and patch are each at most 18446744073709551615 (2<sup>64</sup> − 1); a larger component is `invalid_value`. A library that holds components in a narrower type, such as a 32-bit integer, must still accept every value up to that bound. A version string has no length bound of its own: it is bounded only by the size of the document that holds it, and a reader never refuses a valid version for its length. A prerelease of 1,100 letters is valid (`mep-version` cases).

The schemas' patterns are ECMA-262 regular expressions. In ECMA-262, `$` matches only at the end of the string, so `"0.2.0\n"` is refused; some engines, .NET's among them, also let `$` match before a final line feed, and a validator built on one must anchor at the end of the string instead.

### MEP versions

A provider's `protocolVersion` and a host offering's `protocolVersions` are MEP versions on the supported 0.2 line. A version is on the line when, in canonical SemVer spelling without build metadata, its major is `0` and its minor `2`, and it either has no prerelease or is a prerelease of `0.2.0`. So `0.2.0-draft.1`, `0.2.0-draft.2`, `0.2.0-DRAFT.1` (SemVer is case-sensitive, so this is another prerelease of `0.2.0`), `0.2.0-rc.1`, `0.2.0` and `0.2.3` are on it, and `0.1.0`, `0.2.1-rc.1`, `0.3.0-draft.1`, `0.3.0`, `1.0.0` and `0.2.0+build.1` are not. MEP `0.1` is not supported.

Two codes apply, following their definitions in the [code table](#stable-codes):

- a string that is not a version in canonical SemVer spelling fails its type and is `invalid_value`, as for every other version member: `0.1`, `0.2`, `v0.2.0`, `00.2.0`, `0.2.0-`, `0.2.0-01`, `"0.2.0\n"`, the empty string, and `0.2.18446744073709551616`, whose patch is past the bound above;
- a SemVer version that is not on the line, build metadata included, names a protocol this contract does not support and is `unsupported_case`, as an unknown case of a tagged member is: `0.1.0`, `0.2.1-rc.1`, `0.3.0-draft.1`, `0.3.0`, `1.0.0` and `0.2.0+build.1`.

Either refusal is at the member that holds the version.

As single comparators the line is `>=0.2.0-0` and `<0.3.0-0`. Both comparators hold for `0.2.1-rc.1` too; the SemVer library rule of the Rust `semver` crate and `@std/semver`, under which a prerelease matches only a comparator naming its own major, minor and patch, is what keeps it out. A library without that rule, such as NuGet's version ranges, must apply the definition above rather than the comparators. The `mep-version` binding cases in `cases.json` pin the line, and `lock/protocol-version-*.json` and `lock/negative/protocol-version-*.json` show it in a lock.

Admitting every prerelease of `0.2.0` is a maintainer exception, for MEP only, to the rule that a prerelease matches only exactly. The five toolchain documents keep exact draft matching for their own `schemaVersion`, as stated above.

Membership is exact, deliberately. A provider fits a host offering only when the offering lists the provider's `protocolVersion`, and a release's claims must list it too ([authenticated recipe checks](./toolset-recipe.md#authenticated-recipe-targets)). So two versions on the line are still different versions: a provider at `0.2.0` does not fit a host that lists only `0.2.0-draft.1` (`recipe/protocol-membership-exact.json` and its `resolve` case). This matches how MEP negotiates, by intersecting the lists of versions each side names. The rule is **provisional** on [open question Q1](#open-questions): whether supporting the 0.2 line means that any version on it may be named, which is this rule, or that peers on the line work together.

### Unknown and critical members

A reader ignores any member it does not understand, at any depth. `critical` is an optional array of unique member paths. A path is a dotted list of member names from the document root. Array elements are named through the array's member name, without an index: `toolset.providers.delivery` names `delivery` in every element of `toolset.providers`. Entries of a map whose keys are data are named by `*`: `platforms.*.providers.modelTuple` names `modelTuple` in every provider of every platform closure.

A reader refuses a critical path it does not understand with `unsupported_critical_member`, and the diagnostic's path is that critical path. Each page lists the paths a `0.1.0-draft.1` reader understands, and each schema enumerates exactly those under `critical`. A critical path is understood only when it is exactly one of those strings. A data-keyed map entry is named only by `*`, and an array element only through its array's member name, so `platforms.win-x64.hostTarget` and `providers[0]` are not understood paths, even though they name members the reader reads. The paths in `critical` are unique: a repeated path is `inconsistent_document` at `critical`.

### Order of checks

A reader reports the first failure it finds, and the order is part of the contract:

1. The bytes are JSON (TOML 1.0 for a request) and the root is an object. Otherwise the code is `invalid_document` at the empty path.
2. `schemaVersion`. If it is absent or not a string, the code is `invalid_document`. If it is not SemVer, `invalid_value`. If it is not a listed version, `unsupported_contract_version`.
3. `critical`. If it is not an array of strings, the code is `invalid_document`. A repeated path is `inconsistent_document` at `critical`, checked before any path is compared with the understood ones. After that, the first path in array order that is not understood is `unsupported_critical_member`.
4. Credentials. The first credential member found by a depth-first scan of the whole document is `credential_in_document`. The scan visits each object's members in UTF-8 byte order of their names and each array's elements in index order. A credential is therefore refused before any other member of the body is read, even inside a member the reader otherwise ignores.
5. The body. A rule that relates members is checked once the members it relates have been read. The recipe's consistency rules marked *after reading* wait for the whole document, in the order of their table.

Within the body:

- array elements are read in index order, so a failure in an earlier element is reported first;
- in a map keyed by data, every key is checked first. The first invalid key in UTF-8 byte order is `invalid_value` at that key. The entries are then read in key order, whatever order the document lists them in. For platform keys, key order is the order of the [platform table](#platforms): `win-x64`, `win-arm64`, `osx-x64`, `osx-arm64`, `linux-x64`, `linux-arm64`, `linux-musl-x64`, `linux-musl-arm64`;
- the checks that compare one document with another, on the recipe, lock and receipt pages, visit platforms in the same order;
- a rule that relates several platforms or elements to each other names their common parent, such as `platforms`, never one of them.

Failures in two different members of one object are not ordered by this contract, with one exception: a reader may report either. The fixtures are written so that no case depends on that order.

The exception is a provider's delivery members. An external provider is checked `protocolVersion` first (its type, then the line), then the members it must not have (`modelInput`, then `modelOutput`), then `modelTuple`. A built-in is checked for the members it must not have (`protocolVersion`, then `modelTuple`), then for its model member. So a provider with an off-line `protocolVersion` and a `modelInput` is refused at `protocolVersion`.

These fixtures each break two rules and pin the order between them:

| Fixture | Rules broken | Reported |
| --- | --- | --- |
| `lock/negative/precedence-version-before-credential.json` | A later draft; a credential member | `unsupported_contract_version` at `schemaVersion` |
| `lock/negative/precedence-duplicate-before-unknown-critical.json` | A repeated critical path that is also not understood | `inconsistent_document` at `critical` |
| `lock/negative/precedence-critical-before-credential.json` | An unknown critical path; a credential member | `unsupported_critical_member` at `platforms.*.unknownMember` |
| `lock/negative/precedence-credential-before-body.json` | A credential member; a non-SemVer host version | `credential_in_document` at `apiKey` |
| `lock/negative/precedence-credential-byte-order.json` | `host.token`, listed first; `Authorization` at the root, listed last | `credential_in_document` at `Authorization` |
| `lock/negative/precedence-platform-table-order.json` | A bad digest in `osx-arm64`, listed first, and in `win-x64` | `invalid_value` at `platforms.win-x64.hostSha256` |
| `lock/negative/precedence-platform-keys-first.json` | A bad digest in `win-x64`; an unknown key `zz-unknown` | `invalid_value` at `platforms.zz-unknown` |
| `lock/negative/precedence-protocol-version-before-model-member.json` | An external provider at MEP `0.3.0` that also has `modelInput` | `unsupported_case` at `platforms.win-x64.providers[0].protocolVersion` |
| `recipe/negative/precedence-body-before-consistency.json` | No operations; a non-SemVer host version | `invalid_value` at `hosts[0].version` |
| `recipe/negative/precedence-consistency-table-order.json` | A second built-in in `hosts[0]`; `hosts[1]` repeats the offering | `inconsistent_document` at `hosts[1]` |
| `receipt/binding/recipe-and-host-substituted.json` (against `lock/two-platforms-bound.json`) | Another recipe; another host release | `receipt_lock_mismatch` at `recipe` |

### Numbers

Every number in these documents is a non-negative integer, such as `downloadBytes`, `installedBytes` and `targetsVersion`. It is written in plain decimal, with no sign, fraction or exponent. `41943040.0` and `1e3` are refused with `invalid_document` at the member, although their values are integers (`result/negative/download-bytes-fraction.json` and `download-bytes-exponent.json`). JSON Schema's `integer` type accepts both, so the schemas are looser here.

### Tagged cases

Members that select a case are closed sets: `delivery`, `operation`, prerequisite, source, ownership and authentication `kind`, readiness, check, status, command, outcome and diagnostic `kind`. A reader refuses a case it does not know with `unsupported_case`. There is no default case: an unknown tag never stands for a known one.

The provider delivery cases are:

| `delivery` | Meaning | Identities it requires |
| --- | --- | --- |
| `built-in` | Compiled into the host | The model it exchanges with the host: `modelOutput` for `compile`, which writes the model, and `modelInput` for `generate`, which reads it. No artifact |
| `process` | A native process speaking Content-Length framed MEP | Descriptor and per-platform artifact digests |
| `wasm` | A portable module for one named ABI | `abi`, descriptor and artifact digests |
| `dotnet-tool` | A .NET tool package installed into an isolated tool path | `packageId`, `command`, package digest, and the release's descriptor digest |

The public runtime name for WASM stays `wasm`. The ABI, such as `morphir-bytes-v1` or `extism-kernel-v1`, is a separate member, and a host that supports one ABI never accepts a guest for another.

Prerequisites are `runtime`, `sdk` (with `phase` `install` or `run`) and `native` (optionally limited to `platforms`). Every prerequisite has `kind` and `name`. `versions` is required for `runtime` and `sdk` and optional for `native`; `phase` is required for `sdk`. A comparator is exactly one of `=`, `>`, `>=`, `<` or `<=`, then a complete version in canonical SemVer spelling, with no space. `^`, `~`, wildcards, partial versions such as `>=10`, and combined ranges are `invalid_value`, because Rust, TypeScript and .NET give them different meanings (`recipe/negative/comparator-*.json`). Versions are lists of single SemVer comparators, `[">=10.0.0", "<11.0.0"]`, because Rust and TypeScript separate combined ranges differently. An installed version meets the list when it satisfies every comparator by SemVer precedence and, if it is a prerelease, at least one comparator names its own major, minor and patch with a prerelease. This is the rule of the Rust `semver` crate and of npm. So `[">=10.0.0", "<11.0.0"]` is not met by `11.0.0-preview.1`, although that version precedes `11.0.0`, and `[">=11.0.0-preview.1", "<12.0.0"]` is met by `11.0.0-rc.1`. An empty list is always met. The `prerequisite-versions` binding cases pin the rule. A native library's version is written as SemVer with missing parts as zero: glibc 2.28 is `2.28.0`, so the comparator is `>=2.28.0`.

### Identifiers

| Value | Rule |
| --- | --- |
| Implementation, deployment, preset, language, target, ABI, generation id, workflow, package manager, command | A lowercase portable token: `[a-z]`, then `[a-z0-9-]`, ending in a letter or digit, at most 64 characters |
| Provider identity (`extensionId`) | Portable tokens joined by `.`, at most 238 characters: `morphir.fsharp`, `morphir-dotnet.fsharp`, `org.finos.morphir.fsharp-frontend`. In `0.1.0-draft.1` each segment also has at most 64 characters |
| NuGet package id | Segments of `[A-Za-z0-9_]` joined by `.` or `-`, at most 100 characters |
| Tool id | The tool release metadata v1 tool id grammar |
| Digest | 64 lowercase hexadecimal digits of SHA-256 over exact bytes |
| Version | Canonical SemVer |

Dotted extension ids are decided, and the approved plan for them is the OpenSpec change `allow-dotted-extension-ids` (finos/morphir#1149, merged 10 November 2026). Its last group, which is still to do here, changes three things in these contracts, refining `0.1.0-draft.1` in place:

- the provider identity takes that change's grammar, including its rule that the first segment is not a Windows device name, so `con.example` becomes invalid;
- the 64-character segment limit is dropped, keeping the 238-character total;
- the referenced extension release descriptor moves to `2.0.0-draft.3`, and the signed fixtures' descriptors are regenerated at that version with the F# guests under their dotted ids.

Until then the table above and the signed fixtures stand as they are. Every other token in the table keeps its 64-character limit. No toolchain document uses an extension id as a JSON member name, so the [critical path](#unknown-and-critical-members) grammar is unaffected; ids appear only as values.

An extension id never appears in a target path: target layouts use the descriptor's `shortId`, as in `extensions/fsharp-frontend/0.6.0/release.json`. An id does name local files, such as the extension lock `MORPHIR_HOME/locks/extensions/<id>.json` and its `<id>.json.transaction` journal. A typical Windows home, the `locks\extensions\` directories and the `.json.transaction` suffix add about 60 characters to the id. So an id longer than about 200 characters exceeds the 260-character `MAX_PATH` when long paths are not enabled. Long ids were already allowed; dotted ids make them more likely.

### Target paths

A target path names an authenticated TUF target. It is relative, uses `/` as its separator, has at most 512 UTF-8 bytes and at most 240 UTF-16 code units, and has no NUL, control character (U+0000 to U+001F), U+2028 or U+2029. Each `/`-separated component:

- is not empty, `.` or `..`;
- does not end in `.` or a space;
- contains none of `\ < > : " | ? *`;
- is at most 255 UTF-8 bytes and 255 UTF-16 code units;
- is not a Windows device name. A component is a device name when the part before its first `.`, with trailing spaces removed and compared ASCII case-insensitively, is `CON`, `PRN`, `AUX`, `NUL`, `CONIN$`, `CONOUT$`, or `COM` or `LPT` followed by one of `1` to `9`, `¹`, `²` or `³`. So `artifacts/CON/win-x64.zip` and `con.tar.gz` are refused.

A path that breaks any of these rules is `non_portable_path`. This page defines the rules. A target that passes them can be stored on every first-delivery platform, and a manager's tool and extension stores apply the same rules to every path they store.

A target path is also in Unicode Normalization Form C, by the Unicode 17.0.0 rule stated with the [plan digest](./manager-result.md#the-plan-digest). Canonical encoding normalizes the keys of signed targets metadata to NFC, so a path in another form would be signed under one key and looked up under another. The rule is applied in three places:

- a publisher refuses to publish a target whose path is not NFC;
- a reader refuses a document member that names a non-NFC target path with `non_portable_path` at that member (`lock/negative/target-path-nfd.json`);
- a client refuses a repository whose targets metadata lists a non-NFC path with `non_portable_path` at the empty path. The canonical encoder normalizes every string to NFC, so only a server that serves non-canonical metadata bytes can list one. The signed fixtures serve canonical bytes, so no signed case lists an NFD path; this refusal has no case.

Non-ASCII NFC paths are allowed, and the signed repository publishes one (`extensions/fsharp-frontend/0.6.0/notes/café-naïve-字.txt`), read by a trust case, so every runner's canonical encoder signs and serves a key that is not ASCII. `lock/target-path-non-ascii-nfc.json` is the valid lock counterpart.

The length limits count UTF-8 bytes and UTF-16 code units, never code points or characters. `字` (U+5B57) is 3 bytes and 1 code unit; `𝄞` (U+1D11E) is 4 bytes and 2 code units. Both limits apply, so a path of 175 code units is still refused when it is 513 bytes. The schemas cannot express these limits: their `maxLength: 240` counts code points, so they accept some paths the reader refuses. The reader's limits govern, and the cases that the schema accepts record that in `schemaGap`. `lock/target-path-512-utf8-bytes.json` and `lock/target-path-240-utf16-units.json` are valid at each limit; `lock/negative/target-path-513-utf8-bytes.json`, `target-path-241-utf16-units.json` and `target-component-256-utf8-bytes.json` are one past them.

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

No document carries a credential. Every reader refuses, at any depth and including inside members it otherwise ignores, a member whose name equals one of `password`, `passwd`, `secret`, `token`, `apiKey`, `api-key`, `api_key`, `authorization`, `credential`, `credentials` or `cookie`, compared ASCII case-insensitively, with `credential_in_document`. So `Authorization` and `APIKEY` are refused too (`lock/negative/precedence-credential-byte-order.json`, `recipe/negative/credential-apikey-uppercase.json`). A reported mirror URL has no user information, query or fragment.

## Stable codes

Readers and checks report one code and the member path it concerns. Paths use dotted member names with `[index]` for array elements, for example `platforms.win-x64.providers[0].artifactTarget`. The empty path means the document itself, or, for an authenticated-target check, the target itself.

Every code has exactly one result diagnostic kind, so a [manager result](./manager-result.md#diagnostics) can report any refusal:

| Code | Result diagnostic kind | Meaning |
| --- | --- | --- |
| `invalid_document` | `unsupported-contract` | Not the document's syntax, a required member is absent, or a member has the wrong JSON type |
| `unsupported_contract_version` | `unsupported-contract` | `schemaVersion` is not a listed version |
| `unsupported_critical_member` | `unsupported-contract` | `critical` names a path the reader does not understand |
| `unsupported_case` | `unsupported-contract` | A tagged member has an unknown case, or a MEP version is not on the [supported line](#mep-versions) |
| `invalid_value` | `unsupported-contract` | A scalar fails its validated type, such as a version that is not canonical SemVer |
| `non_portable_path` | `unsupported-contract` | A target path breaks the target path rules |
| `credential_in_document` | `unsupported-contract` | A credential member or a URL carrying credentials |
| `inconsistent_document` | `unsupported-contract` | Valid members that contradict each other |
| `document_unavailable` | `unsupported-contract` | A document the command needs, such as the project request or lock, is absent or unreadable |
| `request_changed` | `lock-binding` | A lock's `requestSha256` differs from the SHA-256 of the request bytes |
| `platform_not_locked` | `lock-binding` | Frozen restore needs a platform closure the lock does not record |
| `lock_changed` | `lock-binding` | A receipt's `lockSha256` differs from the SHA-256 of the lock bytes |
| `receipt_lock_mismatch` | `lock-binding` | A receipt identity differs from the lock's closure for its platform |
| `lock_recipe_mismatch` | `lock-binding` | A lock closure is not one its recipe allows |
| `plan_changed` | `lock-binding` | `--expect-plan` named another digest than the plan the command made |
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
| `repository_mismatch` | `trust-failure` | A document names a repository identity other than the one the check runs against ([one repository per binding check](./toolset-recipe.md#one-repository-per-binding-check)) |
| `release_revoked` | `trust-failure` | Tool release metadata v1: the authenticated state is revoked |
| `metadata_signature_invalid` | `trust-failure` | Tool release metadata v1: a signature or threshold check failed |
| `metadata_expired` | `trust-failure` | Tool release metadata v1: metadata has expired |
| `metadata_rollback` | `trust-failure` | Tool release metadata v1: a metadata version went backwards |
| `metadata_link_mismatch` | `trust-failure` | Tool release metadata v1: metadata bytes disagree with the role that links them |
| `metadata_root_rotation_invalid` | `trust-failure` | Tool release metadata v1: a root rotation was refused |
| `offline_metadata_unavailable` | `trust-failure` | Tool release metadata v1: required metadata is unavailable offline |
| `repository_unavailable` | `trust-failure` | The repository could not be read for a reason no other code names |

## Fixtures and conformance

The contract is the specification pages, the JSON Schemas, the fixture files and the case manifests. They are language-neutral: an implementation in any language reads the same files and must report the same outcome, code and path for every case. The schemas check document shape. Rules a schema does not express are stated on these pages and covered by cases marked `"schema": "accepts"`; each of those cases also has a `schemaGap` saying why the schema is looser, and a test requires one exactly where the schema accepts a refused document.

The schemas and the readers require the same members. A test removes each member of every valid fixture in turn, at every depth: a member whose absence the reader refuses as missing must be one the schema requires, a member the schema requires must be one the reader refuses without, and the members both let a document omit must be exactly a committed list, each optional on its page.

Cases that pin a row of a check table carry a `rule`, which that row's Cases column names. A row that cannot have a case says `No fixture:` and why. A test fails when a row names no case and is not marked, when a rule's cases report a code or path the row does not list, when a code the row lists has no case, or when a case's rule is in no table.

[`fixtures/0.1.0-draft.1/cases.json`](https://github.com/finos/morphir/tree/main/docs/spec/toolchain/fixtures/0.1.0-draft.1) lists every unsigned fixture document with the contract it claims to follow and either `valid` or the exact code and path, and whether the JSON Schema accepts it. Its `bindings` cases check documents against each other:

| `kind` | Inputs | Check |
| --- | --- | --- |
| `lock-request` | `lock`, `request` | The lock binds the exact request bytes |
| `lock-request-bytes` | `lock`, `request` | As `lock-request`, from the request's bytes alone; a refusal's `expected.cause` names CRLF line endings, a byte order mark, or both, and is absent for other changes |
| `lock-platform` | `lock`, `platform` | Frozen restore finds the platform's closure |
| `receipt-lock` | `receipt`, `lock` | The receipt binds the exact lock bytes and repeats its closure |
| `resolve` | `recipe`, `request`, `platform` | [Resolution](./toolset-recipe.md#selecting-a-closure) gives the listed providers, or the code and path |
| `plan-canonical` | `result`, `canonical` | The plan's canonical bytes are exactly `canonical`, and `planSha256` is their SHA-256 |
| `plan-lock` | `result`, `lock` | The plan's `lock` equals `lock` as a parsed value |
| `setup-platforms` | `request`, `platform` | A setup of `request` on `platform` locks exactly `expected.platforms`, in platform table order ([plans](./manager-result.md#plans)) |
| `prerequisite-versions` | `versions`, `installed` | An installed version `installed` meets the comparator list `versions` exactly when `expected.met` is `true` ([tagged cases](#tagged-cases)) |
| `nfc` | `input`, `expected` | The canonical encoder writes the string `input` as `"`, then `expected`, then `"`: `expected` is the Unicode 17.0.0 NFC of `input` ([the plan digest](./manager-result.md#the-plan-digest)). The inputs hold no `"` or `\` |
| `mep-version` | `version` | Read as a `protocolVersion` value, the string is `valid`, or refused with `invalid_value` or `unsupported_case` ([MEP versions](#mep-versions)). It is the one kind that checks a bare string; `path` is empty because the member's path belongs to the document that holds it. The string is also checked against the schemas' shared `$defs.mepVersion`, and a refused string the pattern accepts says so with `"schema": "accepts"` and a `schemaGap` |
| `discover` | `files`, `boundary`, `start` | [Discovery](./toolchain-request.md#discovery) from `start` finds `expected.request`, or no request when it is `null`. Paths are relative, `/`-separated, and name files under one synthetic root |

`fixtures/0.1.0-draft.1/signed/` holds a TEST-ONLY repository in the tool release metadata v1 profile. Its `cases.json` has these sections:

| Section | Each case | Check |
| --- | --- | --- |
| `selection` | `recipe` target, `request` text, `platform` | Resolution against the authenticated recipe |
| `recipeChecks` | `recipe` target | The [authenticated recipe checks](./toolset-recipe.md#authenticated-recipe-targets) |
| `trust` | `metadata` set, `mutations`, `action` | The outcome of loading or reading the mutated repository |
| `channelSelection` | `preset`, `channel` | The recipe target that [channel selection](./toolset-recipe.md#authenticated-recipe-targets) picks, or the code and path |
| `v1Client` | `toolId`, `channel`, version 1 `platform` | Offering descriptors publish `compatibility.morphirCli` `<0.0.0-0`, so the tool release metadata v1 client selects nothing (`expected.selected` is `false`) at `referenceClient.cliVersion` or any other CLI version. The `fsharp-builtin` recipe still binds `recipeBinding.targetPath` for `deployment` and `recipePlatform` with its authenticated digest, and the 18 digests are distinct |
| `v1Descriptors` | release target | Read through the client, it validates unchanged against `tool-release-v1.schema.json`. Every release target except the deliberate negative is listed |
| `frozen` | `request`, `lock`, `recipe` | The SHA-256 of the request bytes is `expected.requestSha256` and the lock binds it; the lock's `recipe.sha256` is `expected.recipeSha256`, the authenticated recipe digest; the lock records exactly `expected.platforms`, the six first-delivery platforms; and each closure equals the resolution of the request on its platform |
| `lockRecipe` | `lock`, `recipe` | The lock's closures are ones the recipe allows |

The metadata is served as files. Each role is the canonical JSON bytes, by the [plan digest rules](./manager-result.md#the-plan-digest), of its envelope (`signatures` and `signed`) as stored in `repository.json`; every signature is over the canonical bytes of `signed`. The repository uses consistent snapshots:

- the metadata directory holds `1.root.json` (also given to the client out of band as the trusted root), `timestamp.json`, `<version>.snapshot.json` and `<version>.targets.json`, each version taken from that role's `signed.version`;
- each entry of `targetFiles` that the targets metadata lists is served under its SHA-256. tough 0.24, the client used here, requests `<sha256>.<target path>` from the targets directory, and its filesystem transport opens the percent-encoded URL path without decoding it, so the non-ASCII target is served from a file named with `%C3%A9` and the like. The TUF specification puts the digest in front of the file name inside the target's directory, as in `toolchains/recipes/fsharp/<sha256>.1.0.0.json`. A runner serves each target where its own client asks for it; the expected outcomes do not depend on the layout;
- a `targetFiles` entry the targets metadata does not list is not served.

A trust case starts from the committed `repository.json`, takes the named metadata set, applies its `mutations` in order and serves the result as a consistent-snapshot repository trusted from `trustedRoot`:

| Mutation `op` | Effect |
| --- | --- |
| `set-signed-member` | Set the member at the RFC 6901 `pointer` inside `role`'s `signed` object to `value`, without signing again |
| `relink` | Recompute the snapshot's `targets.json` and the timestamp's `snapshot.json` length, SHA-256 and version over their canonical bytes, and sign the snapshot and timestamp again with the fixture keys |
| `replace-role` | Replace `role`'s envelope with the one at the dotted path `from` in `repository.json` |
| `replace-target-bytes` | Serve the bytes of target `with` in place of target `target` |
| `replace-target-text` | Serve `target` with the first `find` replaced by `replace` |

The metadata sets are:

- `metadata`: the published repository, version 1 of every role;
- `learnedRevocation`: version 2, in which the host offering release `morphir-dotnet-native-aot` 1.2.3 has release status `revoked`;
- `recipeRevocation`: version 2, in which the recipe target `toolchains/recipes/fsharp/1.0.0.json` has status `revoked` and no channels, which reaches every generation bound to that recipe.

The `action` is one of:

- `load`: load the repository;
- `read`: read `target` through the TUF client;
- `authenticate`: compare the UTF-8 bytes of `text` with the authenticated length and digest of `target`, as for bytes from a local store;
- `check-recipe`: the authenticated recipe checks on `recipe`;
- `check-recipe-bindings`: read `recipe` through the client and parse it as JSON, then apply each entry of `documentMutations` in order. Each entry has a `pointer`, an RFC 6901 pointer into the recipe document that names an existing member or array element, and a `value` that replaces it. Read the result with the recipe reader and run only the host and provider binding checks. The mutated document is not authenticated, and the recipe target checks are not run on it;
- `check-locked-generation`: the [launch and rollback checks](./installation-receipt.md#launch-and-rollback-against-learned-revocations) on the committed fixture `lock`, against the repository's learned trust state.

A refused load has the empty path, as does a refused `read` or `authenticate` of a target named directly. A binding check reports the binding member that named the target.

The TUF client used here compares expiry with the wall clock and cannot be given another time. So every case has the same outcome at any instant after `2020-01-01T00:00:00Z`, when `rejectionMetadata.expiredTimestamp` expires, and before `2999-01-01T00:00:00Z`, when every other role expires. `referenceTime` (`2030-01-01T00:00:00Z`) is one instant in that window; a runner whose client takes a reference time uses it. A test checks that the window holds and that the current time is inside it.

One outcome stays in a Rust-only test, `a_non_portable_recipe_target_is_refused_without_panicking`: channel selection over a repository that lists a recipe under `toolchains/recipes/con/`. `con` is a device name that older Windows versions cannot create as a directory, so it is kept out of the shared repository that every runner writes to disk. The `recipeChecks` case for `toolchains/recipes/con/1.0.0.json` pins the same `non_portable_path` at the empty path without listing the target, because the path check comes first.

Every key in the signed repository is the Ed25519 key whose 32-byte seed is the SHA-256 of a public UTF-8 label recorded in `testOnlyKeys`. Anyone can therefore sign with it, which is what makes the `relink` mutation reproducible in any language and why the keys can never serve as a production root. A production configuration must refuse that `repositoryId` and those keys.

The [F# readiness workflow case](./readiness-workflow.md) in `spec/toolchain/workflows/fsharp-compile-generate/` is the fixed compile-and-generate case behind the `workflow` readiness check. It has its own manifest schema, [`toolchain-workflow-case-0.1.0-draft.1.schema.json`](/schemas/toolchain-workflow-case-0.1.0-draft.1.schema.json), and its source and expected IR are real corpus data, not synthetic.

Digests and versions in these fixtures are synthetic. A repeated-character digest (`aaaa…`) or the SHA-256 of a `synthetic:<label>` string names no released artifact, and version `1.2.3` is illustrative.

## The reference reader

This repository checks the cases with the `morphir-toolchain-contract` crate. It is this repository's reference reader for these document contracts: it parses each document into domain types and runs the cases above. It is ordinary schema and conformance testing, not a compatibility runner, and it implements no acquisition.

IR and MEP behavior is qualified by the compatibility kit. Following the maintainer's decision of 9 November 2026, the kit's runner lives in finos/morphir-dotnet (`src/Morphir.Conformance`, with the `cli`, `library` and `mep-guest` adapters), and its cases, fixed expectations and report contracts stay in this repository as data. The [F# readiness workflow case](./readiness-workflow.md) is one of them. AGENTS.md still describes the earlier arrangement, in which the runner was the Rust `morphir-mck` crate here.

Resolution (`resolve_closure`), recipe selection and the authenticated-target checks make resolution behavior normative. Each rule they apply is therefore stated on the [toolset recipe](./toolset-recipe.md) page and pinned by fixtures, so an implementation never has to read the Rust code.

The pages are the authority over everything else in the contract: the schemas, the case manifests and their fixtures, and the crate. When any of them disagrees with a page, that one has a defect, and the fix is to change it to match the page. When a page is silent or contradicts itself, the page is fixed first, and the others follow it.

The maintainer treats the Rust CLI as legacy and puts first-delivery work into the morphir-dotnet and morphir-moonbit hosts (9 November 2026). In that light, the crate is a reference checker for these documents, kept while it is cheap to keep. It is not the implementation that other hosts must match, and keeping it signals no investment in the Rust CLI. It takes its identities, channels, digests, target path checks and its TUF client (tough) from `morphir-distribution` in the legacy `ecosystem/morphir-rust` submodule, so it stays cheap only while that library keeps building here. Whether it stays is a question for the maintainer.

```sh
cargo test --locked --package morphir-toolchain-contract
```

CI runs the same command through `mise run ci:validate-toolchain-contracts`, and checks the schemas with `mise run fmt-check:schema` and `mise run lint:schema`.

## Decided

The maintainer's decisions that these pages depend on, each recorded on finos/morphir#1146. The rule each one sets is stated on the page linked.

| Date | Decision | Where the rule is stated |
| --- | --- | --- |
| 9 November 2026 | [MEP `0.1` is not supported; the whole 0.2 line is](https://github.com/finos/morphir/issues/1146#issuecomment-6759463703) | [MEP versions](#mep-versions) |
| 9 November 2026 | [Transient pre-1.0 document formats are not read or converted](https://github.com/finos/morphir/issues/1146#issuecomment-6759463703) | [Version authorities](#version-authorities) |
| 9 November 2026 | [The expected generated F# files are one unformatted set with LF line endings, produced with formatting explicitly off; a formatter hook is a separate later change](https://github.com/finos/morphir/issues/1146#issuecomment-6759989025) (finos/morphir-dotnet#575) | [Readiness workflow](./readiness-workflow.md#generation-expectations) |
| 9 November 2026 | [The TUF client is project-owned, in morphir-dotnet, for the subset the profile uses, with BouncyCastle Ed25519 as its only cryptographic dependency, subject to the maintainer's security review before production use](https://github.com/finos/morphir/issues/1146#issuecomment-6760090078) | [Toolset recipe](./toolset-recipe.md#authenticated-recipe-targets) |
| 9 November 2026 | [The legacy `morphir-{rid}` names carry the Native AOT executable and report `native-aot`; there are four deployment values](https://github.com/finos/morphir/issues/1146#issuecomment-6759878937) | [Installation receipt](./installation-receipt.md#members) |
| 9 November 2026 | [Setup activates a staged generation when no check failed and every component is capability-checked](https://github.com/finos/morphir/issues/1146#issuecomment-6760284288) | [Installation receipt](./installation-receipt.md#readiness) |
| 9 November 2026 | [Managers ship their own NFC data, with no dependency on the machine's ICU, and the contract pins the Unicode version](https://github.com/finos/morphir/issues/1146#issuecomment-6760173619) | [The plan digest](./manager-result.md#the-plan-digest) |
| 9 November 2026 | [The shared extension contract is extended so an extension can be a multi-file package; no self-unpacking single-file frontend](https://github.com/finos/morphir/issues/1146#issuecomment-6760228228) | [Toolset recipe limits](./toolset-recipe.md#limits-of-this-contract-version) |
| 10 November 2026 | [A program named by project configuration does not start until the user has allowed that project](https://github.com/finos/morphir/issues/1146#issuecomment-6760321629) (finos/morphir-dotnet#577) | [Toolchain request](./toolchain-request.md) |

## Open questions

These are the questions still open for the maintainer. Each rule that depends on one is marked provisional where it is stated.

- **Q1. Does supporting the MEP 0.2 line mean any version on it may be named, or that peers on the line work together?** Today a provider fits a host only when the host lists the provider's exact `protocolVersion` ([MEP versions](#mep-versions)). **(A)** Keep exact membership: simple, and it matches MEP negotiation, but a guest released at `0.2.1` fits no host that lists only `0.2.0` until the host releases. **(B)** Compatibility within the line: a host speaking any final `0.2.x` fits a provider at any final `0.2.y`, with prereleases still exact. Patch releases then interoperate, but the contract must define which changes a `0.2.x` release may make, and the claims check changes too. Recommendation: A.
