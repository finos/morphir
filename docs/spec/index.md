---
title: "Specifications"
linkTitle: "Specifications"
weight: 25
description: "Formal specifications for Morphir configuration and IR"
---

# Specifications

This section contains formal specifications for Morphir configuration and IR formats.

## Contents

- **[morphir.toml](./morphir-toml/morphir-toml-specification/)**: Specification for `morphir.toml` configuration files (projects, workspaces, tasks, workflows, toolchains, bindings).

- **[morphir.toml merge rules](./morphir-toml/morphir-toml-merge-rules/)**: How multiple configuration sources are merged into an effective configuration (precedence + deep-merge behavior).

- **[Morphir IR Specification](./ir/morphir-ir-specification/)**: The complete Morphir IR specification document, describing the structure, semantics, and usage of the Morphir IR format.

- **[Morphir IR JSON Schemas](./ir/schemas/)**: JSON schema definitions for all supported format versions of the Morphir IR (available in both YAML and JSON formats):
  - v3 (Current): [YAML](/schemas/morphir-ir-v3.yaml) | [JSON](/schemas/morphir-ir-v3.json)
  - v2: [YAML](/schemas/morphir-ir-v2.yaml) | [JSON](/schemas/morphir-ir-v2.json)
  - v1: [YAML](/schemas/morphir-ir-v1.yaml) | [JSON](/schemas/morphir-ir-v1.json)

## Purpose

This specifications section serves as the authoritative reference for:

- **Implementers**: Building tools that generate, consume, or transform Morphir formats
- **Developers**: Working with Morphir configuration and IR across platforms
- **LLMs**: Providing context for AI tools working with Morphir
- **Tooling**: Validating configuration and processing Morphir IR JSON files

## Related Resources

- [Morphir Project](https://morphir.finos.org/)
- [Morphir Repository](https://github.com/finos/morphir)
- [Morphir .NET Repository](https://github.com/finos/morphir-dotnet)

