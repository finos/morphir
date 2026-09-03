# Installing Morphir

This repository publishes the Morphir CLI as a prebuilt executable for Linux,
macOS, and Windows. Both x86-64 and ARM64 packages are available.

## Install with mise

[mise](https://mise.jdx.dev/) can download the correct executable from the
Morphir GitHub release for your operating system and processor.

Install the current prerelease globally:

```shell
mise use -g github:finos/morphir@0.4.0-alpha.6
```

To pin Morphir in a project's `mise.toml`, add:

```toml
[tools]
"github:finos/morphir" = "0.4.0-alpha.6"
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
