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
mise use -g github:finos/morphir@0.4.0-beta.8
```

To pin Morphir in a project's `mise.toml`:

```toml
[tools]
"github:finos/morphir" = "0.4.0-beta.8"
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

### Suppress the banner

Help, `--version`, and running `morphir` without a command show a banner by
default. Use the global `--no-banner` flag to hide it, including with nested
command help:

```shell
morphir --no-banner --version
morphir mck --no-banner --help
```

Set `MORPHIR_NO_BANNER=true` to suppress it across invocations, or configure
the preference in `morphir.toml`:

```toml
[cli]
banner = false
```

The flag takes precedence over `MORPHIR_NO_BANNER`, which takes precedence
over configuration. The environment variable accepts `true` or `false`,
ignoring case and surrounding whitespace. `false` enables the banner even
when configuration disables it; an invalid value is ignored.

Configuration uses the normal machine, user, project, and local user override
layers, including YAML files. The standard environment spelling
`MORPHIR_CLI__BANNER=false` also works through that configuration layer.
If configuration cannot be discovered or loaded, or `cli.banner` is not a
boolean, the banner defaults to enabled. Help and version remain available
when a project's configuration is broken; `--no-banner` and
`MORPHIR_NO_BANNER` still work.

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
| `morphir gleam` | Native Gleam compilation and generation |
| `morphir schema` | Generate JSON Schema for Morphir IR |
| `morphir version` | Print version information |

Run `morphir --help` for the current command list. Some commands are experimental and hidden unless you pass `--help-all`.

## Native Elm provider (`morphir-elm-native`)

`morphir compile` selects the frontend that compiles a language through the
`--extension` flag. By default, compiling Elm sources uses the `morphir-elm`
extension, the mature JavaScript frontend that ships from
[finos/morphir-elm](https://github.com/finos/morphir-elm) and produces both
types and values. This repository also ships an experimental, built-in native
Elm frontend, `morphir-elm-native`, written in Rust.

Select it explicitly. A project that always wants it names it in
`morphir.toml`, under `[frontend.elm]`, the frontend's language-specific
table:

```toml
[frontend]
language = "elm"

[frontend.elm]
extension = "morphir-elm-native"
```

`morphir compile` then uses the native provider with no flag. The same key is
valid under any `[frontend.<language>]` table, because a provider belongs to a
language.

The `--extension` flag selects a provider for one run, and overrides the
configured one:

```sh
morphir compile --extension morphir-elm-native

morphir compile --input Example.elm --extension morphir-elm-native
```

The order of precedence is `--extension`, then
`[frontend.<language>] extension`, then the language's default provider. A
configured id that does not provide the language fails the run and says so. A
value that is not a usable extension id — blank, of the wrong type, or
malformed — is a configuration error naming `frontend.<language>.extension`,
unless `--extension` is given. When it is, the flag's provider is used and the
broken value is ignored, with a warning on stderr that names the key and says
what was wrong with it. Other configuration errors, such as an ambiguous
`[frontend.<language>]` table from two spellings that differ only in case,
still fail the run whether or not `--extension` was given: only a malformed
`extension` value is excused by the flag.

The key applies to a whole-project compile, and to a single-file compile that
loaded a configuration through `--config` or `--project`; a single-file compile
with neither flag uses the default provider. The Morphir Playground and
`morphir ui` read it too, from the workspace they were launched in, so a
browser compile uses the same provider the command line does.

`morphir-elm-native` is **types-only today**: it compiles type declarations
and signatures but not value bodies. `morphir-elm` remains the default
extension for Elm and is the only provider that compiles values, so keep
using it for production Elm workflows.

### Choosing the Elm prelude

The prelude is the set of implicit imports and SDK module aliases every Elm
module is compiled against. `morphir-elm-native` uses `elm-core` unless the
project asks for something else. Name the prelude in `morphir.toml` under
`[frontend.elm]`, the frontend's language-specific table, in one of three
forms.

The default prelude, which resolves `Int`, `String`, `List` and the rest of
the Elm core types:

```toml
[frontend.elm]
prelude = "elm-core"
```

No prelude at all, so only names a module declares or imports itself are in
scope:

```toml
[frontend.elm]
prelude = "none"
```

Or a prelude the project describes itself, as a table with the same fields a
prelude file uses (`id`, `implicit_import`, `module_alias`, and `package`):

```toml
[frontend.elm.prelude]
id = "acme-std"

[[frontend.elm.prelude.implicit_import]]
module = "Acme.Std.Basics"
exposing = ["Int", "String"]

[[frontend.elm.prelude.module_alias]]
source = "Core"
target = "Acme.Std.Core"
```

The key travels to the provider as the `elmPrelude` compile option, so it
applies to the native provider and is ignored by the JavaScript `morphir-elm`
extension. It applies to a whole-project compile, and to a single-file compile
that loaded a configuration through `--config` or `--project`; a single-file
compile with neither flag uses the default prelude. Changing the prelude
invalidates the incremental compile cache, so the next run compiles every
module again. A value that is neither a name nor a table fails the run and
names `frontend.elm.prelude`.

### Matching morphir-elm, or not

`morphir-elm-native` writes a document that is meant to be interchangeable with
the one `morphir-elm` writes, but in two places the compatible answer is not the
better one. Each of those is a mode you choose, rather than a decision buried in
the frontend.

`doc_comments` decides what a `{-| ... -}` comment becomes in the IR. The
default, `morphir-elm`, reproduces morphir-elm byte for byte: the delimiters
come off and every other character — leading spaces, interior and trailing
newlines — stays. `trimmed` removes the surrounding whitespace instead. The
compatible mode is the default because a doc's text is data a consumer may
already be matching on.

`ordering` decides the order modules, types and constructors appear in. The
default, `source`, is the order the Elm declares them: a reader comparing a
document with the source finds them in the same place, and a diff between two
versions shows the edit rather than a reshuffle. `morphir-elm` sorts them the
way morphir-elm's `Dict`s do, on the words a name splits into. Here the better
answer is the default, because the order is not data anyone matches on. Record
fields and constructor arguments are unaffected either way: they are positional
in morphir-elm too.

```toml
[frontend.elm]
doc_comments = "morphir-elm"
ordering = "source"
```

Three surfaces set each key, in this order of precedence:

```sh
# 1. the flag, for one run
morphir compile --elm-ordering morphir-elm --elm-doc-comments trimmed

# 2. the environment, for a shell or a CI job
MORPHIR_FRONTEND__ELM__ORDERING=morphir-elm morphir compile

# 3. morphir.toml, morphir.yaml or a user override, for a project
```

The environment variable is an ordinary configuration layer that the loader
merges over the files, which is why the key is spelled `doc_comments` rather
than `docComments`: the environment mapping lower-cases each segment and keeps
single underscores, so snake_case is the one spelling all three surfaces share.

Both keys travel to the provider as compile options (`elmDocComments` and
`elmOrdering`), so they apply to the native provider and are ignored by the
JavaScript `morphir-elm` extension. Each mode is part of the compile context,
so changing one invalidates the incremental compile cache and the next run
compiles every module again.

Unlike `prelude` and `extension`, the modes apply to a standalone single-file
compile as well — one given neither `--config` nor `--project`. There is no
configuration file on such a run, so the flag and the environment variable are
the only surfaces, and both work. The file keys keep their documented
behaviour: a standalone compile still uses the default provider and the default
prelude.

A value that is not one of the modes fails the run and names the key, unless
the matching flag was given — then the flag's mode is used and the broken value
is ignored, exactly as `extension` behaves. That warning goes to stderr, and to
the `diagnostics` of `--json` and `--json-lines` output, so a client reading the
result envelope sees it too.

## Native Gleam provider (`morphir-gleam`)

Gleam compilation and generation use the built-in Rust extension by default.
It runs in process without installing an extension or a Gleam executable.
For a Gleam project, select the provider explicitly with
`morphir compile --extension morphir-gleam`, then generate code with
`morphir generate --target gleam`. `morphir extension list` reports its mode
as `native-direct`.

The provider supports IR v3/v4 types, including records represented as ADTs
and sum types, diagnostics and incremental compilation. V4 also supports a
subset of Gleam functions. It uses the official Gleam parser; it does not run
Gleam's type inference.

The old `morphir-gleam-binding` selector remains an alias. If an installed
extension has that exact old id, selecting it still uses that installation.
An installed Gleam provider continues to take precedence for commands without
an explicit selector. The native implementation also ships as an optional
WASM package under the `morphir-gleam` extension id.

## Incremental compile cache

Frontends that advertise the `incremental` capability, including
`morphir-elm-native`, can reuse work from a previous compile instead of
recompiling every module. The cache lives under
`<workspace>/.morphir/cache/compile/<extension>/<package>/`, as a manifest
file plus one file per cached module.

A module is reused when its source digest and the interface digests of every
module it depends on match the cached baseline; otherwise it is recompiled.
Reuse never causes a failure: a missing, unreadable, or corrupt cache entry is
treated as no baseline for that module rather than an error, and cache writes
are atomic so an interrupted run cannot leave a half-written entry behind.

A partial failure (one or more modules fail or are blocked by a failed
dependency) still exits with status 1, leaves the previously installed
`morphir-ir.json` untouched, and updates the cache only for modules that
compiled successfully; failed and blocked modules keep their last good cache
entry.

Pass `--no-cache` to skip reading and writing the cache and force a full
recompile:

```sh
morphir compile --extension morphir-elm-native --no-cache
```

Only providers that advertise `incremental` use the cache at all; other
extensions ignore `--no-cache` and always compile fully.

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

The task opens the installed application with `--offline --wait`. Open **IR Explorer**, select
`applyLambda` and inspect
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
