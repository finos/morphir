---
title: "Modules"
description: "Specification for Modules in IR v4"
---

# Modules

A **Module** serves as a container for related types and values. In IR v4, the physical representation of a module depends on the distribution mode.

## Module Structure

Conceptually, a module consists of:
- **Name**: The `Path` identifying the module (e.g., `main/domain`).
- **Types**: A collection of named type definitions or specifications.
- **Values**: A collection of named value definitions or specifications.
- **Documentation**: Optional module-level documentation.

## Documentation

The **Documentation** type provides multi-line documentation support with cross-platform line ending handling.

- **Structure**: Opaque type containing a list of lines
- **Input formats**: Accepts both single strings (split on `\n`) and arrays of strings
- **Normalization**: Trailing `\r` characters are trimmed for cross-platform consistency
- **JSON serialization**:
  - Single-line: `"doc": "Brief description"`
  - Multi-line: `"doc": ["Line 1", "Line 2", "Line 3"]`

## Documented Wrapper

The **Documented** wrapper attaches optional documentation to any definition or specification.

- **Structure**: `Documented(doc: Option(Documentation), value: a)`
- **JSON flattening**: The wrapper is flattened in JSON—`doc` field is inlined alongside the value's fields
- **Omission**: If documentation is `None`, the `doc` field is omitted entirely

```json
{
  "doc": "A user in the system",
  "TypeAliasDefinition": { ... }
}
```

## Physical Representation

### Classic Mode
In the single-blob distribution, a module is a JSON object nesting all its types and values:

```json
{
  "types": { ... },
  "values": { ... },
  "doc": "Module documentation"
}
```

### Document Tree Mode
In the hierarchical layout, a module is represented by a `module.json` file, which supports two encoding styles (or a mix):

#### 1. Manifest Style (Granular)
The `module.json` contains metadata, and definitions reside in separate files.

**Directory Structure** (with optional subdirectories):
```
pkg/main/domain/
├── module.json
├── user.type.json
├── account.type.json
├── login.value.json
└── validate-email.value.json
```

**Alternative with subdirectories** (for organization):
```
pkg/main/domain/
├── module.json
├── types/
│   ├── user.type.json
│   └── account.type.json
└── values/
    ├── login.value.json
    └── validate-email.value.json
```

**Note**: The `types/` and `values/` subdirectories are optional organizational conventions. Definition files (`.type.json`, `.value.json`) can reside directly in the module directory or in subdirectories.

**module.json**:
```json
{
  "formatVersion": 4,
  "module": "main/domain",
  "doc": "Domain model for main application"
}
```

#### 2. Inline Style (Hybrid)
The `module.json` contains the definitions directly, similar to Classic mode. This reduces file count for smaller modules.

**module.json**:
```json
{
  "formatVersion": 4,
  "module": "main/domain",
  "doc": "Domain model for main application",
  "types": {
    "user": { "def": { ... } },
    "account": { "def": { ... } }
  },
  "values": {
    "login": { "def": { ... } },
    "validate-email": { "def": { ... } }
  }
}
```

## Granular Definitions

When using the Granular style, the Document Tree mode enforces a "one file per definition" rule:
- **Naming**: File names use canonical name format (kebab-case) plus suffix (`.type.json` or `.value.json`)
- **Location**: Files can be placed directly in the module directory or organized into subdirectories
- **Polymorphism**: The content of the file can be a *Definition* (implementation) or a *Specification* (interface), indicated by the root key (`def` vs `spec`)

### Example: user.type.json (Definition)

```json
{
  "doc": "Represents a user in the system",
  "def": {
    "TypeAliasDefinition": {
      "body": {
        "Record": {
          "fields": {
            "user-id": "morphir/(sdk):string#string",
            "email": "morphir/(sdk):string#string"
          }
        }
      }
    }
  }
}
```

### Example: user.type.json (Specification)

```json
{
  "doc": "Represents a user in the system",
  "spec": {
    "OpaqueTypeSpecification": {}
  }
}
```

## Module Specifications vs Definitions

Like types and values, modules have both specifications and definitions:

- **ModuleSpecification**: The public interface exposed to consumers. Contains only public types (as specifications) and value signatures.
- **ModuleDefinition**: The full implementation. Contains all types and values (both public and private) with their complete definitions.

Access control is applied at the definition level—specifications are always derived from the public subset of definitions.
