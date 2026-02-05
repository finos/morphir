# Morphir ecosystem submodules

This directory contains [git submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules) for Morphir ecosystem repositories. The finos/morphir repo uses them to integrate with language and tooling implementations.

## Submodules

| Submodule        | Repository | Branch | Purpose |
|------------------|------------|--------|---------|
| **morphir-elm** | [finos/morphir-elm](https://github.com/finos/morphir-elm) | remixed | Reference Elm implementation; IR definition, compilers, visualization, and backend processors |
| **morphir-rust** | [finos/morphir-rust](https://github.com/finos/morphir-rust) | main | Rust libraries (morphir-core, morphir-common, etc.) used by morphir-live and the morphir CLI in this repo |
| **morphir-examples** | [finos/morphir-examples](https://github.com/finos/morphir-examples) | main | Example Morphir projects; used for docs, tests, and reference |
| **morphir-moonbit** | [finos/morphir-moonbit](https://github.com/finos/morphir-moonbit) | main | MoonBit implementation of Morphir tooling |

## First-time clone

If you cloned finos/morphir without submodules, initialize everything:

```bash
mise run init
```

This initializes submodules and sets up the development environment. Alternatively, you can initialize just submodules:

```bash
mise run submodules:init
```

Or use git directly:

```bash
git submodule update --init --recursive
```

To clone the repo with submodules in one step:

```bash
git clone --recurse-submodules https://github.com/finos/morphir.git
```

## Updating submodules

To update each submodule to the commit currently recorded by the superproject:

```bash
mise run submodules:update
```

To pull the latest from each submodule's remote (for local try-out; the superproject still pins a commit until you commit the new ref):

```bash
mise run submodules:pull
```

Check status of all submodules:

```bash
mise run submodules:status
```

## How morphir uses them

- **morphir-elm**: The reference implementation containing the IR definition, Elm compiler, visualization components, and backend processors (Scala, JSON Schema, TypeScript, etc.). Tracks the `remixed` branch which uses Mise + Bun for builds.
- **morphir-rust**: The morphir-live app and the morphir CLI (in `crates/`) depend on morphir-rust crates via Cargo path dependencies (e.g. `morphir-core`, `morphir-common`). The submodule is required to build those crates.
- **morphir-examples**: Used for examples, documentation, and tests. See each submodule's own README for build and usage.
- **morphir-moonbit**: MoonBit implementation with packages for SDK, core types, and WASM bindings. See below for build commands.

## Building and testing morphir-moonbit

Build and test MoonBit packages from the repo root:

```bash
# Build all packages (wasm and wasm-gc targets)
mise run build:morphir-moonbit

# Build specific package(s)
mise run build:morphir-moonbit -- morphir-sdk
mise run build:morphir-moonbit -- morphir-sdk morphir-core

# Run all tests
mise run test:morphir-moonbit

# Test specific package(s)
mise run test:morphir-moonbit -- morphir-core
```

Valid package names: `morphir-sdk`, `morphir-core`, `morphir-moonbit-bindings`

## Adding a new submodule

Run:

```bash
mise run submodules:add -- <name> [url]
```

Examples:

```bash
mise run submodules:add -- morphir-go
mise run submodules:add -- morphir-elm https://github.com/finos/morphir-elm.git
```

If `url` is omitted, it defaults to `https://github.com/finos/<name>.git`. Then add the new submodule to the table above and to [ecosystem/AGENTS.md](AGENTS.md) as needed.
