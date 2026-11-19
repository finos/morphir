# Ecosystem directory – agent guidelines

This directory holds **git submodules** for Morphir ecosystem repositories. Use this file when working on finos/morphir in ways that touch the ecosystem.

## What lives here

- **morphir-elm** – Reference Elm implementation (tracking `vnext`). Contains IR definition, Elm compiler, visualization components, and backend processors.
- **morphir-dotnet** – The Morphir CLI source. finos/morphir pins it and builds, qualifies and releases its four offerings with that source's own build (`.github/workflows/release.yml`, `.config/cli-release.json`). Change the CLI in finos/morphir-dotnet; move the pin here only as a reviewed delivery update, checked by `bun run tools/cli-release.ts verify-source`.
- **morphir-rust** – Rust workspace (morphir-core, morphir-common, morphir-daemon, morphir-ext, etc.). It also holds this repository's Rust development tools, `morphir-mck` and `morphir-dev`, in its `umbrella-tools/` workspace. finos/morphir has no Rust workspace and no Rust product CLI; its mise tasks and CI build the tools from this submodule, so the submodule stays while they need it.
- **morphir-examples** – Example Morphir projects.
- **morphir-moonbit** – MoonBit implementation of Morphir tooling.
- **morphir-python** – Python implementation of Morphir tooling. Owns the Python compiler and the `morphir-python` WASM extension.
- **morphir-scala** – Scala implementation of Morphir tooling. Mill build, cross-compiled to JVM, JS, and Scala Native.
- **morphir-ui** – Morphir's UI monorepo: the morphir-desktop (Electron) and morphir-web apps sharing one Svelte + Effect application (moonrepo + mise + bun toolchain).
- **morphir-typescript** – TypeScript binding for the Morphir IR: the reference semantic model, the version and profile codecs, and its MCK adapter. Shared IR and package runners live in the parent's standalone runner, `morphir-mck` (reached from the Morphir CLI as `morphir mck`). TypeScript retains independent adapters/implementations. PKG-2 moves draft.3 corpus/fixture support to parent Rust MCK and bounded runtime helpers to `morphir-package` in [#852](https://github.com/finos/morphir/issues/852). See [spec/mck/migration.md](../spec/mck/migration.md). Bun workspace; runtime-neutral (Node, Bun, Deno, browser).
- **morphir-gleam** – Gleam models and tooling for the BEAM ecosystem. `packages/morphir_models` is the Gleam mirror of the IR model. It has no MCK adapter or CI integration yet; a future integration should use `morphir-mck`.

Do not edit submodule content in-place for long-term changes. Prefer contributing in the submodule's own repo and then updating the submodule ref in finos/morphir when intentional.

## Path dependencies

- finos/morphir has no `Cargo.toml`. The development tools (`morphir-mck-cli`, `morphir-dev-tools`, `morphir-mck`) are the `ecosystem/morphir-rust/umbrella-tools` workspace. Do **not** add a Rust workspace or crate to the root of finos/morphir.
- That workspace reads this repository's `spec/`, `docs/` and `website/` files by relative path, so it builds only inside a finos/morphir checkout. Run it from the root of finos/morphir with the mise tasks (`mise run mck -- <command>`, `mise run kb -- <command>`, `mise run test`) or with `cargo ... --manifest-path ecosystem/morphir-rust/umbrella-tools/Cargo.toml`.
- A change to the tools is a pull request in finos/morphir-rust, then a move of the submodule pin here. A change that needs new kit files and new tool code needs both, in that order or with the pin on the finos/morphir-rust branch while both are in review.

## Commit authorship

Same as root [AGENTS.md](../AGENTS.md): **do not** add AI assistants as co-authors in commits (EasyCLA).

## Building and Testing

### morphir-rust

To run tests inside morphir-rust:

```bash
cd ecosystem/morphir-rust && cargo test
```

### morphir-moonbit

Build and test MoonBit packages from the repo root using mise tasks:

```bash
# Build all packages (wasm and wasm-gc targets)
mise run build:morphir-moonbit

# Build specific package(s)
mise run build:morphir-moonbit -- morphir-sdk
mise run build:morphir-moonbit -- morphir-sdk morphir-core

# Run all tests
mise run test:morphir-moonbit

# Test specific package(s)
mise run test:morphir-moonbit -- morphir-sdk
```

Valid package names: `morphir-sdk`, `morphir-core`, `morphir-moonbit-bindings`

### morphir-python

Python implementation of Morphir tooling. Uses `uv` for package management and `behave` for BDD tests.

It also owns the Python compiler, the Rust crate `rust/crates/morphir-python-binding`, and the `morphir-python` WASM extension built from it (extension id `morphir-python`, short id `python`, artifact `morphir-python-binding-<version>`, release tags `extension/python/v<version>`). Bundles up to `extension/python/v0.4.0` were released from finos/morphir-rust and stay in its releases. finos/morphir does not build the bundle: `[bundles.python]` in `.config/published-extension-bundles.toml` pins a published release and names its repository. The guides are `docs/python-extension.md` and `docs/python-compiler.md` in that repository.

Its mise configuration supplies Python, uv and the Rust toolchain that builds the native compiler from source:

```bash
cd ecosystem/morphir-python && mise install && mise run install && mise run test-bdd
```

### morphir-scala

Scala implementation of Morphir tooling. Built with [Mill](https://mill-build.org) through the repo's own `./mill` launcher; the Mill version is pinned in `.mill-version`. finos/morphir defines **no** top-level mise tasks for it — run its tasks from inside the submodule:

```bash
cd ecosystem/morphir-scala

mise run lint          # Formatting check (./mill --ticker false -i ci.lint)
mise run test:jvm      # JVM tests
mise run test:js       # JS tests
mise run test:native   # Scala Native tests
mise run ci:local      # Full local CI
```

Mill can also be driven directly, e.g. `./mill morphir.jvm.compile` or `./mill morphir.tests.jvm.test`. See the submodule's own [AGENTS.md](morphir-scala/AGENTS.md) for the full task list and its Scala coding conventions.

Changes inside submodules are committed in the submodule repo. The morphir repo only commits the submodule ref when intentionally updating to a new revision.

## Future submodules

Additional sibling repositories may be added under `ecosystem/` with the same pattern. Document any language- or repo-specific usage in this file.

**Note:** [finos/morphir-go](https://github.com/finos/morphir-go) already exists as a sibling repository but is not currently vendored here. Go tooling development happens in that repo unless and until it is added as a submodule.
