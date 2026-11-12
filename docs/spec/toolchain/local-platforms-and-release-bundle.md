---
title: Local toolchain platforms and release bundles
sidebar_label: Platforms and release bundles
status: draft
---

# Local toolchain platforms and release bundles

`local-toolchains/0.1.0-preview.3` extends the
[composed generation contract](./local-composed-generation.md) in three ways:

- `win-arm64` joins `win-x64` as a supported platform for `morphir` and `morphirup`.
- An installation's origin is either `local-developer`, as in preview.2, or
  `release-checksum`, for a toolchain that `morphirup setup` acquires from an
  official finos/morphir-dotnet release.
- A new `bundle` document lists every asset of one platform's release, and a
  release-checksum generation keeps the exact bundle and checksum bodies it
  was installed from.

A release checksum establishes byte identity against the release's own
`SHA256SUMS`. It is not publisher authentication.

## The six documents

Every document writes `$schema` first, and a reader matches its full URL
exactly. No preview.2 document is read as preview.3, and nothing converts
between the two.

| Document | Published schema | Location |
| --- | --- | --- |
| Candidate | [candidate](/schemas/local-toolchains/0.1.0-preview.3/candidate.schema.json) | Setup input, then the generation's exact `candidate.json`. A release publishes it as `morphir-host-candidate-<platform>.json`. |
| Bundle | [bundle](/schemas/local-toolchains/0.1.0-preview.3/bundle.schema.json) | Release asset `morphir-toolchain-<platform>.json`, then the generation's exact `acquisition/bundle.json`. |
| Generation | [generation](/schemas/local-toolchains/0.1.0-preview.3/generation.schema.json) | `toolchains/generations/<generationSha256>/generation.json`. |
| Receipt | [receipt](/schemas/local-toolchains/0.1.0-preview.3/receipt.schema.json) | The same generation's `receipt.json`. |
| Selection | [selection](/schemas/local-toolchains/0.1.0-preview.3/selection.schema.json) | Home-relative `toolchains/default.json`. |
| Result | [result](/schemas/local-toolchains/0.1.0-preview.3/result.schema.json) | Manager command stdout. |

The portable extension selection inside a candidate's installation keeps its
own `toolchains/0.1.0-preview.1/selection.schema.json` format, and a release
publishes it as `morphir-extensions-<platform>.json`.

## What changed from preview.2

| Schema | Change |
| --- | --- |
| All five preview.2 schemas | `$id` and `$schema` name `0.1.0-preview.3`. |
| `candidate` | `origin` is `local-developer` or `release-checksum`; `platform` is `win-x64` or `win-arm64`. |
| `receipt` | `origin` is `local-developer` or `release-checksum`; `platform` is `win-x64` or `win-arm64`. |
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

## Platforms

`platform` in the candidate, receipt and bundle is `win-x64` or `win-arm64`.
Any other value is invalid. The platform reaches the selection only through the
receipt it is bound to by hash, and reaches the generation only through the
candidate it is bound to.

The manager refuses a candidate whose platform differs from the platform of its
own running process.

## Origins

`origin` in the candidate, receipt, selection and result is one of:

| Origin | Meaning |
| --- | --- |
| `local-developer` | The developer supplied the candidate and archive explicitly. Nothing claims they came from a release. |
| `release-checksum` | `morphirup setup` downloaded the candidate, archive and providers from one finos/morphir-dotnet release and checked every asset against the release's `bundle` and `SHA256SUMS`. |

`sourceRepository` in the candidate is `https://github.com/finos/morphir-dotnet`
for both origins, as in preview.2. It is the producer's declaration, not an
attestation.

## Release bundle

A bundle has exactly these members:

| Member | Meaning |
| --- | --- |
| `$schema` | Exact preview.3 bundle schema URL. |
| `version` | The release's SemVer version, without build metadata. The release tag is `v<version>`. |
| `sourceCommit` | Lowercase 40-character source commit of the release. |
| `platform` | `win-x64` or `win-arm64`. |
| `assets` | Exactly nine closed `{ name, url, bytes, sha256, role }` entries, one for each role below. |

| Role | Asset |
| --- | --- |
| `host-candidate` | The candidate document, `morphir-host-candidate-<platform>.json`. |
| `host-archive` | The self-contained host archive, `morphir-dotnet-<version>-self-contained-<platform>.zip`. |
| `selection` | The portable extension selection, `morphir-extensions-<platform>.json`. |
| `frontend-release` | The frontend's extension release envelope. |
| `frontend-manifest` | The frontend's canonical package manifest. |
| `frontend-archive` | The frontend's process archive. |
| `backend-release` | The backend's extension release envelope. |
| `backend-manifest` | The backend's canonical package manifest. |
| `backend-archive` | The backend's process archive. |

There is no sample role. Each asset's `name` is a single path segment, unique
without regard to case. Its `url` is exactly
`https://github.com/finos/morphir-dotnet/releases/download/v<version>/<name>`,
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
| `repository` | `https://github.com/finos/morphir-dotnet`. |
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
| `asset-platform` | Release asset names carry the bundle's platform: `morphir-host-candidate-<platform>.json`, `morphir-extensions-<platform>.json`, `morphir-toolchain-<platform>.json`, and `-<platform>.` in every other asset name. For example, an ARM64 release publishes `morphir-host-candidate-win-arm64.json`, `morphir-extensions-win-arm64.json` and `morphir-toolchain-win-arm64.json`. |
| `provider-platform` | Each selected provider's pin in the portable selection has an entry in `platforms` for the candidate's platform, and the manager uses that entry: `platforms["win-arm64"]` for an ARM64 candidate, `platforms["win-x64"]` for an x64 one. With a bundle, that digest equals the role's archive asset digest. |
| `bindings` | The receipt, generation and result name the digest of the exact candidate bytes. The candidate and generation name the digest of the exact portable selection bytes. The receipt, selection and result name the digest of the exact generation bytes, and `receiptPath` is `toolchains/generations/<generationSha256>/receipt.json`. The selection names the digest of the exact receipt bytes. The receipt repeats the candidate's implementation, deployment, version, source commit, build identity, entry point and archive digest, and its `installationPath` is `store/tools/sha256/<archive.sha256>`. The generation locks both selected providers. |
| `release-bindings` | The bundle's `sourceCommit` is the candidate's. Its `version` is the candidate's version without build metadata, and the generation's `tag` is `v<version>`. The `host-candidate` asset has the candidate's exact digest and length. The `host-archive` asset has the candidate's archive digest and length. The `selection` asset has the candidate's selection digest. Each `<role>-release` asset has the digest of that provider's `metadata` entry in the generation. `acquisition.bundle.sha256` and `acquisition.checksums.sha256` are the digests of the retained files, and `SHA256SUMS` lists the bundle and every asset with matching digests. |

The installation path is derived from the archive digest, not from the
platform name. An x64 and an ARM64 host have different archives, so they never
share a store folder.

## Fixed examples

The [preview.3 examples](https://github.com/finos/morphir/tree/main/docs/spec/toolchain/local/0.1.0-preview.3)
are test-only document sets with synthetic digests. Each set holds one
installation's candidate, portable selection, generation, receipt, selection
pointer and result, and the release-checksum sets also hold
`acquisition/bundle.json` and `acquisition/SHA256SUMS`. Every digest one
document holds of another is the digest of the written bytes.

| Valid set | Platform | Origin |
| --- | --- | --- |
| `valid/win-arm64-release-checksum` | `win-arm64` | `release-checksum` |
| `valid/win-arm64-local-developer` | `win-arm64` | `local-developer` |
| `valid/win-x64-release-checksum` | `win-x64` | `release-checksum` |
| `valid/win-x64-local-developer` | `win-x64` | `local-developer` |

Each invalid set has an `expected.json` naming the documents that fail their
schema or the rule that fails:

| Invalid set | Fails |
| --- | --- |
| `invalid/unknown-platform` | The candidate, receipt and bundle schemas (`win-x86`). |
| `invalid/candidate-receipt-platforms-differ` | `platform-agreement`. |
| `invalid/candidate-receipt-origins-differ` | `origin-agreement`. |
| `invalid/local-developer-with-acquisition` | `acquisition-by-origin`. |
| `invalid/release-checksum-without-acquisition` | `acquisition-by-origin`. |
| `invalid/arm64-provider-uses-x64-entry` | `provider-platform`. |
| `invalid/asset-name-names-another-platform` | `asset-platform`. |

The result of the ARM64 release-checksum set, `result.json`, is what a release
setup that installed it would print:

```json
{
  "$schema": "https://morphir.finos.org/schemas/local-toolchains/0.1.0-preview.3/result.schema.json",
  "command": "setup",
  "status": "installed",
  "origin": "release-checksum",
  "candidateSha256": "37146dab49c337e5d2e6b0507ccf42861492b6ce4d8fe351555bed2d5507372b",
  "generationSha256": "72d2549008f2c7a2602cd6f0b3b843223d50ae2fc1977d48d3ce23030c8c7d2c",
  "receiptPath": "toolchains/generations/72d2549008f2c7a2602cd6f0b3b843223d50ae2fc1977d48d3ce23030c8c7d2c/receipt.json",
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
the preview.2 or preview.3 selection pointer by its exact `$schema`.
