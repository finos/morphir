# Tasks

Tracking: follows `move-cli-delivery-to-umbrella` (finos/morphir#1153). No Beads issue on this machine.

## 1. Build and assemble from the source

- [x] 1.1 Call the pinned source's `morphirup-build.yml` for each morphirup platform, with `toolchain: true`, `repository`, `ref` and `upload-host-offering`. Bind both source workflows to the pin and its literal `ref`. Verified by the routing and binding tests in `tools/cli-release.test.ts`.
- [x] 1.2 Take the self-contained offering of each toolchain platform from the toolchain job, and stop building it with `cli-offering.yml` there (HOST-1). Verified by the offering matrix test and `prepareRelease`'s host-name check.
- [x] 1.3 Assemble the assets with the source's `FlattenReleaseAssets`, `MorphirupChecksums` and `WindowsToolchainChecksums` from the pinned checkout, and read both checksum files back. Verified by the publish-job test, and locally on the published `v0.5.0-alpha.1` files, where both checksum files came out byte-identical to that release's.
- [x] 1.4 Land the source's `morphirup-build.yml` inputs (`repository`, `ref`, `upload-host-offering`) in finos/morphir-dotnet and move the pin to a commit that has them. The pin is `dc5b9015`, the 0.5.0-alpha.2 release commit, which has #649 and #648. Both source-interface tests pass at it.

## 2. Qualify and record

- [x] 2.1 Qualify each manager on its own platform: `--version` with no .NET on the path, and the archive's executable. Verified by `qualifyMorphirup` tests against a real executable, and locally on the published `morphirup-win-arm64.exe`.
- [x] 2.2 Require the exact contract names, every checksum entry and each host archive's offering bytes in the manifest step, and record the assets, the qualifications and the setup journey. Verified by the asset, evidence and end-to-end tests.
- [ ] 2.3 Dry-run the release from a branch at a pin that has the source inputs, and record the run and its `publishable` result.

## 3. Review of #1172

- [x] 3.1 Refuse publication unless every `morphir-toolchain-<rid>.json` is of local-toolchains `0.1.0-preview.5` or later and downloads each asset from `https://github.com/finos/morphir/releases/download/<tag>/<name>`, with `<name>` attached and its SHA-256. Verified by the bundle tests, including the 0.1.0-preview.4 bundles the pin `318b1bfd` writes.
- [x] 3.2 Check the pinned source's interface: every `with:` key `release.yml` passes is declared by that workflow, and `morphirup-build.yml` uploads `morphir-dotnet-self-contained-<rid>` for exactly the toolchain platforms. Release-info refuses to run otherwise. At the pin `318b1bfd`, both tests fail (the three new inputs are undeclared, and the host offering is never uploaded), and `source.candidate` marks the pin until it moves to the 0.5.0-alpha.2 release commit.
- [x] 3.3 Run the source's assembly in a read-only job (`assemble-morphirup`) with no token, and give `GH_TOKEN` only to the two `gh` steps of the publish job.
- [x] 3.4 Require `<release>+<full pinned commit>` from `morphirup --version`; a bare version fails.

## 4. Documentation

- [x] 4.1 Point `INSTALLING.md` and the website's Installation page at finos/morphir releases for morphirup, keeping the install scripts at finos/morphir-dotnet `main`. They say that `v0.5.0-alpha.2` is the first finos/morphir release with morphirup, and that `v0.5.0-alpha.1` has the CLI only.

## Workflow follow-up

- Release `v0.5.0-alpha.2` once the source cuts it with local-toolchains `0.1.0-preview.5`; then archive this change.