---
title: "Naming"
description: "Specification for names and paths in Morphir IR v4"
---

# Naming

Morphir uses a sophisticated naming system that is independent of any specific naming convention (camelCase, snake_case, etc.). This allows the same IR to be rendered in different conventions for different platforms.

IR v4 introduces a **canonical string serialization** for names, paths, and fully-qualified names, making them easier to read and use as keys in JSON objects.

## Name

A **Name** represents a human-readable identifier composed of words.

- **Canonical Serialization**: A kebab-case string (e.g., `"user-account"`).
  - Abbreviations and acronyms (sequences of single letters) are enclosed in parentheses: `"value-in-(usd)"`.
  - Normalization: When parsing from other formats, detected abbreviations/acronyms are wrapped in parentheses.
- **Legacy Decoding**: Also supports decoding from the legacy array format (e.g. `["value", "in", "u", "s", "d"]`) for backward compatibility.
- **Purpose**: Serves as the atomic unit for all identifiers

### Abbreviation and Acronym Handling

Abbreviations and acronyms are represented as sequences of single-letter words that render as uppercase in target conventions:

| Structured (words) | Canonical | camelCase | PascalCase |
|--------------------|-----------|-----------|------------|
| `["value", "in", "u", "s", "d"]` | `value-in-(usd)` | `valueInUSD` | `ValueInUSD` |
| `["morphir", "s", "d", "k"]` | `morphir-(sdk)` | `morphirSDK` | `MorphirSDK` |
| `["get", "h", "t", "m", "l"]` | `get-(html)` | `getHTML` | `GetHTML` |

**Note**: `["sdk"]` (single word) renders as `Sdk` in PascalCase, while `["s", "d", "k"]` (three single letters) renders as `SDK`.

## TypeVariable

A **TypeVariable** is a semantically distinct wrapper around a Name, used for type parameters.

- **Structure**: Wraps a `Name` to distinguish type variables from value names at the type level
- **Canonical Serialization**: Same as Name (e.g., `"a"`, `"comparable"`)
- **Purpose**: Prevents mixing type variable names with value names in type-safe implementations

## Path

A **Path** represents a hierarchical namespace composed of Names.

- **Canonical Serialization**: Names joined by forward slashes (e.g., `"main/domain"`, `"morphir/(sdk)"`).
- **Legacy Decoding**: Supports array of name arrays (e.g., `[["morphir"], ["s", "d", "k"]]` for `morphir/(sdk)`).
- **Purpose**: Forms the basis for package and module identification

## PackageName

A **PackageName** identifies a package—the top-level namespace for a Morphir project.

- **Structure**: A `Path` representing the package identity
- **Canonical Serialization**: Same as Path (e.g., `"morphir/(sdk)"`, `"my-org/my-project"`)
- **Examples**:
  - `morphir/(sdk)` - The Morphir SDK package
  - `my-org/finance` - A custom organization's finance package
- **Purpose**: Uniquely identifies a package in the ecosystem

## ModuleName

A **ModuleName** identifies a module within a package, combining the package path and module path.

- **Structure**: Composed of a `PackageName` and a module `Path`
- **Canonical Serialization**: Package path followed by module path segments (e.g., `"morphir/(sdk)/list"`, `"my-org/finance/pricing/models"`)
- **Purpose**: Provides the full path to a module for resolution

## Qualified Name (QName)

A **Qualified Name** uniquely identifies a type or value within a package (relative to that package).

- **Canonical Serialization**: `{module-path}#{local-name}` (e.g., `"main/orders#create-order"`).
- **Components**:
  - Module path: The `Path` to the module within the package
  - Local name: The `Name` of the type or value within that module
- **Purpose**: Identifies items relative to a package context

## Fully-Qualified Name (FQName)

A **Fully-Qualified Name** provides a globally unique identifier for any type or value.

- **Canonical Serialization**: `{package-path}:{module-path}#{local-name}` (e.g., `"morphir/(sdk):list#map"`).
- **Legacy Decoding**: Supports array format `[packagePath, modulePath, localName]`.
- **Components**:
  - Package path: The `PackageName` (`Path`)
  - Module path: The module `Path` within the package
  - Local name: The `Name` of the type or value
- **Purpose**: Enables unambiguous references across package boundaries

## URI and Locator (v4)

IR v4 introduces protocol-level addressing for the Document Tree virtual filesystem.

### Scheme

Identifies the type of resource being addressed:

- **Pkg**: `morphir://pkg/...` - Local project resources
- **Deps**: `morphir://deps/...` - External dependency resources
- **Session**: `morphir://session/...` - Transaction state resources

### Suffix

Indicates the content type of a Document Tree node:

- **TypeSuffix**: `.type.json` - Type definition or specification
- **ValueSuffix**: `.value.json` - Value definition or specification
- **ModuleSuffix**: `module.json` - Module manifest

### URI

A protocol-level address combining scheme, path, name, and suffix.

- **Structure**: `Uri(scheme, path, name, suffix)`
- **Example**: `morphir://pkg/my-org/project/main/domain/user.type.json`

### Locator

A hybrid identifier that can reference IR entities by either pure identity or protocol address.

- **ByIdentity**: References via `FQName` (e.g., `morphir/(sdk):list#map`)
- **ByUri**: References via `URI` (e.g., `morphir://pkg/.../list/map.value.json`)
- **Purpose**: Bridges semantic IR identity with physical Document Tree addressing
