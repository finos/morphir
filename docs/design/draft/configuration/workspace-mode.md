---
title: Workspace Mode
sidebar_label: Workspace Mode
sidebar_position: 2
---

# Workspace Mode Configuration

This document describes workspace-specific configuration in `morphir.toml`.

## Overview

A workspace is a collection of related Morphir projects managed together. Workspace mode is activated by including a `[workspace]` section in the configuration file.

## Configuration File Locations

The configuration file can be placed in any of these equivalent locations:

| Location | Notes |
|----------|-------|
| `morphir.toml` | Root level, most visible |
| `.morphir/config.toml` | Hidden directory variant |
| `.morphir/morphir.toml` | Hidden directory variant |
| `.config/morphir/config.toml` | XDG-style location |

All locations use the same format and are functionally equivalent. The CLI searches in this order and uses the first file found.

## Enabling Workspace Mode

```toml
# morphir.toml (or any equivalent location)

[workspace]
members = ["packages/*"]
```

The presence of `[workspace]` section triggers workspace mode, enabling:
- Multi-project discovery and management
- Shared dependency resolution
- Coordinated builds
- Workspace-wide configuration inheritance

## Workspace Section

### `[workspace]`

```toml
[workspace]
# Workspace root directory (empty = directory containing this file)
root = ""

# Output directory for workspace-level artifacts
output_dir = ".morphir"

# Glob patterns for discovering member projects
members = [
    "packages/*",
    "libs/*",
    "apps/*"
]

# Patterns to exclude from discovery
exclude = [
    "packages/deprecated-*",
    "packages/experimental/*"
]

# Default member when no project is specified
default_member = "packages/core"
```

### Field Reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `root` | string | `""` | Workspace root directory. Empty means the directory containing the config file. |
| `output_dir` | string | `".morphir"` | Output directory for generated artifacts, relative to workspace root. |
| `members` | string[] | `[]` | Glob patterns for discovering workspace member projects. Each matching directory with a `morphir.toml` becomes a member. |
| `exclude` | string[] | `[]` | Glob patterns excluded from member discovery. |
| `default_member` | string | `""` | Default member path when none is specified in commands. |

## Project Discovery

Projects are discovered by scanning directories matching `members` patterns:

```
workspace/
├── morphir.toml              # [workspace] members = ["packages/*", "apps/*"]
├── packages/
│   ├── core/                 # ✓ Discovered (matches packages/*)
│   │   └── morphir.toml
│   ├── domain/               # ✓ Discovered (matches packages/*)
│   │   └── morphir.toml
│   └── deprecated-old/       # ✗ Excluded (matches deprecated-*)
│       └── morphir.toml
├── apps/
│   └── api/                  # ✓ Discovered (matches apps/*)
│       └── morphir.toml
└── tools/
    └── generator/            # ✗ Not discovered (no matching pattern)
        └── morphir.toml
```

### Discovery Algorithm

1. Resolve `members` globs relative to workspace root
2. Filter out paths matching `exclude` patterns
3. For each remaining directory, check for configuration file
4. Parse project config and register as workspace member

## Workspace + Project Mode

A workspace root can also be a project itself:

```toml
# morphir.toml - Both workspace and project

[workspace]
members = ["packages/*"]

[project]
name = "my-org/workspace-root"
version = "1.0.0"
source_directory = "src"
```

This is useful when:
- The workspace root contains shared code
- You want a "meta" project that depends on all members
- Monorepo patterns where root is also a package

## Configuration Inheritance

Member projects inherit configuration from the workspace:

```toml
# workspace/morphir.toml
[workspace]
members = ["packages/*"]

[ir]
format_version = 4
strict_mode = true

[codegen]
targets = ["typescript"]
```

```toml
# workspace/packages/core/morphir.toml
[project]
name = "my-org/core"
version = "1.0.0"

# Inherits [ir] and [codegen] from workspace
# Can override specific fields:
[codegen]
targets = ["typescript", "scala"]  # Overrides workspace default
```

### Inheritance Rules

| Section | Inheritance Behavior |
|---------|---------------------|
| `[morphir]` | Merged (project can constrain further) |
| `[project]` | Not inherited (project-specific) |
| `[workspace]` | Not inherited (workspace-level only) |
| `[ir]` | Merged (project overrides workspace) |
| `[codegen]` | Merged (project overrides workspace) |
| `[cache]` | Merged |
| `[logging]` | Merged |
| `[toolchain.*]` | Merged (project can add/override) |
| `[tasks.*]` | Merged (project can add/override) |

## Shared Dependencies

Workspace-level dependencies can be defined for sharing across projects:

```toml
# workspace/morphir.toml
[workspace]
members = ["packages/*"]

[workspace.dependencies]
"morphir/sdk" = "^3.0.0"
"finos/morphir-json" = "^1.0.0"
```

Member projects reference shared dependencies:

```toml
# workspace/packages/domain/morphir.toml
[project]
name = "my-org/domain"

[dependencies]
"morphir/sdk" = { workspace = true }        # Use workspace version
"my-org/core" = { workspace = true }        # Local workspace member
"external/lib" = "^2.0.0"                   # Project-specific dependency
```

## CLI Workspace Awareness

The CLI is **workspace-aware** regardless of the current working directory. When running commands from any subdirectory within a workspace, the CLI:

1. **Walks up** the directory tree to find the workspace root (directory with `[workspace]` in config)
2. **Loads** workspace configuration and discovers all member projects
3. **Determines context** based on current directory:
   - If in a member project directory: operates on that project by default
   - If in workspace root: operates on workspace or default member
   - If in non-member subdirectory: operates in workspace context

### Workspace Discovery

```
workspace/                    # Workspace root (config has [workspace])
├── morphir.toml
├── packages/
│   ├── core/
│   │   └── morphir.toml     # Running `morphir build` here builds core
│   └── domain/
│       ├── morphir.toml
│       └── src/
│           └── User/        # Running `morphir build` here still builds domain
└── docs/                    # Running `morphir workspace list` here works
```

### Context Resolution

```bash
# From workspace root
~/workspace$ morphir build              # Builds default_member or prompts
~/workspace$ morphir workspace build    # Builds all members

# From member project
~/workspace/packages/core$ morphir build              # Builds core
~/workspace/packages/core$ morphir workspace build    # Builds all members
~/workspace/packages/core$ morphir workspace info     # Shows workspace info

# From deep within a project
~/workspace/packages/domain/src/User$ morphir build   # Builds domain
~/workspace/packages/domain/src/User$ morphir workspace list  # Lists all members

# From non-member directory within workspace
~/workspace/docs$ morphir workspace list              # Works - finds workspace root
~/workspace/docs$ morphir build                       # Error or uses default_member
```

### Explicit Workspace/Project Selection

```bash
# Override automatic detection
morphir build --project my-org/core     # Build specific project
morphir build --workspace               # Force workspace-wide operation
morphir build --no-workspace            # Force single-project mode (ignore workspace)
morphir --workspace-root /path/to/ws build  # Explicit workspace root
```

## Example: Full Workspace Configuration

```toml
# morphir.toml

[morphir]
version = "^4.0.0"

[workspace]
output_dir = ".morphir"
members = ["packages/*", "apps/*"]
exclude = ["packages/experimental-*"]
default_member = "packages/core"

[workspace.dependencies]
"morphir/sdk" = "^3.0.0"

[ir]
format_version = 4
strict_mode = false

[codegen]
targets = ["typescript"]
output_format = "pretty"

[cache]
enabled = true
dir = ".morphir/cache"

[logging]
level = "info"
format = "text"

[toolchain.morphir-elm]
enabled = true

[toolchain.morphir-elm.tasks.make]
exec = "morphir-elm"
args = ["make", "-o", "{output_dir}"]
```

## Best Practices

1. **Flat Structure**: Prefer flat `packages/*` over deeply nested hierarchies
2. **Explicit Members**: Use explicit patterns rather than catch-all `**/*`
3. **Shared Config**: Put common settings at workspace level
4. **Default Member**: Set `default_member` for common single-project operations
5. **Workspace Commands**: Use `morphir workspace` prefix for explicit workspace operations
