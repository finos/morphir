# Native CLI acquisition with mise

The native distribution lets a user install Morphir through mise and run
built-in commands without a MoonBit or Node installation. For example, a demo
directory can contain a `mise.toml` that selects the GitHub prerelease and a
`demo.scm` containing `(+ 40 2)`. `mise install` acquires the archive;
`mise exec -- morphir worksheet demo.scm --isolated --discovery-boundary . --json`
returns a worksheet observation with integer value `42`.

The initial demo prerelease is qualified on macOS 26.6.2 arm64. Its scope does
not establish macOS 15 support. Generic macOS 15 artifacts must come from the
existing macOS 15 headless lane and pass installation there. The Mooncakes and
Moonx release keeps its separate qualification and publication requirements.

## User configuration

The [published demo prerelease](https://github.com/finos/morphir-moonbit/releases/tag/v0.1.0-demo.1)
can be installed in a demo directory with:

```sh
mise use 'github:finos/morphir-moonbit[prerelease=true,bin_path=bin]@0.1.0-demo.1'
mise exec -- morphir --help
```

Both this command and the following explicit configuration were verified with
fresh private mise directories against the public GitHub asset. The attached
[public installation receipt](https://github.com/finos/morphir-moonbit/releases/download/v0.1.0-demo.1/public-mise-receipt.json)
records the installed executable hash and Node/Moon-free functional checks.

To select the asset and pin its checksum explicitly, use:

```toml
[tools."github:finos/morphir-moonbit"]
version = "0.1.0-demo.1"
prerelease = true
asset_pattern = "morphir-moonbit-0.1.0-demo.1-macos-arm64.zip"
bin_path = "bin"
checksum = "sha256:a04771ea6ff98d2ee93c62fa8a717f2db330d04ddacc1496db86389e68806206"
```

Run `mise install`, then `mise exec -- morphir --help` or
`mise exec -- morphir version --json`. The GitHub release also carries
`SHA256SUMS` and a manifest. The
[official GitHub backend reference](https://mise.jdx.dev/dev-tools/backends/github.html)
documents asset selection, checksums and prerelease selection.

The archive contains `bin/morphir`, the application license and notices,
dependency license texts and `release-manifest.json`. A native binary does not
provision execution compilers, SDKs, providers or connected-service helpers.
Commands that require those components keep their existing explicit
prerequisites. The demo's built-in worksheet operation needs none of them.

## Prepare and verify an archive

Build the release executable using the pinned toolchain, then package the exact
file whose behavior was qualified:

```sh
mise exec -- moon build apps/morphir --target native --release
mise run test:release:native
mise run release:native:package -- --binary _build/native/release/build/finos/morphir/morphir.exe --directory .dev/native-cli-release --version 0.1.0-demo.1 --json
mise run release:native:verify -- --directory .dev/native-cli-release --json
```

Packaging records the source commit, distribution and application versions,
compiler/core identity, actual host and binary deployment information, file
hashes, and producer run/attempt where available. It refuses an invalid source
identity, unsupported binary or unsafe archive content. A binary's declared
deployment target alone is not runtime qualification on that operating system.

The output directory contains one
`morphir-moonbit-VERSION-macos-arm64.zip`, `manifest.json`, `SHA256SUMS` and,
after verification, `mise-install-receipt.json`. The verifier checks archive
identity and installs from it through mise in fresh temporary directories
outside the checkout. It exercises help, version, a worksheet returning `42`
and a structured failure, including native checks without Node or MoonBit on
`PATH`. An HTTP file acquisition check is local archive evidence. Actual public
GitHub acquisition must also pass after publication.

The `notices` command exports the same resolved CLI dependency and stock-core
license collection for other CLI distributions, including the Node payload
carried by Moonx. Run it from the source workspace with the selected MoonBit
toolchain home and a new output directory:

```sh
mise exec -- moon run scripts/native-cli-release.mbtx -- notices --directory .dev/cli-notices --json
```

It creates `licenses/` and `notices.json`. The notice inventory uses
`profile: "morphir/cli-notices"` and `contractVersion: "0.1.0"`, with resolved
module names, versions and licenses, plus each notice's relative `path`,
`bytes`, `sha256` and `mode`. Existing output is refused and preserved.
An incomplete new output directory is removed before a write failure is
reported. This inventory describes notices; it does not qualify an executable.

All script commands, `package`, `verify`, `notices` and `self-test`, support
`--json`, as does help. JSON mode emits one `morphir/command-result` document
with `contractVersion: "0.1.0"`, a stable `command`, `state`, `exitCode` and
`diagnostics`. Success includes `result`; failure includes
`error: {code, message}`. Child progress and diagnostics use stderr. Syntax
errors use `arguments.invalid` and exit 2. Validation refusals use
`distribution.invalid` and exit 1; child failures use `child.failed` and retain
the child's reported status. Success is emitted only after required outputs
finish. These commands do not upload or publish.

## Promote tested bytes

Commit and review the candidate, complete its source checks, and retain the
package and installation evidence. A demo prerelease needs authorization for
its declared assurance scope; the first macOS arm64 preview has that explicit
maintainer approval. Final-release gates remain in force for the final release.

The existing macOS arm64 headless job packages and verifies its exact native
test executable before uploading the four public outputs. Its artifact name
includes source SHA, run and attempt. Promote those bytes when using that
producer. The Linux/Zig cross-built macOS artifact is a different producer and
does not inherit qualification from a locally compiled macOS executable.

Create the labelled prerelease at the manifest's source commit and attach the
archive, manifest, checksums and installation receipt. Keep the distribution
version consistent with its tag. Native preview tags are excluded from the
stable-only Mooncakes workflow. Do not move an existing tag or replace an
existing asset with different bytes.

Finally, acquire the actual public release using the GitHub backend and fresh
mise directories outside the repository. Compare the downloaded and installed
hashes with the approved manifest and repeat the demo operations. Record the
release URL, immutable source SHA, public asset digest and actual results in
`morphir-ukvn.5.88.5`. A published preview and a local file installation do not
complete the separate final Mooncakes/Moonx release goal.
