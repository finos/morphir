---
title: Build Operations
sidebar_label: Build
sidebar_position: 6
status: draft
tracking:
  beads: [morphir-l75, morphir-n6b]
  github_issues: [392, 393, 400, 401]
---

# Build Operations

This document defines build orchestration, cleaning, and diagnostic operations for Morphir workspaces.

## Overview

Build operations coordinate compilation across multiple projects:

- **Dependency-ordered builds**: Compile projects in correct order
- **Parallel compilation**: Build independent projects concurrently
- **Incremental builds**: Only rebuild what changed
- **Diagnostic aggregation**: Unified error reporting across workspace

## Build Pipeline

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Resolve   │───►│    Order    │───►│   Compile   │───►│   Report    │
│ Dependencies│    │  Projects   │    │   (Parallel)│    │ Diagnostics │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

## Types

### BuildResult

```gleam
/// Result of a workspace build
pub type BuildResult {
  BuildResult(
    /// Overall success/failure
    success: Bool,
    /// Per-project results
    projects: List(ProjectBuildResult),
    /// Total build duration (milliseconds)
    duration_ms: Int,
  )
}

/// Result for a single project
pub type ProjectBuildResult {
  ProjectBuildResult(
    /// Project name
    name: PackagePath,
    /// Build status
    status: BuildStatus,
    /// Compiled distribution (if successful)
    distribution: Option(Distribution),
    /// Compilation diagnostics
    diagnostics: List(Diagnostic),
    /// Build duration (milliseconds)
    duration_ms: Int,
  )
}

/// Build status for a project
pub type BuildStatus {
  /// Build succeeded with no issues
  Ok
  /// Build succeeded with warnings
  Partial
  /// Build failed
  Failed
  /// Build was skipped (up to date)
  Skipped
}
```

### Diagnostic

```gleam
/// Compilation diagnostic
pub type Diagnostic {
  Diagnostic(
    /// Severity level
    severity: Severity,
    /// Error/warning code
    code: String,
    /// Human-readable message
    message: String,
    /// Source location
    location: Option(SourceLocation),
    /// Suggested fixes
    hints: List(String),
  )
}

pub type Severity {
  Error
  Warning
  Info
  Hint
}

pub type SourceLocation {
  SourceLocation(
    /// File path (relative to workspace)
    file: String,
    /// Start line (1-indexed)
    start_line: Int,
    /// Start column (1-indexed)
    start_col: Int,
    /// End line
    end_line: Int,
    /// End column
    end_col: Int,
  )
}
```

## Operations

### Build All

Builds all projects in the workspace.

#### Behavior

1. Resolve all dependencies
2. Compute build order (topological sort)
3. Build projects in parallel where possible
4. Aggregate diagnostics
5. Return combined result

#### Build Order

Projects are built in dependency order:

```
Level 0 (no deps):     core
Level 1 (→ core):      domain, utils
Level 2 (→ domain):    api, cli
```

Projects at the same level can be built in parallel.

#### WIT Interface

```wit
/// Build all projects in workspace
build-all: func() -> result<list<tuple<package-path, distribution>>, workspace-error>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/buildAll",
  "params": {}
}
```

**Response:**
```json
{
  "result": {
    "success": true,
    "projects": [
      {
        "name": "my-org/core",
        "status": "ok",
        "distribution": { "..." },
        "diagnostics": [],
        "durationMs": 523
      },
      {
        "name": "my-org/domain",
        "status": "partial",
        "distribution": { "..." },
        "diagnostics": [
          {
            "severity": "warning",
            "code": "W001",
            "message": "Unused import: List.Extra",
            "location": {
              "file": "packages/domain/src/User.elm",
              "startLine": 5,
              "startCol": 1,
              "endLine": 5,
              "endCol": 25
            }
          }
        ],
        "durationMs": 1247
      }
    ],
    "durationMs": 1823
  }
}
```

#### CLI

```bash
morphir build                    # Build all
morphir build --parallel 4       # Limit parallelism
morphir build --project my-org/api   # Build single project
```

### Clean

Removes build artifacts and caches.

#### Behavior

1. If project specified: clean that project only
2. If no project: clean entire workspace
3. Remove `.morphir-dist/` directories
4. Optionally remove dependency cache

#### WIT Interface

```wit
/// Clean build artifacts
clean: func(
    /// Specific project, or all if none
    project: option<package-path>,
) -> result<_, workspace-error>;
```

#### JSON-RPC

**Request (single project):**
```json
{
  "method": "workspace/clean",
  "params": {
    "project": "my-org/domain"
  }
}
```

**Request (entire workspace):**
```json
{
  "method": "workspace/clean",
  "params": {}
}
```

**Request (include dependency cache):**
```json
{
  "method": "workspace/clean",
  "params": {
    "includeDeps": true
  }
}
```

#### CLI

```bash
morphir clean                    # Clean all
morphir clean my-org/domain      # Clean one project
morphir clean --deps             # Also clean dependency cache
```

### Get Diagnostics

Returns all current diagnostics across the workspace.

#### WIT Interface

```wit
/// Get workspace-wide diagnostics
get-diagnostics: func() -> list<tuple<package-path, list<diagnostic>>>;
```

#### JSON-RPC

**Request:**
```json
{
  "method": "workspace/getDiagnostics",
  "params": {}
}
```

**Response:**
```json
{
  "result": {
    "my-org/core": [],
    "my-org/domain": [
      {
        "severity": "error",
        "code": "E001",
        "message": "Type mismatch: expected Int, got String",
        "location": {
          "file": "packages/domain/src/Order.elm",
          "startLine": 42,
          "startCol": 15,
          "endLine": 42,
          "endCol": 28
        },
        "hints": ["Try using String.toInt to convert"]
      }
    ],
    "my-org/api": [
      {
        "severity": "warning",
        "code": "W002",
        "message": "Function 'oldHelper' is deprecated",
        "location": { "..." }
      }
    ]
  }
}
```

## Incremental Builds

### Change Detection

Changes are detected via:

1. **File modification time**: Compare against last build
2. **Content hash**: SHA-256 of source files
3. **Dependency changes**: Rebuild if dependency was rebuilt

### Build Cache

```
.morphir/
└── cache/
    ├── my-org/
    │   └── domain/
    │       ├── manifest.json    # Build metadata
    │       ├── source-hash      # Hash of all sources
    │       └── ir-cache/        # Cached IR fragments
```

### Manifest Format

```json
{
  "version": "1.0.0",
  "lastBuild": "2026-01-16T12:00:00Z",
  "sourceHash": "sha256:abc123...",
  "files": {
    "src/User.elm": {
      "hash": "sha256:def456...",
      "lastModified": "2026-01-16T11:30:00Z"
    }
  },
  "dependencies": {
    "my-org/core": "sha256:ghi789..."
  }
}
```

## Parallel Execution

### Strategy

```
Sequential (dependencies):    core ──► domain ──► api
                                        │
Parallel (independent):       core ──►─┬► domain ──► api
                                       └► utils ───►─┘
```

### Configuration

```toml
# morphir.toml
[build]
parallel = true         # Enable parallel builds
max-workers = 4         # Maximum parallel compilations
fail-fast = false       # Continue on errors (or stop immediately)
```

## Error Recovery

### Partial Builds

When a project fails, dependent projects can still attempt to build using the last successful IR:

```
core (ok) ──► domain (FAILED) ──► api (uses cached domain IR)
```

### Diagnostic-Only Mode

Build without generating artifacts (fast validation):

```bash
morphir build --check-only
```

## Build Events

### workspace/onBuildStarted

```json
{
  "method": "workspace/onBuildStarted",
  "params": {
    "projects": ["my-org/core", "my-org/domain"],
    "incremental": true
  }
}
```

### workspace/onBuildProgress

```json
{
  "method": "workspace/onBuildProgress",
  "params": {
    "project": "my-org/domain",
    "phase": "compiling",
    "progress": 0.45,
    "currentFile": "src/Domain/User.elm"
  }
}
```

### workspace/onBuildComplete

```json
{
  "method": "workspace/onBuildComplete",
  "params": {
    "success": true,
    "projects": ["my-org/core", "my-org/domain"],
    "durationMs": 2341,
    "diagnosticCount": {
      "errors": 0,
      "warnings": 3
    }
  }
}
```

## Best Practices

1. **Use Incremental Builds**: Avoid `clean` unless necessary
2. **Parallelize**: Enable parallel builds for faster compilation
3. **Fail Fast in CI**: Use `--fail-fast` in CI to stop on first error
4. **Cache Dependencies**: Keep dependency cache for faster rebuilds
5. **Check Before Push**: Run `morphir build --check-only` before committing
