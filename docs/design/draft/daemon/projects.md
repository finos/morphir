---
title: Project Management
sidebar_label: Projects
sidebar_position: 3
status: draft
---

# Project Management

This document defines operations for managing projects within a Morphir workspace.

## Overview

A **project** is a single Morphir package with its own `morphir.toml` configuration. Projects within a workspace can depend on each other and share resolved dependencies.

## Project States

```
                    ┌─────────────────┐
                    │    unloaded     │◄──────────────┐
                    └────────┬────────┘               │
                             │ load                   │ unload
                             ▼                        │
                    ┌─────────────────┐               │
                    │    loading      │               │
                    └────────┬────────┘               │
                             │                        │
              ┌──────────────┴──────────────┐        │
              │ success                     │ failure │
              ▼                             ▼        │
     ┌─────────────────┐           ┌─────────────────┐
     │      ready      │           │      error      │
     └────────┬────────┘           └─────────────────┘
              │ source changed
              ▼
     ┌─────────────────┐
     │      stale      │
     └────────┬────────┘
              │ reload
              └─────────────► loading
```

## Types

### ProjectState

```gleam
/// Project lifecycle state within a workspace
pub type ProjectState {
  /// Project metadata loaded, IR not compiled
  Unloaded
  /// Project is being compiled
  Loading
  /// Project IR is loaded and valid
  Ready
  /// Source files changed, needs recompilation
  Stale
  /// Project has compilation errors
  Error
}
```

### ProjectInfo

```gleam
/// Project information and status
pub type ProjectInfo {
  ProjectInfo(
    /// Package name (e.g., "my-org/domain")
    name: PackagePath,
    /// Semantic version
    version: SemVer,
    /// Path relative to workspace root
    path: String,
    /// Current state
    state: ProjectState,
    /// Source directory within project
    source_dir: String,
    /// Project dependencies
    dependencies: List(DependencyInfo),
  )
}
```

## Operations

### Add Project

Adds an existing project directory to the workspace.

#### Behavior

1. Verify project path exists and contains `morphir.toml`
2. Parse project configuration
3. Register project in workspace
4. Update `morphir.toml`
5. Return project info (state: `Unloaded`)

#### WIT Interface

```wit
/// Add a project to the workspace
add-project: func(
    /// Project name (package path)
    name: package-path,
    /// Project path (relative to workspace root)
    path: string,
    /// Initial version
    version: semver,
    /// Source directory
    source-dir: string,
) -> result<project-info, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/addProject",
  "params": {
    "name": "my-org/new-service",
    "path": "packages/new-service",
    "version": "0.1.0",
    "sourceDir": "src"
  }
}
```

**Response:**
```json
{
  "result": {
    "name": "my-org/new-service",
    "version": "0.1.0",
    "path": "packages/new-service",
    "state": "unloaded",
    "sourceDir": "src",
    "dependencies": []
  }
}
```

#### CLI

```bash
morphir workspace add packages/new-service
morphir workspace add --name my-org/new-service --path packages/new-service
```

### Remove Project

Removes a project from the workspace (does not delete files).

#### Behavior

1. Verify project exists in workspace
2. Check for dependents (warn if other projects depend on it)
3. Unload project if loaded
4. Remove from workspace registry
5. Update `morphir.toml`

#### WIT Interface

```wit
/// Remove a project from the workspace
remove-project: func(
    name: package-path,
) -> result<_, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/removeProject",
  "params": {
    "name": "my-org/old-service"
  }
}
```

#### CLI

```bash
morphir workspace remove my-org/old-service
```

### Get Project Info

Returns detailed information about a specific project.

#### WIT Interface

```wit
/// Get project info
get-project-info: func(
    name: package-path,
) -> result<project-info, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/projectInfo",
  "params": {
    "name": "my-org/domain"
  }
}
```

### List Projects

Lists all projects in the workspace.

#### WIT Interface

```wit
/// List all projects
list-projects: func() -> result<list<project-info>, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/listProjects",
  "params": {}
}
```

**Response:**
```json
{
  "result": [
    {
      "name": "my-org/core",
      "version": "1.0.0",
      "path": "packages/core",
      "state": "ready",
      "sourceDir": "src",
      "dependencies": []
    },
    {
      "name": "my-org/domain",
      "version": "2.0.0",
      "path": "packages/domain",
      "state": "stale",
      "sourceDir": "src",
      "dependencies": [
        { "name": "my-org/core", "version": "1.0.0", "resolved": true }
      ]
    }
  ]
}
```

### Load Project

Compiles a project and loads its IR into memory.

#### Behavior

1. Transition to `Loading` state
2. Resolve project dependencies
3. Compile source files to IR
4. Validate IR
5. Transition to `Ready` or `Error` state
6. Return distribution

#### WIT Interface

```wit
/// Load a project (parse and compile)
load-project: func(
    name: package-path,
) -> result<distribution, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/loadProject",
  "params": {
    "name": "my-org/domain"
  }
}
```

**Response:**
```json
{
  "result": {
    "distribution": {
      "Library": {
        "package": { "name": "my-org/domain", "version": "2.0.0" },
        "definition": { "..." }
      }
    },
    "diagnostics": []
  }
}
```

### Unload Project

Releases a project's IR from memory.

#### Behavior

1. Free IR memory
2. Transition to `Unloaded` state
3. Retain project metadata

#### WIT Interface

```wit
/// Unload a project (free resources)
unload-project: func(
    name: package-path,
) -> result<_, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/unloadProject",
  "params": {
    "name": "my-org/domain"
  }
}
```

### Reload Project

Recompiles a project (typically after source changes).

#### Behavior

1. Same as `Load`, but preserves previous IR until new compilation succeeds
2. Supports incremental compilation if available

#### WIT Interface

```wit
/// Reload a project (recompile)
reload-project: func(
    name: package-path,
) -> result<distribution, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/reloadProject",
  "params": {
    "name": "my-org/domain"
  }
}
```

## Project Discovery

When a workspace is opened, projects are discovered by:

1. **Explicit listing** in `morphir.toml`:
   ```toml
   [[projects]]
   name = "my-org/core"
   path = "packages/core"
   ```

2. **Glob patterns** for automatic discovery:
   ```toml
   [workspace]
   project-patterns = ["packages/*", "libs/*"]
   ```

3. **Walking** the directory tree for `morphir.toml` files

## Dependency Order

Projects are loaded in dependency order:

```
my-org/core        (no deps)      → load first
my-org/domain      (→ core)       → load second
my-org/api         (→ domain)     → load third
```

Circular dependencies are detected and reported as errors.

## Error Handling

| Error | Cause | Recovery |
|-------|-------|----------|
| `ProjectNotFound` | Project not in workspace | Check project name |
| `ProjectAlreadyExists` | Duplicate project name | Use different name |
| `InvalidConfig` | Bad `morphir.toml` | Fix configuration |
| `CompilationError` | Source code errors | Fix source code |
| `DependencyError` | Missing dependency | Add dependency |

## Best Practices

1. **Lazy Loading**: Only load projects when needed for operations
2. **Dependency Caching**: Cache resolved dependencies to speed up loads
3. **Partial Builds**: Allow building subset of projects
4. **State Recovery**: Persist project states for daemon restart
