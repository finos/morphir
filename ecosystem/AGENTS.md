# Ecosystem directory – agent guidelines

This directory holds **git submodules** for Morphir ecosystem repositories. Use this file when working on finos/morphir in ways that touch the ecosystem.

## What lives here

- **morphir-elm** – Reference Elm implementation (tracking `remixed` branch). Contains IR definition, Elm compiler, visualization components, and backend processors.
- **morphir-rust** – Rust workspace (morphir-core, morphir-common, morphir-daemon, morphir-ext, etc.). The **morphir** CLI binary lives in this repo under `crates/morphir`, not in the submodule; it depends on morphir-rust crates via path.
- **morphir-examples** – Example Morphir projects.
- **morphir-moonbit** – MoonBit implementation of Morphir tooling.
- **morphir-python** – Python implementation of Morphir tooling.

Do not edit submodule content in-place for long-term changes. Prefer contributing in the submodule's own repo and then updating the submodule ref in finos/morphir when intentional.

## Path dependencies

- **morphir-live** (`crates/morphir-live`) and **morphir** CLI (`crates/morphir`) depend on crates under `ecosystem/morphir-rust/crates/`.
- Use paths relative to the consuming crate. Example from `crates/morphir-live`:  
  `morphir_core = { path = "../../ecosystem/morphir-rust/crates/morphir-core" }`
- Do **not** add `ecosystem/morphir-rust` as a workspace member in the root `Cargo.toml`; only use path dependencies to specific crates.

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

Changes inside submodules are committed in the submodule repo. The morphir repo only commits the submodule ref when intentionally updating to a new revision.

## Future submodules

When morphir-go or others are added, they will live under `ecosystem/` with the same pattern. Document any language- or repo-specific usage in this file.

### morphir-python

Python implementation of Morphir tooling. Uses `uv` for package management and `behave` for BDD tests.

```bash
cd ecosystem/morphir-python && uv sync && uv run behave
```
