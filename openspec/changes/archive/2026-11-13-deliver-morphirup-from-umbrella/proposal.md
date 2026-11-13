# Proposal

## Why

The official Morphir CLI is released from finos/morphir (`v0.5.0-alpha.1`), but `morphirup`, the toolchain manager, and the setup toolchains it installs are still published only on finos/morphir-dotnet releases. A user who installs Morphir from finos/morphir has to fetch the manager from another repository. morphirup's built-in release source is moving to `https://github.com/finos/morphir` at tag `v<version>` (local-toolchains `0.1.0-preview.5`). From then on, a finos/morphir release has to carry the manager and the toolchains, under exactly the names that source reads.

For example, `morphirup setup --yes` on Windows ARM64 reads `morphir-toolchain-win-arm64.json` from the release and installs `morphir-dotnet-0.5.0-alpha.2-self-contained-win-arm64.zip` and the F# frontend and backend that the bundle names. It checks each file against `SHA256SUMS`. Every one of those names has to be on the finos/morphir release `v0.5.0-alpha.2`, with the bytes the bundle names.

## What Changes

- A finos/morphir release `v<version>` attaches the morphirup and setup-toolchain assets of the pinned source, with the names a finos/morphir-dotnet release of that version gives them:
  - `morphirup-<rid>[.exe]` and `morphirup-<rid>-v<version>.tar.gz` for linux-x64, linux-arm64, win-x64, win-arm64 and osx-arm64;
  - `morphirup-v<version>.sha256` and `morphirup-v<version>-THIRD-PARTY-NOTICES.txt`;
  - for win-x64, win-arm64 and osx-arm64: the self-contained host archive, the F# frontend and backend archives with their `.release.json` and `.manifest`, `morphir-host-candidate-<rid>.json`, `morphir-extensions-<rid>.json` and `morphir-toolchain-<rid>.json`;
  - one `SHA256SUMS` over the toolchains.
- They are built by the pinned source's own `morphirup-build.yml`, which also runs the source's acquired setup journey on the toolchain platforms. They are assembled by the source's own `FlattenReleaseAssets`, `MorphirupChecksums` and `WindowsToolchainChecksums` targets. Nothing is re-implemented here.
- On a toolchain platform, the self-contained offering is the toolchain's host archive: the same name, so one file, with the bytes the toolchain names.
- Each manager is qualified on its own platform, and the manifest records the assets, the qualifications and the setup journey.
- The install instructions point at finos/morphir releases for morphirup.

## Capabilities

### New Capabilities
- `cli/morphirup-delivery`: delivery of morphirup and the setup toolchain in finos/morphir releases, built from the pinned source.

### Modified Capabilities

## Tracking

Follows the archived `move-cli-delivery-to-umbrella` (finos/morphir#1153). The source side is the `morphirup-build.yml` inputs `repository`, `ref` and `upload-host-offering` in finos/morphir-dotnet, and local-toolchains `0.1.0-preview.5`, which names finos/morphir as the release source. No Beads issue is created on this machine.