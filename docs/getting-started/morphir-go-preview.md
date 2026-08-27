---
id: morphir-go-preview
title: Morphir Go
sidebar_label: Morphir Go
sidebar_position: 6
---

# Morphir Go

**Morphir Go** is a Go implementation of Morphir tooling. It provides a CLI and libraries for working with Morphir IR, including WebAssembly Interface Types (WIT) support and Go code generation.

:::info Separate repository
Morphir Go is **not** part of the finos/morphir umbrella tree. Development, installation, and issue tracking happen in **[finos/morphir-go](https://github.com/finos/morphir-go)**.
:::

## Relationship to finos/morphir

| Repository | Role |
| --- | --- |
| **[finos/morphir](https://github.com/finos/morphir)** (this docs site) | Umbrella project: documentation, Rust CLI, Morphir Live, ecosystem submodules |
| **[finos/morphir-go](https://github.com/finos/morphir-go)** | Go CLI, WIT pipeline, Go backends, Go libraries |

Both repositories are FINOS projects. They can coexist in a workspace; choose the CLI that matches your language stack and feature needs.

## When to use Morphir Go

Consider Morphir Go when you need:

- A single native Go binary with fast startup
- **WIT** (WebAssembly Interface Types) compilation and round-trip validation
- Go module and workspace generation from Morphir IR
- Go-based SDK and pipeline tooling

For Elm authoring, visualization, and the most mature backend processors, use **[morphir-elm](installation.md)**.

## Installation

Install and build instructions live in the Morphir Go repository:

- **Repository:** [github.com/finos/morphir-go](https://github.com/finos/morphir-go)
- **Releases:** [github.com/finos/morphir-go/releases](https://github.com/finos/morphir-go/releases)

Typical install options (see the morphir-go README for current commands):

```shell
# Download a release binary from GitHub Releases, or:
go install github.com/finos/morphir-go/cmd/morphir@latest
```

Verify with:

```shell
morphir about
```

## Preview status

Morphir Go is in **developer preview**. For production deployments, continue using stable [morphir-elm](installation.md) tooling unless your team has validated Morphir Go for your workflow.

Report issues and feedback in [finos/morphir-go issues](https://github.com/finos/morphir-go/issues).

## Archived documentation on this site

Earlier preview docs for WIT commands and JSONL batch processing were written when Go tooling was briefly hosted in finos/morphir. That content is archived under [CLI Preview (Archived)](../cli-preview/index.md). Current WIT and Go CLI documentation should be maintained in **finos/morphir-go**.
