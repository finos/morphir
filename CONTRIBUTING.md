# Contributing to Morphir

Thank you for contributing to Morphir. Read the [contribution and governance policies](docs/developers/contributing.md) before opening a pull request. The [development guide](DEVELOPING.md) covers tools, builds, tests, and the usual development workflow.

## Populate the required submodules

This repository uses Git submodules under `ecosystem/`. Populate them before running Cargo, tests, or ecosystem builds:

```bash
mise run submodules:init
```

The command initializes every submodule recursively at the revision recorded by this repository. In particular:

- `ecosystem/morphir-rust` provides path dependencies required to load and build the Rust workspace.
- `ecosystem/morphir-ui` contains the editable Morphir UI source. The CLI serves a checked-in web bundle, so this submodule is only needed when changing or rebuilding that client.
- Other ecosystem tasks require their corresponding submodules.

For a complete first-time setup, including Git hooks, run:

```bash
mise run init
```

If `mise` is not available yet, initialize the submodules directly:

```bash
git submodule update --init --recursive
```

Check the populated revisions and local state with:

```bash
mise run submodules:status
```

Do not replace pinned submodule revisions with the latest upstream commits unless your contribution intentionally updates those revisions.
