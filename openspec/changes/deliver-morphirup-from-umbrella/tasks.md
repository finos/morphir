# Tasks

Tracking: follows `move-cli-delivery-to-umbrella` (finos/morphir#1153). No Beads issue on this machine.

## 1. Build and assemble from the source

- [x] 1.1 Call the pinned source's `morphirup-build.yml` for each morphirup platform, with `toolchain: true`, `repository`, `ref` and `upload-host-offering`. Bind both source workflows to the pin and its literal `ref`. Verified by the routing and binding tests in `tools/cli-release.test.ts`.
- [x] 1.2 Take the self-contained offering of each toolchain platform from the toolchain job, and stop building it with `cli-offering.yml` there (HOST-1). Verified by the offering matrix test and `prepareRelease`'s host-name check.
- [x] 1.3 Assemble the assets with the source's `FlattenReleaseAssets`, `MorphirupChecksums` and `WindowsToolchainChecksums` from the pinned checkout, and read both checksum files back. Verified by the publish-job test, and locally on the published `v0.5.0-alpha.1` files, where both checksum files came out byte-identical to that release's.
- [ ] 1.4 Land the source's `morphirup-build.yml` inputs (`repository`, `ref`, `upload-host-offering`) in finos/morphir-dotnet and move the pin to a commit that has them.

## 2. Qualify and record

- [x] 2.1 Qualify each manager on its own platform: `--version` with no .NET on the path, and the archive's executable. Verified by `qualifyMorphirup` tests against a real executable, and locally on the published `morphirup-win-arm64.exe`.
- [x] 2.2 Require the exact contract names, every checksum entry and each host archive's offering bytes in the manifest step, and record the assets, the qualifications and the setup journey. Verified by the asset, evidence and end-to-end tests.
- [ ] 2.3 Dry-run the release from a branch at a pin that has the source inputs, and record the run and its `publishable` result.

## 3. Documentation

- [x] 3.1 Point `INSTALLING.md` and the website's Installation page at finos/morphir releases for morphirup, keeping the install scripts at finos/morphir-dotnet `main`.

## Workflow follow-up

- Release `v0.5.0-alpha.2` once the source cuts it with local-toolchains `0.1.0-preview.5`; then archive this change.