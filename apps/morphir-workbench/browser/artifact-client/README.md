This directory contains the pure artifact-transfer boundary from
[`@morphir/workspace`](https://github.com/finos/morphir-ui/tree/main/packages/morphir-workspace).
`SOURCE.json` records the exact upstream revision, source paths and SHA-256 values.
The Apache and Unicode license notices are retained. The files are unchanged from
upstream, including their relative imports. Bun resolves the pinned `@std/semver`
npm alias through the Workbench package and lockfile.

The current pin is the published review candidate in upstream PR #47. Replace it
with the verified merged revision before landing the Workbench transfer feature.
These decoders validate metadata and chunks. The Workbench controller separately
owns complete byte verification, lifecycle cleanup and downloads.

Check the copy without a network connection:

```shell
mise run workbench:artifact-source-check
```

Reproduce it from an official upstream checkout after reviewing a pin change:

```shell
moonx scripts/artifact-client-source.mbtx sync /path/to/morphir-ui
moonx scripts/artifact-client-source.mbtx verify-upstream /path/to/morphir-ui
```

Both upstream modes read the exact pinned Git objects. They validate the complete
source inventory and hashes before writing any file. The normal Workbench build
and test tasks check the copied bytes.
