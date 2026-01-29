---
title: "Packages"
description: "Specification for Packages in IR v4"
---

# Packages

A **Package** is the top-level unit of distribution in Morphir. It groups modules into a versioned namespace.

## Package Identity

A package is identified by:
- **Package Path**: A globally unique identifier (e.g., `Morphir.SDK`).
- **Version**: A semantic version string (e.g., `1.2.0`).

## Package Structure

### Classic Mode
A package is part of the monolithic `morphir-ir.json` structure, containing a map of module paths to module definitions.

**PackageDefinition** and **PackageSpecification** both have an optional `modules` field:

```json
// Full form
{ "modules": { "domain/users": { ... }, "domain/orders": { ... } } }

// Compact form (empty modules omitted)
{}
```

### Document Tree Mode
A package maps to a directory structure within the `.morphir-dist` root:

- **Local Packages**: Located in `pkg/{package-path}/`.
    - Example: `pkg/my-org/my-project/`
- **Dependencies**: Located in `deps/{package-path}/{version}/`.
    - Example: `deps/morphir/sdk/1.2.0/`

## Namespace Mapping

IR Paths map to directories using the canonical kebab-case naming convention defined in the [Naming](./names.md) spec.

- **Package Path**: `MyOrg.MyProject` -> `my-org/my-project`
- **Module Path**: `Domain.User` -> `domain/user`

This ensures a predictable and navigational structure for shell tools and developers.
