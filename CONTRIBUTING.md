# Contributing to Morphir

Thank you for contributing to Morphir. Read the [contribution and governance policies](docs/developers/contributing.md) before opening a pull request. The [development guide](DEVELOPING.md) covers tools, builds, tests, and the usual development workflow.

## Populate the required submodules

This repository uses Git submodules under `ecosystem/`. Before running a `mise` task, review the repository configuration and trust it, then populate the submodules:

```bash
mise trust .config/mise/config.toml
mise run submodules:init
```

Current `mise` releases auto-trust project configuration in normal mode. The explicit command also supports older releases. Paranoid mode requires content-bound trust, so run it again after the configuration changes.

The command initializes every submodule recursively at the revision recorded by this repository. In particular:

- `ecosystem/morphir-rust` provides path dependencies required to load and build the Rust workspace.
- `ecosystem/morphir-ui` contains the editable Morphir UI source. The CLI serves a checked-in web bundle, so this submodule is only needed when changing or rebuilding that client.
- Other ecosystem tasks require their corresponding submodules.

For a complete first-time setup, including Git hooks, run:

```bash
mise run init
```

If `mise` is not available or you do not want to trust the project configuration yet, initialize the submodules directly:

```bash
git submodule update --init --recursive
```

If you used `mise`, check the populated revisions and local state with:

```bash
mise run submodules:status
```

For the direct Git fallback, use:

```bash
git submodule status
```

Do not replace pinned submodule revisions with the latest upstream commits unless your contribution intentionally updates those revisions.
