---
title: Dependency Management
sidebar_label: Dependencies
sidebar_position: 4
---

# Dependency Management

This document defines dependency resolution and management for Morphir workspaces.

## Overview

Morphir supports three categories of dependency sources:

| Source | Use Case | Status |
|--------|----------|--------|
| **Path** | Local development, workspace members, monorepos | **Available** |
| **Repository** | Pre-release code, forks, private packages | **Available** |
| **Registry** | Published packages, stable releases | **Planned** |

> **Note**: A Morphir package registry is planned for future releases. Until then, path and repository dependencies are the recommended approaches for sharing Morphir packages.

Dependencies can be declared at two levels:
- **Workspace-level**: Shared versions defined once, inherited by members
- **Project-level**: Specific to individual projects

## Dependency Sources

### Path Dependencies

Path dependencies reference local directories containing Morphir projects. They are resolved directly from the filesystem without version negotiation.

```toml
[dependencies]
# Relative path (recommended for workspace members)
"my-org/core" = { path = "../core" }

# Absolute path (for external local projects)
"my-org/shared" = { path = "/path/to/shared" }
```

**Use cases:**
- Workspace member projects depending on each other
- Local development of multiple related packages
- Temporary overrides during development (similar to Go's `replace`)

**Behavior:**
- Always uses the current source from the path
- No version constraint required (implicit "latest")
- Changes to source are immediately visible
- Must contain a valid `morphir.toml`

### Repository Dependencies

Repository dependencies are fetched directly from git repositories, similar to Go modules. This is the **recommended approach** for sharing packages across organizations until a registry is available.

```toml
[dependencies]
# Git repository with tag/version
"acme/experimental" = { git = "https://github.com/acme/experimental.git", tag = "v1.0.0" }

# Git repository with branch
"acme/feature" = { git = "https://github.com/acme/feature.git", branch = "main" }

# Git repository with specific commit
"acme/pinned" = { git = "https://github.com/acme/pinned.git", rev = "a8b3c5d" }

# SSH URL (for private repositories)
"private/internal" = { git = "git@github.com:private/internal.git", tag = "v2.0.0" }
```

**Reference types (mutually exclusive):**

| Field | Description | Example |
|-------|-------------|---------|
| `tag` | Git tag (recommended for releases) | `"v1.0.0"` |
| `branch` | Git branch (for tracking development) | `"main"` |
| `rev` | Specific commit SHA (for pinning) | `"a8b3c5d82"` |

**Use cases:**
- Sharing packages across organizations
- Pre-release packages
- Forked versions with custom modifications
- Private packages

**Behavior:**
- Repository is cloned/fetched to dependency cache
- Specific ref is checked out
- Treated as immutable once resolved (stored in lock file)

### Registry Dependencies (Planned)

> **Status**: Registry dependencies are planned for a future release.

Registry dependencies will be published packages fetched from a Morphir package registry:

```toml
[dependencies]
# Simple version constraint (planned)
"morphir/sdk" = "3.0.0"

# Semver range (planned)
"some-org/utilities" = "^1.2.0"

# Explicit registry specification (planned)
"finos/morphir-json" = { version = "^1.0.0", registry = "https://registry.morphir.dev" }
```

Until registry support is available, use repository dependencies with git tags for similar functionality:

```toml
# Current recommended approach for external packages
"morphir/sdk" = { git = "https://github.com/finos/morphir-sdk.git", tag = "v3.0.0" }
```

### Workspace Inheritance

Workspace members can inherit dependency versions from the workspace root, similar to Cargo's workspace inheritance:

```toml
# workspace/morphir.toml
[workspace]
members = ["packages/*"]

[workspace.dependencies]
"morphir/sdk" = { git = "https://github.com/finos/morphir-sdk.git", tag = "v3.0.0" }
"acme/shared" = { git = "https://github.com/acme/shared.git", tag = "v2.0.0" }
```

```toml
# workspace/packages/domain/morphir.toml
[project]
name = "my-org/domain"

[dependencies]
# Inherit version from workspace
"morphir/sdk" = { workspace = true }

# Can still add project-specific dependencies
"other/lib" = { path = "../other" }
```

**Benefits:**
- Single source of truth for shared dependency versions
- Consistent versions across all workspace members
- Simplified updates (change once, apply everywhere)
- Reduced configuration duplication

## Version Constraints

Version constraints apply to git tags and future registry dependencies:

| Syntax | Meaning | Example |
|--------|---------|---------|
| `"1.2.3"` | Exact version | Only 1.2.3 |
| `"^1.2.3"` | Compatible (caret) | ≥1.2.3, <2.0.0 |
| `"~1.2.3"` | Approximately (tilde) | ≥1.2.3, <1.3.0 |
| `">=1.2.0"` | Greater than or equal | ≥1.2.0 |
| `"<2.0.0"` | Less than | <2.0.0 |
| `">=1.0.0, <2.0.0"` | Range | ≥1.0.0 and <2.0.0 |

**Notes:**
- Path dependencies ignore version constraints
- Git dependencies with `branch` track the branch head
- Git dependencies with `rev` ignore semver entirely

## Types

### DependencySource

```gleam
/// Source of a dependency
pub type DependencySource {
  /// Local path dependency
  Path(path: String)
  /// Git repository dependency
  Repository(
    url: String,
    ref: GitRef,
  )
  /// Registry dependency (planned)
  Registry(
    version: SemVer,
    registry: Option(String),
  )
  /// Inherited from workspace
  Workspace
}

/// Git reference type
pub type GitRef {
  Tag(String)
  Branch(String)
  Rev(String)
}
```

### DependencySpec

```gleam
/// Dependency specification as declared in morphir.toml
pub type DependencySpec {
  DependencySpec(
    /// Package name
    name: PackagePath,
    /// Dependency source
    source: DependencySource,
  )
}
```

### DependencyInfo

```gleam
/// Resolved dependency information
pub type DependencyInfo {
  DependencyInfo(
    /// Package name
    name: PackagePath,
    /// Original source specification
    source: DependencySource,
    /// Whether dependency has been resolved
    resolved: Bool,
    /// Resolved location (path to resolved package)
    resolved_path: Option(String),
    /// Resolved version (from morphir.toml or git tag)
    resolved_version: Option(SemVer),
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
    version: Option(SemVer),
    /// Direct dependencies
    dependencies: List(PackagePath),
    /// Resolved source information
    source: ResolvedSource,
  )
}

/// Resolved source location
pub type ResolvedSource {
  /// Local path (workspace member or path dep)
  Local(path: String)
  /// Cached from git repository
  Cached(
    cache_path: String,
    url: String,
    ref: String,
  )
  /// Cached from registry (planned)
  RegistryCached(
    cache_path: String,
    registry: String,
  )
}
```

## Operations

### Add Dependency

Adds a dependency to a project.

#### Behavior

1. Validate dependency source specification
2. Update project's `morphir.toml`
3. Mark dependency as unresolved
4. Optionally trigger resolution

#### WIT Interface

```wit
/// Dependency source specification
variant dependency-source {
    /// Local path dependency
    path(string),
    /// Git repository dependency
    repository(git-dependency),
    /// Inherit from workspace
    workspace,
}

/// Git repository dependency
record git-dependency {
    url: string,
    ref: git-ref,
}

/// Git reference
variant git-ref {
    tag(string),
    branch(string),
    rev(string),
}

/// Add a dependency to a project
add-dependency: func(
    project: package-path,
    dependency: package-path,
    source: dependency-source,
) -> result<_, workspace-error>;
```

#### JSON-RPC

**Request (path dependency):**
```json
{
  "method": "workspace/addDependency",
  "params": {
    "project": "my-org/api",
    "dependency": "my-org/core",
    "source": { "path": "../core" }
  }
}
```

**Request (repository dependency):**
```json
{
  "method": "workspace/addDependency",
  "params": {
    "project": "my-org/api",
    "dependency": "morphir/sdk",
    "source": {
      "git": "https://github.com/finos/morphir-sdk.git",
      "tag": "v3.0.0"
    }
  }
}
```

**Request (workspace inheritance):**
```json
{
  "method": "workspace/addDependency",
  "params": {
    "project": "my-org/api",
    "dependency": "morphir/sdk",
    "source": { "workspace": true }
  }
}
```

#### CLI

```bash
# Path dependency
morphir deps add my-org/core --path ../core

# Repository dependency with tag
morphir deps add morphir/sdk --git https://github.com/finos/morphir-sdk.git --tag v3.0.0

# Repository dependency with branch
morphir deps add acme/feature --git https://github.com/acme/feature.git --branch main

# Repository dependency with commit
morphir deps add acme/pinned --git https://github.com/acme/pinned.git --rev a8b3c5d

# Workspace inheritance
morphir deps add morphir/sdk --workspace

# Specify target project
morphir deps add my-org/core --path ../core --project my-org/api
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

1. Collect all dependency specifications
2. Build dependency graph
3. For path dependencies: verify path exists and contains valid project
4. For repository dependencies: clone/fetch to cache, checkout ref
5. Resolve any version conflicts
6. Update lock file
7. Return resolution result

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
    {
      "name": "morphir/sdk",
      "source": { "git": "https://github.com/finos/morphir-sdk.git", "tag": "v3.0.0" },
      "resolved": true,
      "resolvedPath": ".morphir/deps/morphir/sdk/v3.0.0",
      "resolvedVersion": "3.0.0"
    },
    {
      "name": "my-org/core",
      "source": { "path": "../core" },
      "resolved": true,
      "resolvedPath": "/workspace/packages/core"
    },
    {
      "name": "acme/shared",
      "source": { "git": "https://github.com/acme/shared.git", "branch": "main" },
      "resolved": true,
      "resolvedPath": ".morphir/deps/acme/shared/main-a8b3c5d",
      "resolvedVersion": null
    }
  ]
}
```

#### CLI

```bash
morphir deps resolve
morphir deps resolve --project my-org/api
morphir deps list
morphir deps list --resolved  # Show resolved paths
```

## Lock File

The workspace maintains a `morphir.lock` file with resolved dependency information:

```toml
# morphir.lock
# This file is auto-generated. Do not edit.
# It ensures reproducible builds by pinning exact dependency sources.

[[package]]
name = "morphir/sdk"
source = "git"
url = "https://github.com/finos/morphir-sdk.git"
tag = "v3.0.0"
rev = "abc123def456..."
checksum = "sha256:abc123..."
dependencies = []

[[package]]
name = "my-org/core"
source = "path"
path = "packages/core"
# Path dependencies are not version-locked; they use current source

[[package]]
name = "acme/shared"
source = "git"
url = "https://github.com/acme/shared.git"
branch = "main"
rev = "a8b3c5d82e..."  # Pinned commit at resolution time
checksum = "sha256:def456..."
dependencies = ["morphir/sdk"]

[[package]]
name = "acme/pinned"
source = "git"
url = "https://github.com/acme/pinned.git"
rev = "deadbeef..."
checksum = "sha256:789abc..."
dependencies = []
```

### Lock File Behavior

| Source | Lock Behavior |
|--------|---------------|
| Path | Not locked; always uses current source |
| Git (tag) | Locks tag + resolved commit SHA |
| Git (branch) | Locks branch + resolved commit SHA at resolution time |
| Git (rev) | Locks exact commit SHA |

**Updating the lock file:**

```bash
# Resolve and update lock file
morphir deps resolve

# Update a specific dependency to latest
morphir deps update morphir/sdk

# Update all dependencies
morphir deps update --all

# Update git branch dependencies to latest commit
morphir deps update --branches
```

## Resolution Algorithm

### 1. Dependency Collection

Gather all dependency specifications from:
- Workspace-level `[workspace.dependencies]`
- Project-level `[dependencies]`
- Transitive dependencies (from resolved packages)

### 2. Workspace Inheritance Resolution

For dependencies marked `{ workspace = true }`:
1. Look up the dependency in `[workspace.dependencies]`
2. Replace with the workspace-defined source
3. Error if dependency not found in workspace

### 3. Graph Construction

Build a dependency graph:

```
my-org/api
├── morphir/sdk (git: finos/morphir-sdk.git@v3.0.0)
├── my-org/domain (path: ../domain)
│   ├── morphir/sdk (workspace -> git: finos/morphir-sdk.git@v3.0.0)
│   └── my-org/core (path: ../core)
│       └── morphir/sdk (workspace -> git: finos/morphir-sdk.git@v3.0.0)
└── acme/shared (git: acme/shared.git@main)
    └── morphir/sdk (git: finos/morphir-sdk.git@v3.0.0)
```

### 4. Source Resolution

For each dependency in topological order:

**Path dependencies:**
1. Resolve path relative to dependent project
2. Verify directory exists
3. Verify `morphir.toml` exists and is valid
4. Add to resolved graph

**Repository dependencies:**
1. Check if already in cache (matching URL + ref)
2. If not cached: clone repository to `.morphir/deps/`
3. Checkout specified ref (tag/branch/rev)
4. For branches: record resolved commit SHA
5. Verify `morphir.toml` exists in repository root
6. Add to resolved graph with cache path

### 5. Conflict Detection

Conflicts can occur when:
- Same package from different sources (e.g., path vs git)
- Same package from same git URL but different refs

```
Conflict: morphir/sdk
  my-org/api requires git@v3.0.0
  legacy/lib requires git@v2.0.0

Resolution strategies:
1. Unify to single version (if compatible)
2. Update legacy/lib to use v3.0.0
3. Use path override for local development
```

### 6. Path Overrides

For local development, path dependencies can override other sources:

```toml
# morphir.toml
[dependencies]
# Development override - path takes precedence
"morphir/sdk" = { path = "../morphir-sdk" }

# This repository source is ignored when path is also specified:
# "morphir/sdk" = { git = "...", tag = "v3.0.0" }
```

This is similar to Go's `replace` directive, allowing local modifications without changing the primary dependency specification.

## Dependency Cache

Repository dependencies can be cached locally (per-workspace) or globally (user-level). Local caching is the default for workspace isolation, but global caching can reduce disk usage and download time across multiple workspaces.

### Cache Locations

| Cache | Location | Use Case |
|-------|----------|----------|
| Local | `.morphir/deps/` | Workspace isolation, offline builds |
| Global | `$XDG_CACHE_HOME/morphir/deps/` | Shared across workspaces, reduced duplication |

The global cache follows XDG Base Directory conventions:
- Linux/macOS: `~/.cache/morphir/deps/` (or `$XDG_CACHE_HOME/morphir/deps/`)
- Windows: `%LOCALAPPDATA%\morphir\cache\deps\`

### Local Cache (Default)

```
workspace/
└── .morphir/
    └── deps/
        ├── morphir/
        │   └── sdk/
        │       └── v3.0.0-abc123/          # tag + short SHA
        │           ├── morphir.toml
        │           ├── src/
        │           └── .git/               # Shallow clone
        └── acme/
            └── shared/
                └── main-def456/            # branch + short SHA
                    └── ...
```

### Global Cache

```
~/.cache/morphir/
└── deps/
    ├── github.com/
    │   ├── finos/
    │   │   └── morphir-sdk/
    │   │       ├── v3.0.0/
    │   │       └── v3.1.0/
    │   └── acme/
    │       └── shared/
    │           └── main-def456/
    └── gitlab.com/
        └── ...
```

### Configuring Cache Behavior

**Per-dependency cache location:**

```toml
[dependencies]
# Use global cache for this dependency
"morphir/sdk" = { git = "https://github.com/finos/morphir-sdk.git", tag = "v3.0.0", cache = "global" }

# Explicit local cache (default)
"acme/experimental" = { git = "https://github.com/acme/experimental.git", branch = "main", cache = "local" }
```

**Workspace-wide cache default:**

```toml
# morphir.toml
[workspace]
members = ["packages/*"]

[cache]
# Use global cache for all repository dependencies by default
dependencies = "global"

# Or keep default local caching
# dependencies = "local"
```

**User-level default:**

```toml
# ~/.config/morphir/config.toml
[cache]
# Set global as default for all workspaces
dependencies = "global"
```

### Cache Management

```bash
# Show cache status (local and global)
morphir deps cache status

# Clean unused cached dependencies (local)
morphir deps cache clean

# Clean global cache
morphir deps cache clean --global

# Clean all cached dependencies
morphir deps cache clean --all

# Verify cache integrity
morphir deps cache verify
```

## Best Practices

1. **Commit Lock Files**: Always commit `morphir.lock` for reproducible builds
2. **Use Tags for Releases**: Prefer git tags over branches for stability
3. **Workspace Inheritance**: Share common dependencies at workspace level with `[workspace.dependencies]`
4. **Path for Development**: Use path dependencies for local cross-project development
5. **Global Cache for CI**: Consider global caching in CI environments to speed up builds across jobs
6. **Pin Branches**: When using branch dependencies, run `morphir deps resolve` regularly to update the lock file
7. **Review Updates**: Use `morphir deps update --dry-run` to preview changes before applying

## Migration Guide

### From Direct Git Clones

If you previously cloned dependencies manually:

```bash
# Before: manual clone
git clone https://github.com/finos/morphir-sdk.git deps/morphir-sdk

# After: declare in morphir.toml
[dependencies]
"morphir/sdk" = { git = "https://github.com/finos/morphir-sdk.git", tag = "v3.0.0" }
```

### Preparing for Registry

When the Morphir registry becomes available, migration will be straightforward:

```toml
# Current: repository dependency
"morphir/sdk" = { git = "https://github.com/finos/morphir-sdk.git", tag = "v3.0.0" }

# Future: registry dependency
"morphir/sdk" = "3.0.0"
```

The lock file format will remain compatible, so existing builds will continue to work.
