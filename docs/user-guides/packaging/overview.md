---
title: Packaging overview
sidebar_label: Overview
sidebar_position: 1
---

# Packaging overview

Morphir packages let you share a model as a versioned Library, select its dependencies,
and restore verified copies into another project. A Library contains Morphir IR and
a release manifest describing its identity, public modules, dependencies, and files.

:::caution Early access
These guides describe **Morphir CLI v0.4.0-beta.9**. Packaging is an early-access
feature. Commands, configuration, file formats, and supported workflows may change
between releases. Pin the CLI version when following these examples and review
release notes before upgrading. The draft format markers do not promise a stable
interchange format.
:::

## Follow the workflow

If trust is new to you, start with [Why package trust matters](why-package-trust.md)
and [Trust explained simply](trust-explained.md). They explain the purpose of the
checks and the experience we are working toward.

The guides use two Libraries throughout. `eligibility` provides a `Decision` type
with `Approved` and `Declined` constructors. `loan-rules` depends on it.

| Article | What you will learn |
| --- | --- |
| [Create a Library](creating-a-library.md) | Understand and prepare the IR and manifest that make up a bundle. |
| [Publish locally](publishing-locally.md) | Understand how a bundle becomes a signed registry release, and which authoring tools are still missing. |
| [Install and use Libraries](installing-and-using.md) | Run the supported trust, resolve, restore, and consumption workflow against a prepared local registry. |

Start with the last article if you want to try working commands immediately.
You can complete it with the released CLI and example files; building Morphir
from source is unnecessary.

## What is available today?

| Operation | Early-access support |
| --- | --- |
| Prepare a Library bundle | `morphir package create` builds a verified dependency-free classic V4 Library. Other Libraries use the worked IR and manifest examples; there is no `pack` command. |
| Publish a new Library release | On macOS, `morphir package registry`, `sign` and `publish` publish a dependency-free classic V4 Library to an explicitly initialized local registry. Other platforms await qualification. |
| Establish trust | `morphir package trust init` records an explicitly trusted bootstrap root. |
| Select dependencies | `morphir package resolve` selects and verifies a complete graph from an exact published root, then writes `morphir.lock`. |
| Install a locked graph | `morphir package restore` verifies and writes the Libraries into a new directory. |
| Refresh or update | `refresh` authenticates registry metadata; `update` writes a new lock for selected dependency updates. |
| Use restored IR | Pass a restored Library to a supported generator. The example generates Gleam and compiles it in a consumer project. |

The current workflow uses one local directory registry that you control. It does
not provide remote registry discovery or automatically add dependencies to an
unpublished project. The root supplied to `resolve` must itself be a published
release. Cross-package code linking and running the generated application are
outside the demonstrated workflow.

## Files you will encounter

| File or directory | Purpose |
| --- | --- |
| `ir.json` | The Library's model, encoded as classic JSON IR v4 in this profile. |
| `manifest.json` | The release identity, exports, dependency requirements, and exact file hashes. |
| Registry directory | Bundles plus signed metadata, release records, and publisher statements. |
| `trust-policy.json` | Your explicit choice of trusted repository and publisher keys. A package cannot choose these for you. |
| Trust-state directory | Persistent authentication state used to reject rollback. Keep it between commands. |
| `morphir.lock` | The selected releases and their verification and acquisition information. Keep it with the consumer project. |
| Restore destination | The complete verified graph, arranged by package path and release version. |

The package path, such as `example.com/finance/eligibility`, identifies a release
family. The IR Package name, `example/eligibility`, identifies definitions inside
the model. They are separate names. Release versions do not become part of IR names.

## Before you start

Install the [Morphir CLI](../../getting-started/morphir-cli.md) using the
[v0.4.0-beta.9 release](https://github.com/finos/morphir/releases/tag/v0.4.0-beta.9),
then check `morphir --version`. File-copy commands in these guides use a POSIX shell,
such as Bash or Git Bash on Windows. Windows users should also follow the CLI
guide's [long-path setup](../../getting-started/morphir-cli.md#windows-enable-long-paths).

The prepared registry uses public test keys. Use it to learn the workflow;
those keys must not authorize your own real releases. The local workflow requires
caller-controlled directories and fresh signed metadata. Production-grade recovery
and broader filesystem qualification remain [separate work](https://github.com/finos/morphir/issues/912).

Continue with [creating a Library](creating-a-library.md), or go straight to
[installing and using the example](installing-and-using.md).
