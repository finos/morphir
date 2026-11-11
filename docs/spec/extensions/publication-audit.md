---
title: Extension publication audit
sidebar_position: 3
---

# Extension publication audit

The approved publication rule selects **PKGVER-A**, so packages join the first
extension state family schemas at `0.1.0-preview.1`. This is the outcome of the
publication-history audit, not a new version choice.

The cutoff is [#1151's merge](https://github.com/finos/morphir/pull/1151) at
**2026-11-11T06:52:34Z**, main commit
`cd391b07564823c14389d42cd14f05e89824e4f8`. Evidence was read on 11 November
2026 after that merge. Release publication and asset update timestamps in the
snapshot precede the cutoff. The [machine-readable evidence](./publication-audit.json)
records complete release, tag and asset inventories, exact tag commits, metadata
asset hashes, NuGet package hashes and publication times, and all documentation
paths and blob hashes. No released code was executed.

## Every source required by package task 1.1

| Source | Evidence at the cutoff | Result |
| --- | --- | --- |
| Parent `main` schema directory | `git ls-tree -r cd391b075 -- website/static/schemas/extensions` is empty. [#1150](https://github.com/finos/morphir/pull/1150) merged at 06:10:37Z as `ec363c61dd955d6979e1c9f7cf94592d19f348ad`; its task 1.7 is unchecked in the approved tree. | No published preview.1 schemas |
| finos/morphir releases and tags | 24 release records and 110 tags. Latest host release [v0.4.0-beta.12](https://github.com/finos/morphir/releases/tag/v0.4.0-beta.12), published 1 November, commit `d3154e9b9a54162a1409593972ac31c4a369f0ec`. Parent source history under `crates/` and `tools/` contains no preview.1 implementation at the cutoff. | Legacy per-file readers/writers |
| finos/morphir-dotnet releases and tags | 10 release records and 11 tags. Latest host release [v0.4.0-alpha.4](https://github.com/finos/morphir-dotnet/releases/tag/v0.4.0-alpha.4), published 10 November 09:59Z, tag commit `bec7df31eb813396e0e119c557e0a319adbe1ebb`. Its downloaded source snapshot has no preview.1 URL or version in C#, F#, JSON or TOML. The installer is planned separately. | No released preview.1 implementation |
| `Morphir.Tool` NuGet | The complete index lists `0.3.0-rc.1`, `0.3.0-rc.2`, and `0.4.0-alpha.1` through `.4`. All six nupkgs were downloaded and hashed. Every ZIP member was inspected as bytes for ASCII and UTF-16LE `0.1.0-preview.1`; none occurs. Nuspecs, package repository commits and publication times are preserved in the evidence. Latest publication is 10 November 09:58:06.67Z. | No package evidence of a preview.1 reader/writer |
| finos/morphir-rust releases and tags | 20 release records and 28 tags. Latest extension release [extension/rust/v0.4.0](https://github.com/finos/morphir-rust/releases/tag/extension/rust/v0.4.0), published 1 November. At parent pin `c9f79da9d2fdd3ae59347cefe057f89f01810d37`, `git grep 0.1.0-preview.1 -- crates` has no matches. Its extension descriptors are integer 1 or draft.2. | Legacy per-file formats |
| MoonBit host repository | [finos/morphir-moonbit](https://github.com/finos/morphir-moonbit), two release records and two tags. Latest [v0.1.0](https://github.com/finos/morphir-moonbit/releases/tag/v0.1.0), published 10 November 13:26Z, tag commit `89f892468649bc6fef6acc40e5bfb2e9800c16da`. Its downloaded source has no preview.1 URL or version in MoonBit, JSON or TOML. | No released preview.1 implementation |
| Every pinned extension repository | Complete release/tag/asset inventories for morphir-extensions, morphir-python, morphir-rust, morphir-elm and morphir-scala. Every JSON, JSONL and TOML metadata asset of at most 2 MB was downloaded and hashed. This includes all extension descriptors and both bundle and legacy descriptors where a release provides both. | No preview.1 extension-state URL in any of the 111 inspected metadata assets |
| Every extension repository named by .NET documentation | All 160 documentation pages at the last main commit before cutoff, `9972c34582157d79c0f63c66dc6b43d20facb77a`, were read. The extension-model PRD names morphir-extensions Avro v0.4.0 and morphir-elm classic v0.6.0; the WASM spike also names morphir-elm v0.5.0-preview.2. Each appears in the inventories and inspected descriptor assets. Other repository mentions concern SDKs, configuration or project examples, not additional extension release repositories. | No additional publisher using preview.1 |

The .NET documents are
[the extension-model PRD](https://github.com/finos/morphir-dotnet/blob/9972c34582157d79c0f63c66dc6b43d20facb77a/docs/content/contributing/design/prds/morphir-extension-model.md)
and [the WASM spike](https://github.com/finos/morphir-dotnet/blob/9972c34582157d79c0f63c66dc6b43d20facb77a/docs/content/contributing/design/spikes/extension-model/wasm-runtime.md).
The audit includes older released extension assets, not just the six current pins.
The 184 Elm release records include one unpublished record; that record was not
treated as a release. Tags are recorded independently from releases.

The MoonBit repository identity is established by its
[`ExtensionId::parse`](https://github.com/finos/morphir-moonbit/blob/89f892468649bc6fef6acc40e5bfb2e9800c16da/pkgs/morphir-host/worker/claims.mbt#L23)
and [CLI extension consumer](https://github.com/finos/morphir-moonbit/blob/89f892468649bc6fef6acc40e5bfb2e9800c16da/apps/morphir/cli/extension.mbt).
The released parser accepts a printable token up to 128 characters. This audit
identifies the host; it does not claim that host has adopted the new grammar,
shared installer or doctor rules. The parent's older recorded MoonBit pin remains
unchanged. Host adoption and pin movement remain group 3 work.

## Pinned ids and formats

The pin file is `.config/published-extension-bundles.toml` at the cutoff. These
are descriptor and claims format versions, distinct from extension release versions.

| Pin | Repository and release tag | Published id | Descriptor | Claims |
| --- | --- | --- | --- | --- |
| avro | finos/morphir-extensions `extension/avro/v0.4.0` | `morphir-avro` | `2.0.0-draft.2` | `0.1.0-draft.2` |
| openapi | finos/morphir-extensions `extension/openapi/v0.5.0` | `morphir-openapi` | `2.0.0-draft.2` | `0.1.0-draft.2` |
| python | finos/morphir-python `extension/python/v0.6.0` | `morphir-python` | `2.0.0-draft.2` | `0.1.0-draft.2` |
| rust | finos/morphir-rust `extension/rust/v0.4.0` | `morphir-rust` | `2.0.0-draft.2` | `0.1.0-draft.2` |
| elm | finos/morphir-elm `extension/elm/v0.4.1` | `morphir-elm` | Bundle descriptor `2.0.0-draft.2`; legacy descriptor integer `1` | Bundle claims `0.1.0-draft.2` |
| scala-elm | finos/morphir-scala `v0.5.0-M13` | `morphir-scala-elm` | `2.0.0-draft.2` | `0.1.0-draft.2` |

The Rust manifest at the recorded pin,
[`extensions.toml`](https://github.com/finos/morphir-rust/blob/c9f79da9d2fdd3ae59347cefe057f89f01810d37/.github/extensions.toml),
also names `morphir-elm-native` and `morphir-rust`. Released descriptor assets
across the inspected repositories additionally name `morphir-elm-classic` and
`morphir-gleam`. Every one of these ids passes the published id schema. Their
release versions and exact asset sources are in `metadataAssets` in the evidence.
The `.tgz` and raw-executable process shapes remain separate in the package cases.

## Result and limits

Both PKGVER-A conditions held at approval. Publish all seven schemas once under
`website/static/schemas/extensions/0.1.0-preview.1/`, with package members in
release, index-record, catalog and lock. Each `$id` and document `$schema` uses
its exact `https://morphir.finos.org/schemas/extensions/0.1.0-preview.1/` URL.
The package manifest header uses the same version. PKGVER-B remains in the
approved design as historical conditional text; it was not selected.

These observations establish publication history and structural inputs. They do
not qualify a host, execute an installer, authenticate a publisher or replace a
release check. Tagged source and package bytes were inspected without running
them. Metadata updated after approval would require historical evidence rather
than an assumption; none of the inspected metadata assets has such a timestamp.
Existing published assets and signed toolchain fixtures were not changed.
