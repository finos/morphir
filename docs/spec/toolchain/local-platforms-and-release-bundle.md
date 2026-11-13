---
title: Local toolchain platforms and release bundles
sidebar_label: Platforms and release bundles
status: draft
---

# Local toolchain platforms and release bundles

`local-toolchains/0.1.0-preview.5` extends the
[composed generation contract](./local-composed-generation.md) in three ways:

- `win-arm64` and `osx-arm64` join `win-x64` as supported platforms for
  `morphir` and `morphirup`. An `osx-arm64` host comes in a `tar-gzip` archive,
  and its entry point is `morphir`.
- An installation's origin is either `local-developer`, as in preview.2, or
  `release-checksum`, for a toolchain that `morphirup setup` acquires from an
  official finos/morphir release.
- A new `bundle` document lists every asset of one platform's release, and a
  release-checksum generation keeps the exact bundle and checksum bodies it
  was installed from.

The toolchain is released from finos/morphir, where the official Morphir CLI is
released. Its code is still built in finos/morphir-dotnet, which the candidate
names as its source repository.

`local-toolchains/0.1.0-preview.4` is the earlier version of this family, whose
releases come from finos/morphir-dotnet. The released morphirup `0.5.0-alpha.1`
reads it, and its schemas and examples stay published unchanged.
`local-toolchains/0.1.0-preview.3` is the Windows-only version before it.
Nothing converts between previews.

A release checksum establishes byte identity against the release's own
`SHA256SUMS`. It is not publisher authentication.

## The six documents

Every document writes `$schema` first, and a reader matches its full URL
exactly. No preview.2, preview.3 or preview.4 document is read as preview.5.

| Document | Published schema | Location |
| --- | --- | --- |
| Candidate | [candidate](/schemas/local-toolchains/0.1.0-preview.5/candidate.schema.json) | Setup input, then the generation's exact `candidate.json`. A release publishes it as `morphir-host-candidate-<platform>.json`. |
| Bundle | [bundle](/schemas/local-toolchains/0.1.0-preview.5/bundle.schema.json) | Release asset `morphir-toolchain-<platform>.json`, then the generation's exact `acquisition/bundle.json`. |
| Generation | [generation](/schemas/local-toolchains/0.1.0-preview.5/generation.schema.json) | `toolchains/generations/<generationSha256>/generation.json`. |
| Receipt | [receipt](/schemas/local-toolchains/0.1.0-preview.5/receipt.schema.json) | The same generation's `receipt.json`. |
| Selection | [selection](/schemas/local-toolchains/0.1.0-preview.5/selection.schema.json) | Home-relative `toolchains/default.json`. |
| Result | [result](/schemas/local-toolchains/0.1.0-preview.5/result.schema.json) | Manager command stdout. |

The portable extension selection inside a candidate's installation keeps its
own `toolchains/0.1.0-preview.1/selection.schema.json` format, and a release
publishes it as `morphir-extensions-<platform>.json`.

## What changed from preview.2

| Schema | Change |
| --- | --- |
| All five preview.2 schemas | `$id` and `$schema` name `0.1.0-preview.5`. |
| `candidate` | `origin` is `local-developer` or `release-checksum`; `platform` is `win-x64`, `win-arm64` or `osx-arm64`; `archive.format` is `zip` or `tar-gzip`, as the platform requires; the entry point's file name is the platform's. |
| `receipt` | `origin` is `local-developer` or `release-checksum`; `platform` is `win-x64`, `win-arm64` or `osx-arm64`; the entry point's file name is the platform's. |
| `selection` | `origin` is `local-developer` or `release-checksum`. |
| `result` | `origin` is `local-developer` or `release-checksum`. |
| `generation` | New optional `acquisition` member. |
| `bundle` | New document. |

Every other member keeps its preview.2 meaning: the self-contained .NET
offering, the complete `files` inventory of the host folder (at most 8192
entries), the archive and file byte bounds, the selected frontend and backend,
the workflow observations, the launch records and the selection pointer.
`selection`, `result` and `generation` have no `platform` member. `generation`
and `bundle` have no `origin` member.

## What changed from preview.3

| Schema or rule | Change |
| --- | --- |
| All six schemas | `$id` and `$schema` name `0.1.0-preview.5`. |
| `candidate`, `receipt`, `bundle` | `platform` also accepts `osx-arm64`. |
| `candidate` | `archive.format` is `zip` or `tar-gzip`, as the platform requires, and the entry point's file name is the platform's. Preview.3 accepted only `zip` and did not constrain the entry point's name. |
| `receipt` | The entry point's file name is the platform's. |
| `bundle` | Asset URLs name finos/morphir releases. See the changes from preview.4 below. |
| `generation` | `acquisition.repository` is `https://github.com/finos/morphir`. |
| Rule `asset-platform` | The host and provider archive names also end with the platform's archive file extension. |

## What changed from preview.4

| Schema or rule | Change |
| --- | --- |
| All six schemas | `$id` and `$schema` name `0.1.0-preview.5`. |
| `bundle` | Each asset's `url` matches `^https://github\.com/finos/morphir/releases/download/v[^/]+/[^/]+$`. Preview.4 required `finos/morphir-dotnet`. |
| `generation` | `acquisition.repository` is `https://github.com/finos/morphir`. Preview.4 required `https://github.com/finos/morphir-dotnet`. |
| `candidate` | Only the `$id` and `$schema` URLs. `sourceRepository` stays `https://github.com/finos/morphir-dotnet`, because that is where the code is built. |
| Rule `release-bindings` | Also states that the generation's `acquisition.repository` is the release repository. |

Release asset names do not change. The host archive is still named
`morphir-dotnet-<version>-self-contained-<platform><extension>`.

## Platforms

`platform` in the candidate, receipt and bundle is one of the platforms below.
Any other value is invalid. Each platform has exactly one archive format and one
entry point file name:

| Platform | `archive.format` | Archive file extension | Entry point file name |
| --- | --- | --- | --- |
| `win-x64` | `zip` | `.zip` | `morphir.exe` |
| `win-arm64` | `zip` | `.zip` | `morphir.exe` |
| `osx-arm64` | `tar-gzip` | `.tar.gz` | `morphir` |

A candidate whose `archive.format` is not its platform's is invalid: a Windows
candidate with `tar-gzip` and an `osx-arm64` candidate with `zip` both fail the
candidate schema. The candidate and receipt schemas also refuse an
`entryPoint.path` whose last segment is not the platform's entry point file
name. The archive file extension applies to the host and provider archives a
release publishes.

The platform reaches the selection only through the receipt it is bound to by
hash, and reaches the generation only through the candidate it is bound to.

The manager refuses a candidate whose platform differs from the platform of its
own running process.

## Origins

`origin` in the candidate, receipt, selection and result is one of:

| Origin | Meaning |
| --- | --- |
| `local-developer` | The developer supplied the candidate and archive explicitly. Nothing claims they came from a release. |
| `release-checksum` | `morphirup setup` downloaded the candidate, archive and providers from one finos/morphir release and checked every asset against the release's `bundle` and `SHA256SUMS`. |

`sourceRepository` in the candidate is `https://github.com/finos/morphir-dotnet`
for both origins, as in preview.2, because that is where the code is built. It
is the producer's declaration, not an attestation. The release repository is a
separate fact: a release-checksum toolchain is released from
`https://github.com/finos/morphir`, which the bundle's asset URLs and the
generation's `acquisition.repository` name.

## Release bundle

A bundle has exactly these members:

| Member | Meaning |
| --- | --- |
| `$schema` | Exact preview.5 bundle schema URL. |
| `version` | The release's SemVer version, without build metadata. The release tag is `v<version>`. |
| `sourceCommit` | Lowercase 40-character source commit of the release. |
| `platform` | `win-x64`, `win-arm64` or `osx-arm64`. |
| `assets` | Exactly nine closed `{ name, url, bytes, sha256, role }` entries, one for each role below. |

| Role | Asset |
| --- | --- |
| `host-candidate` | The candidate document, `morphir-host-candidate-<platform>.json`. |
| `host-archive` | The self-contained host archive, `morphir-dotnet-<version>-self-contained-<platform><extension>`, where `<extension>` is the platform's archive file extension. |
| `selection` | The portable extension selection, `morphir-extensions-<platform>.json`. |
| `frontend-release` | The frontend's extension release envelope. |
| `frontend-manifest` | The frontend's canonical package manifest. |
| `frontend-archive` | The frontend's process archive, with the platform's archive file extension. |
| `backend-release` | The backend's extension release envelope. |
| `backend-manifest` | The backend's canonical package manifest. |
| `backend-archive` | The backend's process archive, with the platform's archive file extension. |

There is no sample role. Each asset's `name` is a single path segment, unique
without regard to case. Its `url` is exactly
`https://github.com/finos/morphir/releases/download/v<version>/<name>`,
so an asset cannot name another repository, another tag or an escaped
separator. `bytes` is between 1 and 2^30 inclusive. `sha256` is the asset's
lowercase SHA-256.

The release's `SHA256SUMS` has one `<sha256>  <name>` line for every asset and
one for the bundle itself, under the name `morphir-toolchain-<platform>.json`.
Names are unique, and each digest equals the bundle's.

## Acquisition in the generation

A release-checksum generation keeps the exact bytes of the bundle at
`acquisition/bundle.json` and of the checksum file at `acquisition/SHA256SUMS`,
and records them in `acquisition`:

| `acquisition` member | Meaning |
| --- | --- |
| `repository` | `https://github.com/finos/morphir`, the release repository. |
| `tag` | `v` followed by the bundle's `version`. |
| `bundle` | `{ path: "acquisition/bundle.json", sha256 }`, the digest of the exact retained bytes. |
| `checksums` | `{ path: "acquisition/SHA256SUMS", sha256 }`, the digest of the exact retained bytes. |

Because these files are part of the generation, `generationSha256` changes when
either changes. A release-checksum generation also lists both providers'
original release envelopes in `metadata`.

## Rules across documents

A single schema cannot check these rules. A reader checks them, and the parent
repository's fixed examples are tested against them by name.

| Rule | Statement |
| --- | --- |
| `schema-first` | `$schema` is the first member of every JSON document. |
| `origin-agreement` | The candidate, receipt, selection and result of one installation have the same `origin`. |
| `platform-agreement` | The candidate, receipt and bundle have the same `platform`, and it is the platform of the manager process and of the host archive. |
| `acquisition-by-origin` | When the candidate's origin is `release-checksum`, the generation has `acquisition` and keeps both acquisition files. When it is `local-developer`, the generation has no `acquisition` member and no acquisition files: the developer gave the archive explicitly, so nothing claims it was acquired from a release. |
| `asset-platform` | Release asset names carry the bundle's platform: `morphir-host-candidate-<platform>.json`, `morphir-extensions-<platform>.json`, `morphir-toolchain-<platform>.json`, and `-<platform>.` in every other asset name. The `host-archive`, `frontend-archive` and `backend-archive` names end with the platform's archive file extension. For example, a Windows ARM64 release publishes `morphir-host-candidate-win-arm64.json`, `morphir-extensions-win-arm64.json`, `morphir-toolchain-win-arm64.json` and `morphir-dotnet-<version>-self-contained-win-arm64.zip`, and a macOS ARM64 release publishes `morphir-dotnet-<version>-self-contained-osx-arm64.tar.gz`. |
| `provider-platform` | Each selected provider's pin in the portable selection has an entry in `platforms` for the candidate's platform, and the manager uses that entry: `platforms["win-arm64"]` for a Windows ARM64 candidate, `platforms["win-x64"]` for an x64 one, `platforms["osx-arm64"]` for a macOS ARM64 one. With a bundle, that digest equals the role's archive asset digest. |
| `bindings` | The receipt, generation and result name the digest of the exact candidate bytes. The candidate and generation name the digest of the exact portable selection bytes. The receipt, selection and result name the digest of the exact generation bytes, and `receiptPath` is `toolchains/generations/<generationSha256>/receipt.json`. The selection names the digest of the exact receipt bytes. The receipt repeats the candidate's implementation, deployment, version, source commit, build identity, entry point and archive digest, and its `installationPath` is `store/tools/sha256/<archive.sha256>`. The generation locks both selected providers. |
| `release-bindings` | The bundle's `sourceCommit` is the candidate's. Its `version` is the candidate's version without build metadata, the generation's `acquisition.repository` is `https://github.com/finos/morphir`, and the generation's `tag` is `v<version>`. Every asset `url` is `https://github.com/finos/morphir/releases/download/v<version>/<name>` for that asset's `name`. The `host-candidate` asset has the candidate's exact digest and length. The `host-archive` asset has the candidate's archive digest and length. The `selection` asset has the candidate's selection digest. Each `<role>-release` asset has the digest of that provider's `metadata` entry in the generation. `acquisition.bundle.sha256` and `acquisition.checksums.sha256` are the digests of the retained files, and `SHA256SUMS` lists the bundle and every asset with matching digests. |

The installation path is derived from the archive digest, not from the
platform name. Hosts for different platforms have different archives, so they
never share a store folder.

## Fixed examples

The [preview.5 examples](https://github.com/finos/morphir/tree/main/docs/spec/toolchain/local/0.1.0-preview.5)
are test-only document sets with synthetic digests. Each set holds one
installation's candidate, portable selection, generation, receipt, selection
pointer and result, and the release-checksum sets also hold
`acquisition/bundle.json` and `acquisition/SHA256SUMS`. Every digest one
document holds of another is the digest of the written bytes. Every
[preview.4 example](https://github.com/finos/morphir/tree/main/docs/spec/toolchain/local/0.1.0-preview.4)
is carried forward under the same name, with its `$schema` URLs at preview.5,
its bundle URLs and acquisition repository at finos/morphir, and its digests
recomputed.

| Valid set | Platform | Origin |
| --- | --- | --- |
| `valid/osx-arm64-release-checksum` | `osx-arm64` | `release-checksum` |
| `valid/osx-arm64-local-developer` | `osx-arm64` | `local-developer` |
| `valid/win-arm64-release-checksum` | `win-arm64` | `release-checksum` |
| `valid/win-arm64-local-developer` | `win-arm64` | `local-developer` |
| `valid/win-x64-release-checksum` | `win-x64` | `release-checksum` |
| `valid/win-x64-local-developer` | `win-x64` | `local-developer` |

Each invalid set has an `expected.json` naming the documents that fail their
schema or the rule that fails:

| Invalid set | Fails |
| --- | --- |
| `invalid/unknown-platform` | The candidate, receipt and bundle schemas (`win-x86`). |
| `invalid/osx-arm64-archive-is-zip` | The candidate schema (an `osx-arm64` candidate with `zip`). |
| `invalid/win-x64-archive-is-tar-gzip` | The candidate schema (a `win-x64` candidate with `tar-gzip`). |
| `invalid/candidate-receipt-platforms-differ` | `platform-agreement`. |
| `invalid/candidate-receipt-origins-differ` | `origin-agreement`. |
| `invalid/local-developer-with-acquisition` | `acquisition-by-origin`. |
| `invalid/release-checksum-without-acquisition` | `acquisition-by-origin`. |
| `invalid/arm64-provider-uses-x64-entry` | `provider-platform`. |
| `invalid/asset-name-names-another-platform` | `asset-platform`. |
| `invalid/bundle-url-names-morphir-dotnet` | The bundle schema and `release-bindings` (asset URLs under finos/morphir-dotnet). |
| `invalid/acquisition-repository-is-morphir-dotnet` | The generation schema and `release-bindings` (`acquisition.repository` is finos/morphir-dotnet). |

The result of the ARM64 release-checksum set, `result.json`, is what a release
setup that installed it would print:

```json
{
  "$schema": "https://morphir.finos.org/schemas/local-toolchains/0.1.0-preview.5/result.schema.json",
  "command": "setup",
  "status": "installed",
  "origin": "release-checksum",
  "candidateSha256": "5309eb838c6ef493c164e54235b1f1a54532b63e2f0de711ef1b35e12a816f54",
  "generationSha256": "231f74b99052a6cb43f1a73db86feb9595f749ffe3dddd2ab4ccb3c7bafbb4a9",
  "receiptPath": "toolchains/generations/231f74b99052a6cb43f1a73db86feb9595f749ffe3dddd2ab4ccb3c7bafbb4a9/receipt.json",
  "selectionPath": "toolchains/default.json"
}
```

## Release setup

```text
morphirup setup --home <H> --dry-run
morphirup setup --home <H> --yes
```

Release setup without `--candidate`, `--local-archive` or `--local-developer`
reads the bundle and `SHA256SUMS` of the release whose version comes from the
nearest `.morphir/toolchain.toml`, or of the manager's own version. It checks
the candidate, selection and provider envelopes against the bundle before it
downloads an archive. The dry run plans without creating Home or running code.
Stderr states that the delivery is release-checksum and not
publisher-authenticated. Selection, show and run work as in preview.2, and read
only the preview.5 selection pointer, by its exact `$schema`. A Home set up with
an earlier preview is not read; run setup again.
