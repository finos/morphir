# Installing Morphir

The Morphir CLI comes from [finos/morphir-dotnet](https://github.com/finos/morphir-dotnet). This repository
builds it from a pinned commit of that source, launches every produced artifact on its own platform, and publishes
official releases under tags `v<version>`, the namespace the Rust CLI's releases used; a new release must be newer than every existing `v*` release. Each release carries a `release-manifest.json` that names the
source commit, the compatibility kit and the SHA-256 of every asset.

The first official .NET release has not been published yet, and its version is not decided. Until it is, install from the
[finos/morphir-dotnet releases](https://github.com/finos/morphir-dotnet/releases) or the `Morphir.Tool` package.

## Choose an offering

| Offering | What you get | Needs |
| --- | --- | --- |
| `native-aot` | One native `morphir` executable | No .NET installation; the operating system libraries below. No in-process F# frontend. |
| `self-contained` | A folder with the `morphir` apphost and its own .NET runtime | No .NET installation; the operating system libraries below. Includes the F# frontend. |
| `framework-dependent` | A folder with the `morphir` apphost | An installed .NET 10 runtime and its prerequisites. Includes the F# frontend. |
| `dotnet-tool` | The `Morphir.Tool` package, command `dotnet-morphir` | The .NET 10 SDK to install it. |

Platforms: Windows x64 and ARM64, macOS x64 and ARM64, and Linux (glibc) x64 and ARM64. No offering is
production-qualified yet: the official release workflow has not run, and the pinned source is an unreleased
candidate.

### Operating system prerequisites

What is known, and what is not measured yet, for the pinned source (from finos/morphir-dotnet's own analysis in
[#584](https://github.com/finos/morphir-dotnet/pull/584)):

- **Linux.** The executables use ICU for globalization (the pinned build does not set invariant mode), so expect to
  need `libicu`. They reach OpenSSL (`libssl`, `libcrypto`) for SHA-256 hashing and for HTTPS, and HTTPS also needs CA
  certificates. Whether each offering starts without these in a clean image has not been measured for the pinned
  source.
- **glibc floor: unqualified.** No floor is stated for these artifacts. A probe of a build without the WASM engine,
  linked in `ubuntu:22.04`, measured glibc 2.34; a separate branch with the WASM engine, linked on Ubuntu 24.04,
  measured 2.38. Neither measured the artifacts of the pinned source, and the release workflow links on its
  runners. musl-based Linux is not supported.
- **macOS.** The artifacts are not signed with a Developer ID and not notarized; the pinned build has no signing
  step. Gatekeeper may refuse a downloaded executable until you allow it. The minimum macOS version is not measured.
- **Windows.** The executables are not Authenticode-signed, so SmartScreen may warn on first run.

## Install a release archive

Download the archive for your offering and platform from the release:

```text
morphir-dotnet-<version>-<offering>-<rid>.zip      Windows (win-x64, win-arm64)
morphir-dotnet-<version>-<offering>-<rid>.tar.gz   macOS (osx-x64, osx-arm64) and Linux (linux-x64, linux-arm64)
```

Files sit at the archive root. Extract the archive into a folder of its own and run `morphir` (`morphir.exe` on
Windows) from there, or put that folder on `PATH`. Keep the whole folder for `self-contained` and
`framework-dependent`: the apphost loads the files beside it.

Check the download against the release manifest before you extract it:

```shell
sha256sum morphir-dotnet-<version>-native-aot-linux-x64.tar.gz      # Linux
shasum -a 256 morphir-dotnet-<version>-native-aot-osx-arm64.tar.gz   # macOS
```

```powershell
(Get-FileHash morphir-dotnet-<version>-native-aot-win-x64.zip -Algorithm SHA256).Hash.ToLower()
```

Then check the installation:

```shell
morphir --version
```

### Earlier asset names

Links and scripts that fetch `morphir-<rid>` (`morphir-<rid>.exe` on Windows) or `morphir-<rid>-v<version>.tar.gz`
keep working for win-x64, osx-arm64, linux-x64 and linux-arm64. In releases from this repository those names
carry the same Native AOT executable as the `native-aot` offering. Assets already published under them are
unchanged.

## Install the .NET tool

```shell
dotnet tool install --global Morphir.Tool
dotnet-morphir --version
dotnet morphir --version
```

To install the package from a release instead of a feed, download `Morphir.Tool.<version>.nupkg` into a folder and
add `--add-source <folder> --version <version>`.

## The Rust CLI

The Rust `morphir` CLI that this repository used to build was deleted on 10 November 2026. Its releases up to
[`v0.4.0-beta.12`](https://github.com/finos/morphir/releases/tag/v0.4.0-beta.12) stay downloadable and unchanged,
but they receive no updates. They speak only MEP `0.1`, so they cannot list a Morphir Home that a current host
has installed into.

## Install the Python extension

The CLI ships separately from language extensions. [finos/morphir-python](https://github.com/finos/morphir-python)
owns the `morphir-python` WASM extension and publishes `extension/python/v<version>` bundles; bundles up to
`extension/python/v0.4.0` stay in the [finos/morphir-rust releases](https://github.com/finos/morphir-rust/releases).
The installation notes in the
[Python extension guide](https://github.com/finos/morphir-python/blob/main/docs/python-extension.md) were written for
the Rust CLI releases (`0.4.0-beta.7` and later take `extension/python/v0.4.0`). Running WASM extensions in the .NET
CLI is separate, unfinished work.

finos/morphir-python also packages the same compiler for Python: `pip install morphir-python` gives a Python API and
a `morphir-python` command that compile and generate without the Morphir CLI. See the
[Python compiler guide](https://github.com/finos/morphir-python/blob/main/docs/python-compiler.md).

## Build from source

Build the CLI in [finos/morphir-dotnet](https://github.com/finos/morphir-dotnet); its README covers the .NET SDK and
the build. An official offering is built with that repository's release profile, for example:

```shell
dotnet run --project build/_build.csproj -- --target PackRelease --deployment native-aot --rid linux-x64
```

This repository's own Rust crates are development tools (`morphir-mck`, `morphir-dev`), not the CLI. See
[DEVELOPING.md](DEVELOPING.md).
