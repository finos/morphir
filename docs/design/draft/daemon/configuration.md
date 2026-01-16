---
title: Configuration System
sidebar_label: Configuration
sidebar_position: 8
status: draft
---

# Configuration System

This module describes the Morphir configuration system design, covering project configuration, workspace configuration, and the merge/resolution rules.

## Overview

Morphir uses a unified configuration file (`morphir.toml`) that supports both single-project and multi-project (workspace) modes. The same file format handles:

- **Project mode**: Single project with its own configuration
- **Workspace mode**: Multiple projects with shared configuration

## Configuration File

All configuration lives in `morphir.toml` (or alternative locations). There is no separate workspace configuration file.

```
my-workspace/
├── morphir.toml              # Workspace-level config (has [workspace] section)
├── .config/
│   └── morphir/
│       └── config.toml       # Workspace-level shared config (gitignored secrets, local overrides)
├── packages/
│   ├── core/
│   │   ├── morphir.toml      # Project-level config
│   │   └── src/
│   └── domain/
│       ├── morphir.toml      # Project-level config
│       └── src/
```

### Mode Detection

The presence of specific sections determines the mode:

| Section Present | Mode | Behavior |
|-----------------|------|----------|
| `[project]` only | Project | Single project configuration |
| `[workspace]` | Workspace | Multi-project with member discovery |
| Both | Workspace + Root Project | Workspace with the root also being a project |

## Module Reference

| Module | Description |
|--------|-------------|
| [morphir.toml](./morphir-toml.md) | Configuration file structure and sections |
| [Workspace Mode](./workspace-mode.md) | Workspace-specific configuration and discovery |
| [Tasks](./tasks.md) | Task definitions and pre/post hooks |
| [Merge Rules](./merge-rules.md) | Configuration inheritance and merge behavior |
| [Environment](./environment.md) | Environment variables and runtime overrides |

## Key Sections

### Core Configuration

```toml
[morphir]
version = "^4.0.0"           # IR version constraint

[project]
name = "my-org/my-project"
version = "1.0.0"
source_directory = "src"
exposed_modules = ["Domain.User", "Domain.Order"]
```

### Workspace Configuration

```toml
[workspace]
output_dir = ".morphir"
members = ["packages/*"]     # Glob patterns for project discovery
exclude = ["packages/old-*"]
default_member = "packages/core"
```

### Build & Codegen

```toml
[ir]
format_version = 4
strict_mode = false

[codegen]
targets = ["typescript", "scala"]
output_format = "pretty"
```

### Tasks

Built-in tasks (`build`, `test`, `check`, `codegen`, `pack`, `publish`) work automatically. Users define custom tasks or hooks:

```toml
[tasks]
# Custom task
integration = "./scripts/integration-tests.sh"

# CI pipeline using built-in tasks
[tasks.ci]
description = "Run CI pipeline"
depends = ["check", "test", "build"]

# Pre/post hooks extend built-in tasks
[tasks."post:build"]
run = "prettier --write .morphir-dist/"
```

See [Tasks](./tasks.md) for full documentation.

## Configuration Locations

Configuration can be placed in multiple locations:

| Location | Scope | Typical Use |
|----------|-------|-------------|
| `./morphir.toml` | Project/Workspace | Primary configuration (committed) |
| `./.morphir/morphir.toml` | Project/Workspace | Alternative location |
| `./.config/morphir/config.toml` | Workspace | Local overrides, secrets (often gitignored) |
| `~/.config/morphir/config.toml` | User | User-level defaults and preferences |
| `/etc/morphir/config.toml` | System | System-wide defaults |

## Configuration Resolution

Configuration is resolved from multiple sources with the following precedence (highest first):

1. **Command-line flags**: `--config-key=value`
2. **Environment variables**: `MORPHIR__SECTION__KEY`
3. **Workspace local config**: `./.config/morphir/config.toml`
4. **Project/Workspace config**: `./morphir.toml` or `./.morphir/morphir.toml`
5. **Parent configs**: Walk up directory tree (for nested projects)
6. **User config**: `~/.config/morphir/config.toml`
7. **System config**: `/etc/morphir/config.toml`

The `.config/morphir/config.toml` within a workspace is useful for:
- Local developer overrides (gitignored)
- Secrets and credentials
- Machine-specific paths
- CI/CD environment-specific settings

See [Merge Rules](./merge-rules.md) for detailed merge semantics.

## Workspace vs Project Config

| Aspect | Project Config | Workspace Config |
|--------|----------------|------------------|
| Scope | Single package | Multiple packages |
| File | `morphir.toml` in project dir | `morphir.toml` at workspace root |
| Key section | `[project]` | `[workspace]` |
| Dependencies | Per-project | Can be shared |
| Build output | Per-project `.morphir-dist/` | Workspace `.morphir/` |

## Design Principles

1. **Single File Format**: One `morphir.toml` format for all modes
2. **Explicit Over Implicit**: Workspace mode requires explicit `[workspace]` section
3. **Inheritance**: Child projects inherit from parent workspace config
4. **Override**: More specific config overrides less specific
5. **Simple Tasks**: Tasks are shell commands, not a DSL; pre/post hooks extend built-in commands
6. **Separation of Concerns**: Committed config vs local overrides (`.config/`)

## Related Documents

- [morphir.toml Specification](/docs/spec/morphir-toml/morphir-toml-specification) - Formal spec
- [Merge Rules](/docs/spec/morphir-toml/morphir-toml-merge-rules) - Merge behavior spec
- [Workspace Operations](./README.md) - Runtime workspace management
