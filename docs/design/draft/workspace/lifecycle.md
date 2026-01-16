---
title: Workspace Lifecycle
sidebar_label: Lifecycle
sidebar_position: 2
---

# Workspace Lifecycle

This document defines the lifecycle operations for Morphir workspaces: creation, opening, closing, and configuration management.

## Overview

Workspace lifecycle operations manage the overall state of a workspace session. A workspace must be opened before any project operations can be performed.

## State Machine

```
                    ┌─────────────────┐
                    │    (none)       │
                    └────────┬────────┘
                             │ create / open
                             ▼
                    ┌─────────────────┐
                    │  initializing   │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │ success                     │ failure
              ▼                             ▼
     ┌─────────────────┐           ┌─────────────────┐
     │      open       │           │      error      │
     └────────┬────────┘           └────────┬────────┘
              │ close                       │ close
              └──────────────┬──────────────┘
                             ▼
                    ┌─────────────────┐
                    │     closed      │
                    └─────────────────┘
```

## Types

### WorkspaceState

```gleam
/// Workspace lifecycle state
pub type WorkspaceState {
  /// Workspace is not active
  Closed
  /// Workspace is being initialized
  Initializing
  /// Workspace is ready for operations
  Open
  /// Workspace has unrecoverable errors
  Error
}
```

### WorkspaceInfo

```gleam
/// Complete workspace information
pub type WorkspaceInfo {
  WorkspaceInfo(
    /// Absolute path to workspace root
    root: String,
    /// Workspace name (from config or derived from root)
    name: String,
    /// Current lifecycle state
    state: WorkspaceState,
    /// Projects in this workspace
    projects: List(ProjectInfo),
    /// Workspace-level configuration
    config: Option(Document),
  )
}
```

### WorkspaceError

```gleam
/// Errors that can occur during workspace operations
pub type WorkspaceError {
  /// Workspace directory not found
  NotFound(path: String)
  /// Workspace already exists at path
  AlreadyExists(path: String)
  /// No workspace is currently open
  NotOpen
  /// Invalid workspace configuration
  InvalidConfig(message: String)
  /// IO error during operation
  IoError(message: String)
}
```

## Operations

### Create Workspace

Creates a new workspace at the specified path.

#### Behavior

1. Verify path does not already contain a workspace
2. Create `morphir.toml` with initial configuration
3. Create `.morphir/` directory for cache and state
4. Transition to `Open` state
5. Return workspace info

#### WIT Interface

```wit
/// Create a new workspace
create-workspace: func(
    /// Workspace root path (must not exist or be empty)
    root: string,
    /// Initial configuration (optional)
    config: option<document-value>,
) -> result<workspace-info, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/create",
  "params": {
    "root": "/path/to/workspace",
    "config": {
      "name": "my-workspace"
    }
  }
}
```

**Response:**
```json
{
  "result": {
    "root": "/path/to/workspace",
    "name": "my-workspace",
    "state": "open",
    "projects": []
  }
}
```

#### CLI

```bash
morphir workspace init [path]
morphir workspace init --name my-workspace
```

### Open Workspace

Opens an existing workspace for operations.

#### Behavior

1. Locate `morphir.toml` (search upward if needed)
2. Parse workspace configuration
3. Discover projects in workspace
4. Load project metadata (not full IR)
5. Transition to `Open` state
6. Return workspace info

#### WIT Interface

```wit
/// Open an existing workspace
open-workspace: func(
    /// Workspace root path
    root: string,
) -> result<workspace-info, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/open",
  "params": {
    "root": "/path/to/workspace"
  }
}
```

**Response:**
```json
{
  "result": {
    "root": "/path/to/workspace",
    "name": "my-workspace",
    "state": "open",
    "projects": [
      {
        "name": "my-org/core",
        "version": "1.0.0",
        "path": "packages/core",
        "state": "unloaded",
        "sourceDir": "src"
      }
    ]
  }
}
```

#### CLI

```bash
morphir workspace open [path]
cd /path/to/workspace && morphir workspace open
```

### Close Workspace

Closes the current workspace, releasing resources.

#### Behavior

1. Stop file watching if active
2. Unload all projects
3. Flush any pending state
4. Transition to `Closed` state

#### WIT Interface

```wit
/// Close the current workspace
close-workspace: func() -> result<_, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/close",
  "params": {}
}
```

**Response:**
```json
{
  "result": null
}
```

### Get Workspace Info

Returns current workspace state and information.

#### WIT Interface

```wit
/// Get current workspace info
get-workspace-info: func() -> result<workspace-info, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/info",
  "params": {}
}
```

### Update Configuration

Updates workspace-level configuration.

#### Behavior

1. Validate new configuration
2. Merge with existing configuration
3. Write updated `morphir.toml`
4. Notify affected projects if needed

#### WIT Interface

```wit
/// Update workspace configuration
update-workspace-config: func(
    config: document-value,
) -> result<_, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/updateConfig",
  "params": {
    "config": {
      "defaultSourceDir": "lib",
      "outputDir": "dist"
    }
  }
}
```

## Configuration

See [Configuration System](../configuration/README.md) for full configuration documentation.

### morphir.toml

```toml
[morphir]
version = "^4.0.0"

[workspace]
# Output directory for workspace-level artifacts
output_dir = ".morphir"

# Glob patterns for discovering member projects
members = ["packages/*"]

# Patterns to exclude from discovery
exclude = ["packages/deprecated-*"]

# Default member when no project specified
default_member = "packages/core"

# Shared dependencies (resolved once for all projects)
[workspace.dependencies]
"morphir/sdk" = "3.0.0"

# Default settings inherited by all projects
[ir]
format_version = 4

[codegen]
targets = ["typescript"]
```

## Error Handling

| Error | Cause | Recovery |
|-------|-------|----------|
| `NotFound` | Path doesn't exist or has no workspace | Use `create` instead |
| `AlreadyExists` | Workspace already at path | Use `open` instead |
| `NotOpen` | Operation requires open workspace | Call `open` first |
| `InvalidConfig` | Malformed configuration file | Fix configuration |
| `IoError` | File system error | Check permissions |

## Best Practices

1. **Single Active Workspace**: Only one workspace should be open per daemon instance
2. **Workspace Discovery**: Search upward for `morphir.toml` to support nested directories
3. **Graceful Degradation**: If workspace config is missing, treat directory as single-project workspace
4. **State Persistence**: Save workspace state to `.morphir/state.json` for session recovery
