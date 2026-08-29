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

## Related tooling

| Tool | Repository | Use when |
| --- | --- | --- |
| **morphir-elm** | [finos/morphir-elm](https://github.com/finos/morphir-elm) | Production Elm authoring, visualization, and mature backends |
| **Morphir Go CLI** | [finos/morphir-go](https://github.com/finos/morphir-go) | Go-based CLI, WIT pipeline, Go code generation |
| **Morphir UI** | [finos/morphir-ui](https://github.com/finos/morphir-ui) | User-interface development for Morphir |

For stable production workflows today, continue using [morphir-elm](installation.md) unless your project specifically targets the Rust or Go CLIs.
