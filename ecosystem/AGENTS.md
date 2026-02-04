# Ecosystem directory – agent guidelines

This directory holds **git submodules** for Morphir ecosystem repositories. Use this file when working on finos/morphir in ways that touch the ecosystem.

## What lives here

- **morphir-rust** – Rust workspace (morphir-core, morphir-common, morphir-daemon, morphir-ext, etc.). The **morphir** CLI binary lives in this repo under `crates/morphir`, not in the submodule; it depends on morphir-rust crates via path.
- **morphir-examples** – Example Morphir projects.
- **morphir-moonbit** – MoonBit implementation of Morphir tooling.

Do not edit submodule content in-place for long-term changes. Prefer contributing in the submodule's own repo and then updating the submodule ref in finos/morphir when intentional.

## Path dependencies

- **morphir-live** (`crates/morphir-live`) and **morphir** CLI (`crates/morphir`) depend on crates under `ecosystem/morphir-rust/crates/`.
- Use paths relative to the consuming crate. Example from `crates/morphir-live`:  
  `morphir_core = { path = "../../ecosystem/morphir-rust/crates/morphir-core" }`
- Do **not** add `ecosystem/morphir-rust` as a workspace member in the root `Cargo.toml`; only use path dependencies to specific crates.

## Commit authorship

Same as root [AGENTS.md](../AGENTS.md): **do not** add AI assistants as co-authors in commits (EasyCLA).

## Testing

To run tests inside a submodule:

```bash
cd ecosystem/morphir-rust && cargo test
```

Changes inside submodules are committed in the submodule repo. The morphir repo only commits the submodule ref when intentionally updating to a new revision.

## Future submodules

When morphir-go, morphir-elm, morphir-python, or others are added, they will live under `ecosystem/` with the same pattern. Document any language- or repo-specific usage in this file.
