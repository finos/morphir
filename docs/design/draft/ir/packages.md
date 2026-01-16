---
title: Package Structure
sidebar_label: Packages
sidebar_position: 6
---

# Package Structure

Packages are versioned collections of modules that form a distributable unit.

## Package Types

```gleam
// === package.gleam ===

/// Package specification - public interface for dependency resolution
/// Used when this package is a dependency of another
pub type PackageSpecification(attributes) {
  PackageSpecification(
    modules: Dict(ModulePath, ModuleSpecification(attributes)),
  )
}

/// Package definition - complete implementation
/// Used for the local project being compiled
pub type PackageDefinition(attributes) {
  PackageDefinition(
    modules: Dict(ModulePath, AccessControlled(ModuleDefinition(attributes))),
  )
}
```

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Module access | AccessControlled on definitions | Modules can be package-private |
| No module docs | Docs at type/value level | Module-level docs in separate metadata |
| Path as key | `Dict(ModulePath, ...)` | Hierarchical organization preserved |

## Package Hierarchy

```
PackageDefinition
└── modules: Dict(ModulePath, AccessControlled(ModuleDefinition))
    ├── "main/domain" (Public)
    │   └── ModuleDefinition
    │       ├── types: Dict(Name, AccessControlled(Documented(TypeDefinition)))
    │       └── values: Dict(Name, AccessControlled(Documented(ValueDefinition)))
    │
    └── "internal/utils" (Private)
        └── ModuleDefinition
            └── ...
```

## JSON Serialization

### PackageSpecification

```json
{
  "modules": {
    "main/domain": {
      "types": {
        "user": { "TypeAliasSpecification": { "body": { "..." } } }
      },
      "values": {
        "create-user": { "inputs": { "..." }, "output": { "..." } }
      }
    }
  }
}
```

### PackageDefinition

```json
{
  "modules": {
    "main/domain": {
      "access": "Public",
      "types": {
        "user": {
          "access": "Public",
          "TypeAliasDefinition": { "body": { "..." } }
        }
      },
      "values": {
        "create-user": {
          "access": "Public",
          "ExpressionBody": { "..." }
        }
      }
    },
    "internal/utils": {
      "access": "Private",
      "types": { "..." },
      "values": { "..." }
    }
  }
}
```
