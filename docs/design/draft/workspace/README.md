---
title: Workspace Design
sidebar_label: Overview
sidebar_position: 1
---

# Workspace Design

This module defines the workspace management system for Morphir, enabling multi-project development with shared dependencies, coordinated builds, and file watching.

## Overview

A **workspace** is a collection of related Morphir projects that can share dependencies, be built together, and be managed as a cohesive unit. Workspaces enable:

- **Multi-project development**: Work on multiple related packages simultaneously
- **Shared dependencies**: Common dependencies resolved once across all projects
- **Coordinated builds**: Build all projects in dependency order
- **File watching**: Automatic recompilation on source changes
- **IDE integration**: Workspace-aware language server support

## Architecture

```
workspace-root/
├── morphir.toml    # Workspace configuration
├── .morphir/                 # Workspace-level cache and state
│   ├── deps/                 # Resolved dependencies (shared)
│   └── cache/                # Build cache
├── packages/
│   ├── core/                 # Project: my-org/core
│   │   ├── morphir.toml
│   │   └── src/
│   ├── domain/               # Project: my-org/domain
│   │   ├── morphir.toml
│   │   └── src/
│   └── api/                  # Project: my-org/api
│       ├── morphir.toml
│       └── src/
```

## Module Reference

| Module | Description |
|--------|-------------|
| [Lifecycle](./lifecycle.md) | Workspace creation, opening, closing, and configuration |
| [Projects](./projects.md) | Project management within a workspace |
| [Dependencies](./dependencies.md) | Dependency resolution and management |
| [Watching](./watching.md) | File system watching for incremental builds |
| [Build](./build.md) | Build orchestration and diagnostics |

## Key Concepts

### Workspace vs Project

| Concept | Scope | Configuration |
|---------|-------|---------------|
| **Workspace** | Multiple projects | `morphir.toml` with `[workspace]` section |
| **Project** | Single package | `morphir.toml` with `[project]` section |

Both use the same `morphir.toml` file format. The presence of `[workspace]` section enables workspace mode. A workspace is optional - single projects can operate independently with just `[project]` configuration.

See [Configuration System](../configuration/README.md) for full configuration documentation.

### Workspace States

```
┌──────────┐    open     ┌──────────┐
│  Closed  │ ──────────► │   Open   │
└──────────┘             └──────────┘
     ▲                        │
     │         close          │
     └────────────────────────┘
```

| State | Description |
|-------|-------------|
| `closed` | Workspace is not active |
| `initializing` | Workspace is being loaded |
| `open` | Workspace is ready for operations |
| `error` | Workspace has unrecoverable errors |

### Project States

| State | Description |
|-------|-------------|
| `unloaded` | Project metadata loaded, IR not compiled |
| `loading` | Project is being compiled |
| `ready` | Project IR is loaded and valid |
| `stale` | Source files changed, needs recompilation |
| `error` | Project has compilation errors |

## Design Principles

1. **Lazy Loading**: Projects are not compiled until explicitly loaded or needed
2. **Incremental**: Only recompile what changed
3. **Shared Resolution**: Dependencies resolved once at workspace level
4. **Isolation**: Project failures don't break the workspace
5. **Observable**: Rich state and diagnostic information

## Integration Points

### JSON-RPC Protocol

Workspace operations are exposed via JSON-RPC for daemon/client communication:

- `workspace/create`, `workspace/open`, `workspace/close`
- `workspace/addProject`, `workspace/removeProject`, `workspace/listProjects`
- `workspace/buildAll`, `workspace/clean`, `workspace/watch`

See [VFS Protocol](../morphir-vfs-protocol-v4.md#workspace-management-methods) for full method specifications.

### WIT Interface

For WASM component integration, the workspace interface is defined in WIT:

```wit
package morphir:vfs@0.4.0;

interface workspace {
    // Lifecycle, project, dependency, watching, and build operations
    // See individual module docs for details
}
```

### CLI Commands

```bash
morphir workspace init          # Create new workspace
morphir workspace add <path>    # Add project to workspace
morphir workspace build         # Build all projects
morphir workspace watch         # Watch and rebuild on changes
```

## Related Documents

- [VFS Protocol v4](../morphir-vfs-protocol-v4.md) - Parent protocol specification
- [WASM Components](../vfs-protocol/wasm-component.md) - WIT interface definitions
- [morphir.toml Specification](../../spec/morphir-toml/morphir-toml-specification.md) - Project configuration
