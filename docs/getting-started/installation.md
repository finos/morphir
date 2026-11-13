---
id: installation
title: Installation
sidebar_position: 2
---
# Installation

Morphir has two sets of command-line tools:

- **The Morphir CLI**, `morphir`, from [finos/morphir-dotnet](https://github.com/finos/morphir-dotnet). It compiles
  models to the Morphir IR, generates code and works with Morphir distributions.
- **The Elm tooling**, `morphir-elm`, from [finos/morphir-elm](https://github.com/finos/morphir-elm). It compiles
  Elm models and runs the Morphir developer UI. The tutorials on this site use it.

## The Morphir CLI

The quickest way to start is `morphirup`, the Morphir toolchain manager. It installs the CLI and its F# frontend and
backend for a project, and needs no .NET installation. Install it with the script for your system.

On macOS, or on Linux (install only; see below):

```shell
curl -fsSL https://raw.githubusercontent.com/finos/morphir-dotnet/main/scripts/install-morphirup.sh | sh
```

On Windows:

```powershell
irm https://raw.githubusercontent.com/finos/morphir-dotnet/main/scripts/install-morphirup.ps1 | iex
```

The script downloads `morphirup` from the newest finos/morphir-dotnet release and installs it only if its SHA-256
matches the release's checksum file. Then, in your project:

```shell
morphirup setup --yes
morphirup run -- compile
```

`morphirup setup` works on Windows x64, Windows ARM64 and macOS on Apple silicon, and is experimental. On Linux the
script installs `morphirup`, but `setup` is not supported yet. On Linux, on Intel macOS, or to install `morphir` on
its own, download a release archive or install the `Morphir.Tool` .NET tool.
[Installing Morphir](https://github.com/finos/morphir/blob/main/INSTALLING.md) covers every option, the platforms
and the system requirements.

Check the installation:

```shell
morphir --version
```

## The Elm tooling

`morphir-elm` is delivered through `npm`, so it needs [Node.js and npm](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm).
To install it, run:

```shell
npm install -g morphir-elm
```

### Setup
The Elm tooling reads a configuration file called `morphir.json` in the project
root directory with the following structure:

```
{
    "name": "My.Package",
    "sourceDirectory": "src"
}
```

An optional section can be added to specify a subset of modules to be used by Morphir:

```
{
    "name": "My.Package",
    "sourceDirectory": "src",
    "exposedModules": [
        "Module",
        "OtherModule"
    ]
}
```

[Installation and usage](installation-and-usage.md) describes the `morphir-elm` commands.
