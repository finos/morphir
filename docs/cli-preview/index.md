---
id: cli-preview-index
title: Morphir CLI Preview
sidebar_label: Overview
---

# Morphir CLI Preview

:::caution Developer Preview
The Morphir CLI Preview features are in active development. APIs and behavior may change.
For production use, please use the stable [morphir-elm](../installation.md) tools.
:::

Welcome to the Morphir CLI Preview documentation. This section covers new CLI features being developed as part of the Morphir Go rewrite, including WebAssembly Interface Types (WIT) support and enhanced batch processing capabilities.

## What's in Preview?

The CLI Preview introduces several powerful new features:

### WIT (WebAssembly Interface Types) Pipeline

A complete pipeline for working with WIT files:

- **`morphir wit make`** - Compile WIT to Morphir IR (frontend)
- **`morphir wit gen`** - Generate WIT from Morphir IR (backend)
- **`morphir wit build`** - Full round-trip pipeline with validation

[Learn more about WIT commands](commands/wit.md)

### JSONL Batch Processing

Process multiple sources efficiently with JSONL input/output:

- Stream processing of multiple WIT sources
- Structured JSON output for CI/CD integration
- Named entries for easy result correlation

[See JSONL examples](commands/wit.md#jsonl-batch-mode)

## Quick Start

```bash
# Install the latest preview version
curl -fsSL https://raw.githubusercontent.com/finos/morphir/main/scripts/install.sh | bash

# Compile WIT to Morphir IR
morphir wit make example.wit -o example.ir.json

# Full pipeline with round-trip validation
morphir wit build example.wit -o regenerated.wit

# Batch processing with JSONL
morphir wit make --jsonl-input sources.jsonl --jsonl
```

[Full Getting Started guide](getting-started.md)

## Preview Versioning

Preview releases follow semantic versioning with a pre-release suffix:

| Version | Description |
|---------|-------------|
| `0.4.0-alpha.1` | First alpha with WIT pipeline and JSONL support |
| `0.4.0-beta.x` | Feature-complete beta releases |
| `0.4.0` | Stable release |

See [Release Notes](release-notes/v0.4.0-alpha.1.md) for detailed changelog.

## Documentation Structure

- **[Getting Started](getting-started.md)** - Quick start guide for new users
- **[What's New](whats-new.md)** - Overview of new features in this release
- **[Commands](commands/wit.md)** - Detailed command reference
- **[Release Notes](release-notes/v0.4.0-alpha.1.md)** - Version-specific changelogs

## Feedback

We welcome feedback on preview features:

- **Report Issues**: [GitHub Issues](https://github.com/finos/morphir/issues)
- **Discussions**: [GitHub Discussions](https://github.com/finos/morphir/discussions)
- **Contributing**: [Contribution Guide](../contributing.md)

## Compatibility

The CLI Preview maintains compatibility with:

- **Morphir IR**: All versions (v1, v2, v3)
- **Existing Tooling**: Works alongside morphir-elm
- **Platforms**: Linux, macOS, Windows (x86_64, arm64)
