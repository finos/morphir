# Installing Morphir

The Morphir CLI comes from [finos/morphir-dotnet](https://github.com/finos/morphir-dotnet). This repository
builds it from a pinned commit of that source, launches every produced artifact on its own platform, and publishes
the official releases on [finos/morphir releases](https://github.com/finos/morphir/releases) under tags
`v<version>`. Each release carries a `release-manifest.json` that names the source commit, the compatibility kit
and the SHA-256 of every asset.

The `v*` tags up to `v0.4.0-beta.12` are releases of the earlier Rust CLI (see [The Rust CLI](#the-rust-cli)). Every
.NET release is newer than all of them.

To set up a project's whole toolchain (the CLI and its F# frontend and backend) in one step, use the experimental
[`morphirup`](#set-up-a-project-with-morphirup-experimental) manager instead.

## Choose an offering

| Offering | What you get | Needs |
| --- | --- | --- |
| `native-aot` | One native `morphir` executable | No .NET installation; the operating system libraries below. No in-process F# frontend. |
| `self-contained` | A folder with the `morphir` apphost and its own .NET runtime | No .NET installation; the operating system libraries below. Includes the F# frontend. |
| `framework-dependent` | A folder with the `morphir` apphost | An installed .NET 11 runtime (`Microsoft.NETCore.App` 11.x) and its prerequisites. Includes the F# frontend. |
| `dotnet-tool` | The `Morphir.Tool` package, command `dotnet-morphir` | The .NET 11 SDK (11.0.100 or later) to install it. |

Platforms: Windows x64 and ARM64, macOS x64 and ARM64, and Linux (glibc) x64 and ARM64. Before a release is
published, each offering is started on each platform the way you start it, with `--version`, `--help` and
`morphir ir verify` on a packaged example. The release manifest records the result for every offering and platform.

### Operating system prerequisites

What is known, and what is not measured yet (from finos/morphir-dotnet's own analysis in
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
keep working for win-x64, win-arm64, osx-arm64, linux-x64 and linux-arm64 (there are none for osx-x64). In releases from this repository those names
carry the same Native AOT executable as the `native-aot` offering. Assets already published under them are
unchanged.

## Install the .NET tool

```shell
dotnet tool install --global Morphir.Tool --prerelease
dotnet-morphir --version
dotnet morphir --version
```

Leave out `--prerelease` to get the latest stable release once there is one. To install the package from a release
instead of a feed, download `Morphir.Tool.<version>.nupkg` into a folder and add
`--add-source <folder> --version <version>`.

## Set up a project with morphirup (experimental)

`morphirup` is the Morphir toolchain manager: one native executable that needs no .NET installation. In a project,
`morphirup setup` downloads the Morphir host and the F# frontend and backend of one release, checks each file's size
and SHA-256 against that release's `SHA256SUMS`, and installs them under your Morphir Home (`MORPHIR_HOME`, or
`~/.morphir`). `morphirup run` then runs them with no network access.

Release setup works on Windows x64, Windows ARM64 and macOS ARM64 (Apple silicon). Intel macOS is not supported.

`morphirup` and its toolchains are published on the
[finos/morphir-dotnet releases](https://github.com/finos/morphir-dotnet/releases), not on this repository's
releases. From the release of the version you want, download the manager for your platform
(`morphirup-win-x64.exe`, `morphirup-win-arm64.exe` or `morphirup-osx-arm64`) and `morphirup-v<version>.sha256`.
Check the manager's SHA-256 against its line in that file, rename it to `morphirup` (`morphirup.exe` on Windows) and put it on `PATH`.
Then, in your project:

```shell
morphirup setup --dry-run
morphirup setup --yes
morphirup run -- compile
morphirup run -- generate --target fsharp --output generated
```

`setup` installs the toolchain of the manager's own version, unless `.morphir/toolchain.toml` asks for an exact
version. `--dry-run` shows the plan and changes nothing.

The checksums show that each download is the file the release lists. They do not authenticate the publisher: setup
trusts the finos/morphir-dotnet release it downloads from. The
[morphirup guide](https://github.com/finos/morphir-dotnet/blob/main/docs/content/docs/cli/morphirup.md) covers every
option, the local-developer route and what is not implemented yet.

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
the Rust CLI releases (`0.4.0-beta.7` and later take `extension/python/v0.4.0`). The .NET CLI runs the Python
extension experimentally, through `extensions.python.path` in the project configuration, with
`morphir compile --language python` and `morphir generate --target python`. It does not run WASM extensions on
Windows x64.

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
