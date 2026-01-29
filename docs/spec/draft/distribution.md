---
title: "Distribution"
description: "Specification for Morphir IR v4 Distributions"
---

# Distribution

A **Distribution** represents a complete, versioned unit of a Morphir project or dependency. IR v4 supports two distribution modes: **Classic** and **Document Tree**.

## Dual Distribution Modes

### 1. Classic Mode
A single monolithic JSON blob (e.g., `morphir-ir.json`).
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
├── format.json            # Layout metadata and spec version
├── morphir.toml           # Project-level configuration
├── pkg/                   # Local project IR
│   └── my-org/
│       └── my-project/
│           ├── module.json       # Module manifest
│           ├── types/
│           │   └── user.type.json
│           └── values/
│               └── login.value.json
├── deps/                  # Dependency IR
│   └── morphir/
│       └── sdk/
│           └── 1.2.0/
│               └── ...
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
{ "Specs": { "packageName": "morphir/sdk", "dependencies": {...}, "spec": {...} } }

// Compact form
{ "Specs": { "packageName": "morphir/sdk" } }
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
