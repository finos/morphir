---
status: accepted
---

# ADR-0004: Retire morphir-live rather than migrate it into morphir-ui

`crates/morphir-live` is a Dioxus single-page app that browses workspaces, projects and models and edits `morphir.toml` through either a generated form or a raw TOML tab. We are retiring it. UI development consolidates in [finos/morphir-ui](https://github.com/finos/morphir-ui), and none of this crate's code moves there.

The crate never connected to Morphir. `src/data.rs` is headed "Sample data for demonstration purposes" and supplies the only workspaces the app has ever shown. `morphir_core` is a declared dependency that nothing under `src/` imports, so no IR is ever loaded. Every settings save path is a `// TODO: Actually save the config`. There are no tests. Where the crate does model the domain, it is weaker than what we already have written down: its `Workspace` and `Project` structs carry counts and an `is_favorite` flag, against `morphir-daemon`'s `Workspace::open` with real glob discovery and a five-state project lifecycle; its `MorphirConfig` covers seven of the fourteen sections in the morphir.toml specification; and its Favorites, Recent and Archived filters correspond to nothing in any config or daemon model. Its look and feel came from morphir-scala's shell, which finos/morphir-ui already carries.

We considered keeping it as a Dioxus and WASM experiment, and repurposing it as the shell for a Rust-native UI. Both keep a second UI stack alive. Scattered UI efforts drifting apart in look, feel and capability is the problem consolidation is meant to solve, so preserving this one would recreate it. Two ideas from the app are worth building, and both are requirements rather than code to salvage: multi-project workspace browsing, and morphir.toml editing that shows which scope each effective value came from. They are recorded in finos/morphir-ui#13.

Retiring the crate withdraws a published artifact. Release builds produce `morphir-live-<version>.tar.gz`, attach it to the GitHub release, and deploy it to GitHub Pages. Removal reaches the crate, the Cargo workspace member, the `dev` mise task and its neighbours, the release and pages workflows with their CI tests, and the references in README, INSTALLING, DEVELOPING and the CLI getting-started guide. Until finos/morphir-ui ships a hosted web build, this repository publishes no browser-accessible Morphir UI.
