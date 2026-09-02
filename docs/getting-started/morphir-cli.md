---
id: morphir-cli
title: Morphir CLI
sidebar_label: Morphir CLI
sidebar_position: 5
---

# Morphir CLI

The **Morphir CLI** shipped from this repository is a Rust command-line tool for working with Morphir IR, configuration, distributions, and language bindings.

:::info Repository ownership
This CLI is built from [`crates/morphir`](https://github.com/finos/morphir/tree/main/crates/morphir) in **finos/morphir**.

For the Go-based Morphir CLI (including WIT pipeline commands), see **[Morphir Go](morphir-go-preview.md)** in [finos/morphir-go](https://github.com/finos/morphir-go).
:::

## Installation

Prebuilt binaries are published from [finos/morphir releases](https://github.com/finos/morphir/releases).

### Install with mise

```shell
mise use -g github:finos/morphir@0.4.0-alpha.5
```

To pin Morphir in a project's `mise.toml`:

```toml
[tools]
"github:finos/morphir" = "0.4.0-alpha.5"
```

Run `mise install` after changing the configuration. Prereleases must be selected explicitly.

### Install a release archive manually

Download the archive for your system from [GitHub Releases](https://github.com/finos/morphir/releases).

| System | Processor | Asset suffix |
| --- | --- | --- |
| Linux | x86-64 | `x86_64-unknown-linux-gnu.tgz` |
| Linux | ARM64 | `aarch64-unknown-linux-gnu.tgz` |
| macOS | Intel | `x86_64-apple-darwin.tgz` |
| macOS | Apple silicon | `aarch64-apple-darwin.tgz` |
| Windows | x86-64 | `x86_64-pc-windows-msvc.zip` |
| Windows | ARM64 | `aarch64-pc-windows-msvc.zip` |

Extract the `morphir` executable (or `morphir.exe` on Windows) and add it to your `PATH`.

See [INSTALLING.md](https://github.com/finos/morphir/blob/main/INSTALLING.md) in the repository for checksum verification and build-from-source instructions.

## Verify installation

```shell
morphir version
```

## Windows: enable long paths

A Morphir IR v4 document tree stores each type and value as its own file, nested under the package and module
names. Those paths get long, and Morphir writes them assuming long paths are available (a budget of 4000
characters, recorded in each distribution's manifest as `pathBudget`).

Windows can handle that, but **two separate switches** have to be turned on, and both are off by default. With
either one missing, checking out or building a document tree fails once a path passes 260 characters.

**1. Git.** Git for Windows ships with long paths disabled, independently of Windows itself:

```powershell
git config --global core.longpaths true
```

**2. Windows.** Set once per machine, from an administrator PowerShell, then sign out and back in:

```powershell
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -Value 1
```

Windows 10 version 1607 and later support this. Older versions cannot enable it. The registry switch only
affects programs that declare themselves long-path aware; `morphir.exe` does so in releases after 0.4.0-alpha.5.

### If you cannot enable long paths

Some machines are locked down and the registry change is not available. For that situation the format defines a
portable profile: a distribution written with `pathBudget: 200` in its manifest shortens any filename that would
overflow and records the mapping inside the module, so the tree still reads correctly. The cost is that a
shortened filename no longer looks like the name it holds.

```json
{
  "formatVersion": 4,
  "distribution": "Library",
  "package": "my-org/my-project",
  "pathBudget": 200
}
```

The CLI cannot produce such a tree yet: `morphir ir migrate` always writes with the default budget, and the
manifest is part of its output, so editing the file afterward does not change the filenames already chosen. A
`--path-budget` writer option is tracked as follow-up work. Until it lands, the practical workaround on a
constrained machine is to keep document trees close to the filesystem root so the package's own nesting fits
within 260 characters.

Every tree records the `pathBudget` it was written with, so a tool can compare it with what your machine handles
and report a mismatch up front rather than failing file by file. That check is planned for `morphir doctor` and is
not in the CLI yet; until then, a tree written with the default budget may fail to check out on a machine without
long paths enabled.

## Command overview

The Rust CLI includes:

| Command | Purpose |
| --- | --- |
| `morphir compile` | Compile source to Morphir IR |
| `morphir generate` | Generate code from Morphir IR |
| `morphir config` | Inspect effective configuration |
| `morphir tool` | Manage Morphir tools |
| `morphir dist` | Manage Morphir distributions |
| `morphir extension` | Manage Morphir extensions |
| `morphir gleam` | Gleam language binding commands |
| `morphir schema` | Generate JSON Schema for Morphir IR |
| `morphir version` | Print version information |

Run `morphir --help` for the current command list. Some commands are experimental and hidden unless you pass `--help-all`.

## Build from source

```shell
git clone --recurse-submodules https://github.com/finos/morphir.git
cd morphir
mise install
cargo build --locked --release --package morphir
```

The executable is written to `target/release/morphir` (or `target\release\morphir.exe` on Windows).

## Install an unsigned developer Desktop

Contributors can build and install Morphir Desktop without Apple, Windows, notarization, TUF, or
network credentials. From a `morphir-ui` checkout, run:

```shell
bun run --cwd apps/morphir-desktop package:developer
```

The portable package is written beneath `apps/morphir-desktop/release/`. Choose the host package
that the CLI can launch directly: `.zip` on Windows or macOS, and `.tar.gz` or `.AppImage` on
Linux. Read the exact version from `apps/morphir-desktop/package.json`, then install it explicitly:

```shell
morphir tool install desktop \
  --source <path-to-portable-package> \
  --channel developer \
  --version 0.1.0
```

`developer` is a local, unsigned trust policy. The CLI still hashes the source, applies package
size and safe-extraction limits, installs into the content-addressed store in Morphir Home, and
atomically records the exact version, digest, platform, launch path, and rollback state. It never
uses this policy for stable, preview, or developer-insider acquisition.

Inspect and maintain the installation with the same verified lifecycle used by later release
channels:

```shell
morphir tool list
morphir tool list --json
morphir tool update desktop --source <new-package> --channel developer --version <version>
morphir tool repair desktop --source <original-package>
morphir tool rollback desktop
morphir tool uninstall desktop
```

Repair requires the exact original package bytes. Uninstall removes the active selection and its
lock; content-addressed package bytes remain cache-owned and can be reclaimed with
`morphir cache clean`.

### Launch the installed Desktop

```shell
morphir desktop --offline --wait <workspace-directory-or-morphir-ir.json>
```

The CLI verifies the installed files, opens the selected workspace, and reports Desktop readiness.
`--wait` keeps the command running until Desktop closes and returns its exit status. Without it,
the CLI returns after startup. Logs beneath Morphir Home record the same launch ID. Desktop
records the CLI operation ID as its parent operation ID. The installed app does not need the
original ZIP or a source checkout.

The developer workflow requires the explicit local installation above. `--offline` never downloads
a missing release; it reports the installation command instead.

### Desktop installation paths on Windows

Desktop packages declare `longPathAware` for filesystem access. Electron's Chromium runtime still
uses a [fixed-size buffer for its own executable path](https://github.com/chromium/chromium/blob/main/base/base_paths_win.cc).
When that path reaches 260 UTF-16 code units, the CLI asks Windows for an existing short filename
and verifies that it resolves to the same installed executable before launching it. Package
verification remains unchanged; the CLI does not create aliases or change Windows settings.

If the volume has no usable short filename, the CLI reports the limit before starting Desktop.
Choose a shorter `MORPHIR_HOME` and install the package there, for example in PowerShell:

```powershell
$env:MORPHIR_HOME = 'C:\MorphirHome'
morphir tool install desktop --source <path-to-package.zip> --channel developer --version 0.1.0
morphir desktop --offline --wait <workspace-directory>
```

This selects a separate Home; it does not move or delete an existing installation. Keep the same
`MORPHIR_HOME` value for subsequent commands. Windows long-path support must still be enabled for
deep project files as described above.

### Run the developer Desktop demo

From an initialized checkout with Rust, Bun and native build tools installed:

```shell
mise run demo:desktop
```

This builds the CLI and an unsigned Desktop archive for the current platform, copies the Insight
sample model, and installs Desktop into a fresh temporary Morphir Home. Build and dependency
installation steps may use the network. No existing Morphir installation is changed.

The task opens the installed application with `--offline --wait`. Select `applyLambda` and inspect
its Insight and XRay views, then close the window. The task moves the original archive aside and
opens Desktop again offline. Close the second window to finish. Failed build, install or launch
commands stop the task and return their nonzero exit code.

The printed demo directory retains the copied CLI, sample model, installed files, logs and the
archive as `package.saved`. The task runs the installed CLI outside the checkout. It does not
disable networking or make the source checkout unreadable, so this is not an OS-isolation test.
Windows app-data and Linux XDG config directories are also redirected into the demo directory;
macOS may still use Electron's normal OS profile location.

To build and install without opening a window, or run the orchestration tests without building:

```shell
mise run demo:desktop -- --prepare-only
mise run test:desktop-demo
```

## Related tooling

| Tool | Repository | Use when |
| --- | --- | --- |
| **morphir-elm** | [finos/morphir-elm](https://github.com/finos/morphir-elm) | Production Elm authoring, visualization, and mature backends |
| **Morphir Go CLI** | [finos/morphir-go](https://github.com/finos/morphir-go) | Go-based CLI, WIT pipeline, Go code generation |
| **Morphir UI** | [finos/morphir-ui](https://github.com/finos/morphir-ui) | User-interface development for Morphir |

For stable production workflows today, continue using [morphir-elm](installation.md) unless your project specifically targets the Rust or Go CLIs.
