---
title: "Distribution"
description: "Specification for Morphir IR v4 Distributions"
---

# Distribution

A **Distribution** contains a Morphir package and its dependency context. IR v4 supports two storage layouts: **Classic** and **Document Tree**.
The document's `formatVersion` identifies the IR format; package release versions belong to the proposed package system.

The [MCK IR suite](https://github.com/finos/morphir/tree/main/spec/ir/mck) specifies serialization and layout behavior.
The planned MCK package suite covers the outer release manifest, dependency lock, and package verification.
See [the package specification](./packages.md) for the distinction and the status of the current document-tree integration.

## Dual Distribution Modes

### 1. Classic Mode
A single document, such as `morphir-ir.json`, using a supported JSON or YAML profile.
- **Use Case**: Compatibility with existing tooling, simple projects.
- **Structure**: Contains the entire package definition, including all modules, types, and values nested within the JSON object.

### 2. Document Tree Mode
A hierarchical file layout (e.g., `.morphir-dist/`) where each definition specification resides in its own file.
- **Use Case**: Large projects, shell-tool integration (grep/find), incremental updates.
- **Layout**: The file structure mirrors the logical IR path structure.

## Document Tree Layout (`.morphir-dist`)

The **Document Tree** layout follows a strict directory structure:

```text
.morphir-dist/
├── manifest.json          # Distribution metadata and format version
├── pkg/                   # Local project IR
│   └── my-org/
│       └── my-project/
│           ├── module.json       # Module manifest
│           ├── user.type.json    # Definition files sit flat in the module directory
│           └── login.value.json
├── deps/                  # Dependency IR
│   └── morphir/
│       └── _sdk/
│           └── @/                # reserved version segment; current readers require bare @
│               └── basics/
│                   └── module.json
```

## Distribution Types

Both modes support three kinds of distributions:

### Library Distribution
Contains the full implementation logic (`TypeDefinition`, `ValueDefinition`).
- Used for the project being compiled.
- Corresponds to the `pkg/` directory in Document Tree mode.
- **Required fields**: `packageName`
- **Optional fields**: `dependencies` (default: empty), `def` (default: empty)

```json
// Full form
{ "Library": { "packageName": "my-org/my-lib", "dependencies": {...}, "def": {...} } }

// Compact form (empty dependencies and def omitted)
{ "Library": { "packageName": "my-org/my-lib" } }
```

### Specs Distribution
Contains only the public interface (`TypeSpecification`, `ValueSpecification`).
- Used for dependencies to speed up compilation.
- Corresponds to the `deps/` directory in Document Tree mode.
- **Required fields**: `packageName`
- **Optional fields**: `dependencies` (default: empty), `spec` (default: empty)

```json
// Full form
{ "Specs": { "packageName": "morphir/SDK", "dependencies": {...}, "spec": {...} } }

// Compact form
{ "Specs": { "packageName": "morphir/SDK" } }
```

### Application Distribution
A self-contained distribution with all dependencies statically linked.
- Includes named entry points that can be invoked by tooling or runtime.
- Used for deployment and execution.
- **Required fields**: `packageName`, `entryPoints`
- **Optional fields**: `dependencies` (default: empty), `def` (default: empty)

```json
// Full form
{ "Application": { "packageName": "my-org/my-app", "dependencies": {...}, "def": {...}, "entryPoints": {...} } }

// Compact form
{ "Application": { "packageName": "my-org/my-app", "entryPoints": { "main": { "target": "my-org/my-app:main#run", "kind": "main" } } } }
```
