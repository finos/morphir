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

## Core Concepts

### Specifications vs Definitions

A fundamental pattern in Morphir IR is the distinction between **Specifications** and **Definitions**. This separation enables modular compilation, separate interface publication, and dependency management.

| Concept | Specification | Definition |
|---------|---------------|------------|
| **Purpose** | Public interface/contract | Full implementation |
| **Contains** | Signatures, public structure | Implementation details, bodies |
| **Visibility** | Always public | Can be public or private |
| **Used by** | Consumers/dependents | Owner module only |

This pattern applies at multiple levels:

- **Types**: `TypeSpecification` vs `TypeDefinition`
- **Values**: `ValueSpecification` vs `ValueDefinition`
- **Modules**: `ModuleSpecification` vs `ModuleDefinition`
- **Packages**: `PackageSpecification` vs `PackageDefinition`

**Key principle**: A specification can always be derived from a definition by extracting only the public interface. Incomplete definitions (v4) expose as opaque specifications to hide internal brokenness from consumers.

### Type Specifications and Definitions

| Specification | Definition | Notes |
|---------------|------------|-------|
| `TypeAliasSpecification` | `TypeAliasDefinition` | Alias visible to consumers |
| `OpaqueTypeSpecification` | — | No structure exposed |
| `CustomTypeSpecification` | `CustomTypeDefinition` | Sum type with constructors |
| `DerivedTypeSpecification` | — | Opaque with conversion functions |
| — | `IncompleteTypeDefinition` | v4: Exposes as `OpaqueTypeSpecification` |

### Value Specifications and Definitions

| Specification | Definition Body | Notes |
|---------------|-----------------|-------|
| `ValueSpecification` | `ExpressionBody` | Normal IR implementation |
| `ValueSpecification` | `NativeBody` | Platform builtin (v4) |
| `ValueSpecification` | `ExternalBody` | FFI call (v4) |
| `ValueSpecification` | `IncompleteBody` | Work-in-progress (v4) |

A `ValueSpecification` contains only the function signature (input types and output type). The `ValueDefinition` wraps a `ValueDefinitionBody` with access control.

## Key Changes in v4

- **No Generic Parameters**: Types and Values no longer carry a generic attribute parameter `a`. Instead, they contain specific `TypeAttributes` and `ValueAttributes` structures.
- **Explicit Attributes**: Attributes include source location, constraints (for types), and inferred types (for values).
- **Module.json**: First-class support for `module.json` files containing full module definitions.
- **Incomplete Definitions**: New `IncompleteTypeDefinition` and `IncompleteBody` support best-effort compilation.
- **Native and External Values**: First-class support for platform builtins and FFI.
