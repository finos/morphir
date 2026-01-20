---
title: Draft Specifications
sidebar_label: Overview
sidebar_position: 1
---

# Draft Specifications (IR v4)

This section contains the draft specifications for Morphir IR Version 4.

For the rationale behind these specifications, please see the [Draft Design Documentation](../../design/draft/README.md).

## Modules

- [What's New](./whats-new.md)
- [Naming](./names.md)
- [Attributes](./attributes.md)
- [Type System](./types.md)
- [Value System](./values.md)
- [Modules](./modules.md)
- [Package System](./packages.md)
- [Distribution System](./distribution.md)
- [Schema Architecture](./schemas.md)

## Key Changes in v4

- **No Generic Parameters**: Types and Values no longer carry a generic attribute parameter `a`. Instead, they contain specific `TypeAttributes` and `ValueAttributes` structures.
- **Explicit Attributes**: Attributes include source location, constraints (for types), and inferred types (for values).
- **Module.json**: First-class support for `module.json` files containing full module definitions.
