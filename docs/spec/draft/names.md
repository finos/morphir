---
title: "Naming"
description: "Specification for names and paths in Morphir IR v4"
---

# Naming

Morphir uses a sophisticated naming system that is independent of any specific naming convention (camelCase, snake_case, etc.). This allows the same IR to be rendered in different conventions for different platforms.

IR v4 introduces a **canonical string serialization** for names, paths, and fully-qualified names, making them easier to read and use as keys in JSON objects.

## Name

A **Name** represents a human-readable identifier.

- **Canonical Serialization**: A kebab-case string (e.g., `"user-account"`).
  - Abbreviations are enclosed in parentheses: `"value-in-(usd)"`.
  - Normalization: When parsing from other formats, detected abbreviations are wrapped in parentheses.
- **Legacy Decoding**: Also supports decoding from the legacy array format (e.g. `["value", "in", "u", "s", "d"]`) for backward compatibility.
- **Purpose**: Serves as the atomic unit for all identifiers

## Path

A **Path** represents a hierarchical location in the IR structure.

- **Canonical Serialization**: Names joined by forward slashes (e.g., `"morphir/sdk/string"`).
- **Legacy Decoding**: Supports array of names (e.g., `[["morphir"], ["s", "d", "k"]]`).
- **Purpose**: Identifies packages and modules within the hierarchy.

## Qualified Name (QName)

A **Qualified Name** uniquely identifies a type or value within a package.

- **Canonical Serialization**: `{module-path}#{local-name}` (e.g., `"main/orders#create"`).
- **Components**:
  - Module path: The Path to the module
  - Local name: The Name of the type or value within that module
- **Purpose**: Identifies items relative to a package

## Fully-Qualified Name (FQName)

A **Fully-Qualified Name** provides a globally unique identifier for any type or value.

- **Canonical Serialization**: `{package-path}:{module-path}#{local-name}` (e.g., `"morphir/sdk:list#map"`).
- **Legacy Decoding**: Supports array format `[packagePath, modulePath, localName]`.
- **Purpose**: Enables unambiguous references across package boundaries
