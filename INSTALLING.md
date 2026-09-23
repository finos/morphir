# Installing Morphir

This repository publishes the Morphir CLI as a prebuilt executable for Linux,
macOS, and Windows. Both x86-64 and ARM64 packages are available.

## Install with mise

[mise](https://mise.jdx.dev/) can download the correct executable from the
Morphir GitHub release for your operating system and processor.

Install the current prerelease globally:

```shell
mise use -g github:finos/morphir@0.4.0-beta.4
```

To pin Morphir in a project's `mise.toml`, add:

```toml
[tools]
"github:finos/morphir" = "0.4.0-beta.4"
```

Run `mise install` after changing the configuration. Prereleases must be
selected explicitly. A request for `latest` does not select them by default.

Check the installation:

```shell
morphir version
```

## Install a release archive manually

Download the archive for your system from
[GitHub Releases](https://github.com/finos/morphir/releases).

| System | Processor | Asset suffix |
| --- | --- | --- |
| Linux | x86-64 | `x86_64-unknown-linux-gnu.tgz` |
| Linux | ARM64 | `aarch64-unknown-linux-gnu.tgz` |
| macOS | Intel | `x86_64-apple-darwin.tgz` |
| macOS | Apple silicon | `aarch64-apple-darwin.tgz` |
| Windows | x86-64 | `x86_64-pc-windows-msvc.zip` |
| Windows | ARM64 | `aarch64-pc-windows-msvc.zip` |

Each archive contains one executable named `morphir`, or `morphir.exe` on
Windows. Extract it and move it to a directory on `PATH`.

Linux and macOS:

```shell
mkdir -p "$HOME/.local/bin"
tar -xzf morphir-<version>-<target>.tgz
install -m 0755 morphir "$HOME/.local/bin/morphir"
```

Windows PowerShell:

```powershell
Expand-Archive morphir-<version>-<target>.zip
Move-Item .\morphir.exe $env:LOCALAPPDATA\Microsoft\WindowsApps\morphir.exe
```

The release also includes a `.sha256` file for every archive. Verify the
download before extracting it:

```shell
# Linux
sha256sum -c morphir-<version>-<target>.tgz.sha256

# macOS
shasum -a 256 -c morphir-<version>-<target>.tgz.sha256
```

```powershell
$expected = (Get-Content morphir-<version>-<target>.zip.sha256).Split()[0]
$actual = (Get-FileHash morphir-<version>-<target>.zip -Algorithm SHA256).Hash
if ($actual -ne $expected) { throw "Checksum verification failed" }
```

## Install the Python extension

The CLI ships separately from language extensions. With CLI `0.4.0-beta.1` or
later, install the `morphir-python` WASM bundle `extension/python/v0.2.0` to compile
supported Python ADTs, fixed tuples, conditional functions, typed calls and unary
lambdas to Morphir IR v3 or v4 and generate Python. The earlier `v0.1.0` bundle does
not compile with this CLI.
See the [Python extension installation guide](https://github.com/finos/morphir-rust/blob/main/docs/tutorials/python-extension.md)
for download, repository publication and installation commands, and the
[binding README](https://github.com/finos/morphir-rust/blob/main/crates/morphir-python-binding/README.md)
for the supported subset and conformance limits.

## Build from source

Building from source requires Git, [mise](https://mise.jdx.dev/), and the
platform build tools required by Rust.

```shell
git clone --recurse-submodules https://github.com/finos/morphir.git
cd morphir
mise install
cargo build --locked --release --package morphir
```

The executable is written to `target/release/morphir` on Linux and macOS, or
`target\release\morphir.exe` on Windows.

### Windows: MSVC Spectre-mitigated libs

`cargo build`, `cargo test`, and `cargo clippy` fail on Windows with this error if your
Visual Studio install is missing an optional component:

```
error: failed to run custom build command for `msvc_spectre_libs v0.1.3`

  cargo:warning=No spectre-mitigated libs were found. Please modify the VS Installation to add these.

  thread 'main' panicked at msvc_spectre_libs-0.1.3/build.rs:38:13:
  No spectre-mitigated libs were found. Please modify the VS Installation to add these.
```

The CLI's embedded Rego evaluator (`morphir-opa`, via `regorus`) depends on the
`msvc_spectre_libs` crate, which requires the **Spectre-mitigated MSVC libraries**.
Either install the **"MSVC v143 - VS 2022 C++ x64/x86 Spectre-mitigated libs
(Latest)"** component from the Visual Studio Installer, or skip it entirely with
`cargo build --no-default-features --package morphir`, which drops `regorus` from
the dependency graph (and disables `morphir eval`'s Rego provider along with
itest's Rego-backed assertions). See [DEVELOPING.md](DEVELOPING.md#prerequisites)
for the elevated-install one-liner and [issue #886](https://github.com/finos/morphir/issues/886)
for the full analysis.
