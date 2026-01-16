---
title: File Watching
sidebar_label: Watching
sidebar_position: 5
---

# File Watching

This document defines the file watching system for Morphir workspaces, enabling automatic recompilation on source changes.

## Overview

File watching enables:

- **Incremental builds**: Recompile only changed files
- **IDE integration**: Real-time error feedback
- **Development workflow**: Automatic rebuild on save
- **Hot reload**: Update running applications (where supported)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Workspace Daemon                      │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │   Watcher   │───►│   Debounce  │───►│  Compiler   │  │
│  └─────────────┘    └─────────────┘    └─────────────┘  │
│         ▲                                     │         │
│         │ FS events                           │ IR      │
│         │                                     ▼         │
│  ┌─────────────┐                      ┌─────────────┐  │
│  │ File System │                      │  Notifier   │  │
│  └─────────────┘                      └─────────────┘  │
│                                              │         │
└──────────────────────────────────────────────┼─────────┘
                                               │
                                               ▼
                                        Clients (IDE, CLI)
```

## Types

### WatchEventType

```gleam
/// Type of file system event
pub type WatchEventType {
  /// File or directory created
  Created
  /// File content modified
  Modified
  /// File or directory deleted
  Deleted
  /// File or directory renamed
  Renamed
}
```

### WatchEvent

```gleam
/// A file system change event
pub type WatchEvent {
  WatchEvent(
    /// Type of event
    event_type: WatchEventType,
    /// Affected path (relative to workspace root)
    path: String,
    /// New path (for rename events only)
    new_path: Option(String),
    /// Project this file belongs to (if determinable)
    project: Option(PackagePath),
    /// Timestamp of event
    timestamp: DateTime,
  )
}
```

### WatchState

```gleam
/// Current state of the file watcher
pub type WatchState {
  /// Watcher is not running
  Stopped
  /// Watcher is initializing
  Starting
  /// Watcher is active
  Running
  /// Watcher encountered an error
  Error(message: String)
}
```

## Operations

### Start Watching

Begins watching the workspace for file changes.

#### Behavior

1. Initialize file system watcher
2. Register watch paths for all projects
3. Set up debouncing (default: 100ms)
4. Begin emitting events

#### Watch Paths

By default, watches:
- `*/src/**/*.elm` - Elm source files
- `*/src/**/*.morphir` - Morphir DSL files
- `*/morphir.toml` - Project configuration
- `morphir-workspace.toml` - Workspace configuration

#### WIT Interface

```wit
/// Start watching workspace for changes
start-watching: func() -> result<_, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/watch",
  "params": {
    "enabled": true
  }
}
```

**Response:**
```json
{
  "result": {
    "state": "running",
    "watchedPaths": [
      "packages/core/src",
      "packages/domain/src",
      "packages/api/src"
    ]
  }
}
```

#### CLI

```bash
morphir workspace watch
morphir build --watch
```

### Stop Watching

Stops file system watching.

#### WIT Interface

```wit
/// Stop watching workspace
stop-watching: func() -> result<_, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/watch",
  "params": {
    "enabled": false
  }
}
```

### Poll Events

Retrieves pending watch events (for polling-based clients).

#### WIT Interface

```wit
/// Poll for watch events (non-blocking)
poll-events: func() -> list<watch-event>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/pollEvents",
  "params": {}
}
```

**Response:**
```json
{
  "result": [
    {
      "eventType": "modified",
      "path": "packages/domain/src/User.elm",
      "project": "my-org/domain",
      "timestamp": "2026-01-16T12:34:56Z"
    }
  ]
}
```

## Notifications

### workspace/onFileChanged

Push notification sent when files change (for streaming clients).

```json
{
  "method": "workspace/onFileChanged",
  "params": {
    "events": [
      {
        "eventType": "modified",
        "path": "packages/domain/src/User.elm",
        "project": "my-org/domain",
        "timestamp": "2026-01-16T12:34:56Z"
      },
      {
        "eventType": "created",
        "path": "packages/domain/src/Order.elm",
        "project": "my-org/domain",
        "timestamp": "2026-01-16T12:34:56Z"
      }
    ]
  }
}
```

### workspace/onProjectStateChanged

Push notification when a project's state changes due to file events.

```json
{
  "method": "workspace/onProjectStateChanged",
  "params": {
    "project": "my-org/domain",
    "previousState": "ready",
    "currentState": "stale",
    "reason": "Source files modified"
  }
}
```

### workspace/onBuildComplete

Push notification when automatic rebuild completes.

```json
{
  "method": "workspace/onBuildComplete",
  "params": {
    "project": "my-org/domain",
    "success": true,
    "diagnostics": [],
    "duration": 1234
  }
}
```

## Debouncing

File events are debounced to avoid excessive recompilation:

```
Events:     ─●─●●──●───●●●──────────────────
Debounce:   ─────────────────●──────────────
                             └── Trigger rebuild
            |<── 100ms ──>|
```

### Configuration

```toml
# morphir-workspace.toml
[watch]
debounce-ms = 100        # Debounce interval
ignore-patterns = [      # Patterns to ignore
  "**/node_modules/**",
  "**/.git/**",
  "**/*.bak"
]
auto-rebuild = true      # Automatically rebuild on changes
```

## Event Processing

### File Change Flow

```
1. File saved
   │
2. FS event received
   │
3. Debounce (collect more events)
   │
4. Determine affected project(s)
   │
5. Mark project(s) as 'stale'
   │
6. Emit 'onProjectStateChanged'
   │
7. If auto-rebuild enabled:
   │   ├── Recompile affected project(s)
   │   └── Emit 'onBuildComplete'
   │
8. Emit 'onFileChanged' (batched events)
```

### Affected Project Detection

```gleam
/// Determine which project a file belongs to
fn find_project_for_path(
  workspace: WorkspaceInfo,
  path: String,
) -> Option(PackagePath) {
  workspace.projects
  |> list.find(fn(p) { string.starts_with(path, p.path) })
  |> option.map(fn(p) { p.name })
}
```

## Watch Strategies

### Recursive Watch

Watch entire source directories recursively (default):

```
packages/domain/src/
├── Domain/
│   ├── User.elm      ← watched
│   └── Order.elm     ← watched
└── Utils.elm         ← watched
```

### Glob-Based Watch

Watch specific patterns:

```toml
[watch]
patterns = [
  "**/*.elm",
  "**/*.morphir",
  "!**/*_test.elm"  # Exclude tests
]
```

### Selective Watch

Watch only specific projects:

```toml
[watch]
projects = ["my-org/core", "my-org/domain"]  # Only these
```

## Error Handling

| Error | Cause | Recovery |
|-------|-------|----------|
| `WatchError` | FS watcher failed | Restart watcher |
| `TooManyFiles` | Watch limit exceeded | Use ignore patterns |
| `PermissionDenied` | Cannot access directory | Check permissions |
| `PathNotFound` | Watched path deleted | Re-scan workspace |

## Platform Considerations

### Linux (inotify)

- Default limit: ~8192 watches
- Increase with: `fs.inotify.max_user_watches`

### macOS (FSEvents)

- No practical limit
- Slightly higher latency

### Windows (ReadDirectoryChangesW)

- Works per-directory
- May miss rapid changes

## Best Practices

1. **Ignore Generated Files**: Don't watch `.morphir-dist/`, `node_modules/`
2. **Reasonable Debounce**: 100-300ms balances responsiveness and efficiency
3. **Batch Events**: Process multiple changes together when possible
4. **Graceful Degradation**: Fall back to polling if native watching fails
5. **Resource Limits**: Monitor memory/CPU usage of watcher
