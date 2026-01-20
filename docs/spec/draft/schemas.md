---
title: "Schema Architecture"
description: "Architecture of the Morphir IR v4 JSON Schemas"
---

# Schema Architecture

The v4 schema specification uses **separate root schemas with shared `$ref` definitions**. This modular approach supports the dual distribution modes (Classic and Document Tree).

## Schema Hierarchy

```text
schemas/v4/
├── common/                 # Shared $ref definitions
│   ├── naming.yaml         # Path, Name, FQName, Locator
│   ├── types.yaml          # Type expressions & definitions
│   ├── values.yaml         # Value expressions & definitions
│   └── access.yaml         # AccessControlled wrapper
├── classic/                # Single-blob mode
│   └── distribution.yaml   # Root: Distribution
└── tree/                   # Document Tree mode
    ├── format.yaml         # .morphir-dist/format.json
    ├── module.yaml         # module.json schema
    ├── type-node.yaml      # *.type.json schema
    └── value-node.yaml     # *.value.json schema
```

## Common Schemas

- **`common/*.yaml`**: These files define the reusable building blocks of the IR. They are not intended to be used as root schemas for validation but are referenced by distribution-specific schemas.

## Distribution-Specific Schemas

### Classic Mode
- **`classic/distribution.yaml`**: The root schema for validating a monolithic `morphir-ir.json` file. It references the common definitions to build the full nested structure.

### Document Tree Mode
- **`tree/format.yaml`**: Validates the `format.json` file at the root of a distribution.
- **`tree/module.yaml`**: Validates `module.json` files. It supports both the Manifest Style (metadata only) and the Inline Style (embedded definitions).
- **`tree/type-node.yaml`**: Validates individual `*.type.json` files.
- **`tree/value-node.yaml`**: Validates individual `*.value.json` files.

## Polymorphism in Document Tree Nodes

Type and value node schemas use **mutually exclusive keys** to distinguish between implementations and specifications:

```json
{ "def": { ... } } // Validates against TypeDefinition or ValueDefinition
{ "spec": { ... } } // Validates against TypeSpecification or ValueSpecification
```

This ensures that tools can strictly validate the content of a node based on its intended role (definition vs. specification).
