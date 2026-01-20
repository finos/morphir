---
title: "Modules"
description: "Specification for Modules in IR v4"
---

# Modules

A **Module** serves as a container for related types and values. In IR v4, the physical representation of a module depends on the distribution mode.

## Module Structure

Conceptually, a module consists of:
- **Name**: The `Path` identifying the module (e.g., `Main/Domain`).
- **Types**: A collection of named type definitions or specifications.
- **Values**: A collection of named value definitions or specifications.
- **Documentation**: Optional module-level docstring.

## Physical Representation

### Classic Mode
In the single-blob distribution, a module is a JSON object nesting all its types and values:

```json
{
  "types": { ... },
  "values": { ... },
  "doc": "..."
}
```

### Document Tree Mode
In the hierarchical layout, a module is represented by a `module.json` file, which supports two encoding styles (or a mix):

#### 1. Manifest Style (Granular)
The `module.json` contains metadata, and definitions reside in separate files.

**Directory Structure**:
```
pkg/main/domain/
├── module.json
├── types/
│   └── user.type.json
└── values/
    └── login.value.json
```

**module.json**:
```json
{
  "formatVersion": 4,
  "module": "Main/Domain",
  "doc": "..."
}
```

#### 2. Inline Style (Hybrid)
The `module.json` contains the definitions directly, similar to Classic mode. This reduces file count for smaller modules.

**module.json**:
```json
{
  "formatVersion": 4,
  "module": "Main/Domain",
  "doc": "...",
  "types": {
    "User": { "def": { ... } }
  },
  "values": {
    "login": { "def": { ... } }
  }
}
```

## Granular Definitions

When using the Granular style, the Document Tree mode enforces a "one file per definition" rule:
- **Separation**: Types and Values are stored separately.
- **Naming**: File names correspond to the type or value name (plus suffix).
- **Polymorphism**: The content of the file can be a *Definition* (implementation) or a *Specification* (interface), indicated by the root key (`def` vs `spec`).
