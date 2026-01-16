---
title: Dependency Management
sidebar_label: Dependencies
sidebar_position: 4
---

# Dependency Management

This document defines dependency resolution and management for Morphir workspaces.

## Overview

Morphir workspaces provide centralized dependency management:

- **Workspace-level dependencies**: Shared across all projects
- **Project-level dependencies**: Specific to individual projects
- **Local dependencies**: Projects within the workspace depending on each other
- **External dependencies**: Published packages from registries

## Dependency Types

### Internal Dependencies

Projects within the same workspace can depend on each other:

```toml
# packages/domain/morphir.toml
[dependencies]
"my-org/core" = { workspace = true }  # Local project reference
```

Internal dependencies are resolved directly from the workspace without version negotiation.

### External Dependencies

Published packages from Morphir registries:

```toml
[dependencies]
"morphir/sdk" = "3.0.0"
"some-org/utilities" = "^1.2.0"
```

### Version Constraints

| Syntax | Meaning |
|--------|---------|
| `"1.2.3"` | Exact version |
| `"^1.2.3"` | Compatible with 1.2.3 (>=1.2.3, <2.0.0) |
| `"~1.2.3"` | Approximately 1.2.3 (>=1.2.3, <1.3.0) |
| `">=1.2.0"` | Greater than or equal |
| `">=1.0.0, <2.0.0"` | Range |

## Types

### DependencyInfo

```gleam
/// Dependency information and resolution status
pub type DependencyInfo {
  DependencyInfo(
    /// Package name
    name: PackagePath,
    /// Required version (constraint)
    version: SemVer,
    /// Whether dependency has been resolved
    resolved: Bool,
    /// Resolved version (if resolved)
    resolved_version: Option(SemVer),
    /// Whether this is a workspace-local dependency
    is_local: Bool,
  )
}
```

### DependencyGraph

```gleam
/// Resolved dependency graph
pub type DependencyGraph {
  DependencyGraph(
    /// Root projects being resolved
    roots: List(PackagePath),
    /// All resolved packages (topologically sorted)
    packages: List(ResolvedPackage),
    /// Resolution conflicts (if any)
    conflicts: List(DependencyConflict),
  )
}

/// A resolved package in the graph
pub type ResolvedPackage {
  ResolvedPackage(
    name: PackagePath,
    version: SemVer,
    /// Direct dependencies
    dependencies: List(PackagePath),
    /// Source: local, cache, or registry
    source: PackageSource,
  )
}
```

## Operations

### Add Dependency

Adds a dependency to a project.

#### Behavior

1. Validate version constraint syntax
2. Update project's `morphir.toml`
3. Mark dependency as unresolved
4. Optionally trigger resolution

#### WIT Interface

```wit
/// Add a dependency to a project
add-dependency: func(
    project: package-path,
    dependency: package-path,
    version: semver,
) -> result<_, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/addDependency",
  "params": {
    "project": "my-org/api",
    "dependency": "morphir/sdk",
    "version": "3.0.0"
  }
}
```

#### CLI

```bash
morphir deps add morphir/sdk@3.0.0
morphir deps add morphir/sdk@3.0.0 --project my-org/api
```

### Remove Dependency

Removes a dependency from a project.

#### Behavior

1. Verify dependency exists
2. Check if removal would break other projects
3. Update project's `morphir.toml`
4. Update lock file

#### WIT Interface

```wit
/// Remove a dependency from a project
remove-dependency: func(
    project: package-path,
    dependency: package-path,
) -> result<_, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/removeDependency",
  "params": {
    "project": "my-org/api",
    "dependency": "some/unused-lib"
  }
}
```

#### CLI

```bash
morphir deps remove some/unused-lib
morphir deps remove some/unused-lib --project my-org/api
```

### Resolve Dependencies

Resolves all dependencies for a project or workspace.

#### Behavior

1. Collect all dependency constraints
2. Build dependency graph
3. Resolve version conflicts using SAT solver
4. Fetch missing packages from registry
5. Update lock file
6. Return resolution result

#### WIT Interface

```wit
/// Resolve all dependencies for a project
resolve-dependencies: func(
    project: package-path,
) -> result<list<dependency-info>, workspace-error>;

/// Resolve all dependencies for entire workspace
resolve-all-dependencies: func() -> result<list<tuple<package-path, list<dependency-info>>>, workspace-error>;
```

#### JSON-RPC

**Request (single project):**
```json
{
  "method": "workspace/resolveDependencies",
  "params": {
    "project": "my-org/api"
  }
}
```

**Request (entire workspace):**
```json
{
  "method": "workspace/resolveDependencies",
  "params": {}
}
```

**Response:**
```json
{
  "result": [
    { "name": "morphir/sdk", "version": "3.0.0", "resolved": true },
    { "name": "my-org/core", "version": "1.0.0", "resolved": true, "isLocal": true },
    { "name": "some/lib", "version": "1.2.0", "resolved": true }
  ]
}
```

#### CLI

```bash
morphir deps resolve
morphir deps resolve --project my-org/api
morphir deps list
```

## Lock File

The workspace maintains a `morphir-workspace.lock` file with resolved versions:

```toml
# morphir-workspace.lock
# This file is auto-generated. Do not edit.

[[package]]
name = "morphir/sdk"
version = "3.0.0"
source = "registry"
checksum = "sha256:abc123..."

[[package]]
name = "my-org/core"
version = "1.0.0"
source = "workspace"
path = "packages/core"

[[package]]
name = "some/lib"
version = "1.2.0"
source = "registry"
checksum = "sha256:def456..."
dependencies = ["morphir/sdk"]
```

## Resolution Algorithm

### 1. Constraint Collection

Gather all version constraints from:
- Workspace-level `[dependencies]`
- Project-level `[dependencies]`
- Transitive dependencies

### 2. Graph Construction

Build a dependency graph:

```
my-org/api@1.0.0
├── morphir/sdk@^3.0.0
├── my-org/domain@workspace
│   ├── morphir/sdk@^3.0.0
│   └── my-org/core@workspace
│       └── morphir/sdk@^3.0.0
└── some/http@^2.1.0
    └── morphir/sdk@^3.0.0
```

### 3. Version Resolution

Use PubGrub or similar algorithm to find compatible versions:

1. Start with root constraints
2. For each package, select highest compatible version
3. Add transitive constraints
4. Backtrack on conflicts
5. Report unsatisfiable constraints

### 4. Conflict Resolution

When conflicts occur:

```
Conflict: morphir/sdk
  my-org/api requires ^3.0.0
  legacy/lib requires ^2.0.0

Options:
1. Upgrade legacy/lib (if newer version available)
2. Downgrade morphir/sdk to 2.x (breaking change)
3. Fork legacy/lib
```

## Dependency Cache

Resolved dependencies are cached at `.morphir/deps/`:

```
.morphir/
└── deps/
    ├── morphir/
    │   └── sdk/
    │       └── 3.0.0/
    │           ├── morphir.toml
    │           └── .morphir-dist/
    └── some/
        └── lib/
            └── 1.2.0/
                └── ...
```

## Best Practices

1. **Lock Files**: Always commit lock files for reproducible builds
2. **Workspace Dependencies**: Share common dependencies at workspace level
3. **Version Ranges**: Use `^` for flexibility, exact versions for stability
4. **Regular Updates**: Periodically update dependencies with `morphir deps update`
5. **Security Scanning**: Integrate with vulnerability databases
