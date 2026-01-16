---
title: Morphir Extensions
sidebar_label: Overview
sidebar_position: 1
status: draft
tracking:
  beads: [morphir-go-772, morphir-010]
  github_issues: [399]
  github_discussions: []
---

# Morphir Extensions

The extension architecture for adding capabilities to Morphir via WASM components and the task system.

## Tracking

| Type | References |
|------|------------|
| **Beads** | morphir-go-772 (task execution), morphir-010 (CLI extensions) |
| **GitHub Issues** | [#399](https://github.com/finos/morphir/issues/399) (task/target execution engine) |

## Overview

Morphir Extensions enable:

- **Custom Code Generators**: Add new backend targets (Spark, Scala, etc.)
- **Custom Frontends**: Support new source languages
- **Additional Tasks**: Register new intrinsic tasks
- **Build Automation**: Pre/post hooks for built-in commands
- **Protocol Integration**: JSON-RPC based communication

## Documents

| Document | Status | Description |
|----------|--------|-------------|
| [WASM Components](./wasm-components.md) | Draft | Component model integration and WIT interfaces |
| [Tasks](./tasks.md) | Draft | Task system, dependencies, and hooks |

## Extension Types

### WASM Components

Extensions implemented as WASM components using the Component Model:

```wit
package morphir:extension@0.4.0;

interface codegen {
    /// Generate code for a target language
    generate: func(ir: distribution, options: codegen-options) -> result<generated-files, codegen-error>;
}
```

**Benefits:**
- Language agnostic (Rust, Go, C, etc.)
- Sandboxed execution
- Capability-based permissions
- Hot-reloadable

### Tasks

User-defined or extension-provided commands:

```toml
# Built-in tasks work automatically
# Extensions can register additional intrinsic tasks

[tasks.ci]
description = "Run CI pipeline"
depends = ["check", "test", "build"]

[tasks."post:build"]
run = "prettier --write .morphir-dist/"
```

**Task Types:**
- **Built-in**: `build`, `test`, `check`, `codegen`, `pack`, `publish`
- **Extension-provided**: Registered by WASM components
- **User-defined**: Shell commands in `[tasks]`

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Morphir CLI/Daemon                    │
├─────────────────────────────────────────────────────────┤
│                   Extension Host                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │ WASM Runtime│  │ Task Runner │  │  JSON-RPC   │     │
│  │ (wasmtime)  │  │             │  │  Protocol   │     │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘     │
└─────────┼────────────────┼────────────────┼─────────────┘
          │                │                │
          ▼                ▼                ▼
    ┌───────────┐    ┌───────────┐    ┌───────────┐
    │  Codegen  │    │  Custom   │    │  External │
    │ Extension │    │   Tasks   │    │  Process  │
    └───────────┘    └───────────┘    └───────────┘
```

## Extension Points

| Point | Mechanism | Use Case |
|-------|-----------|----------|
| Code Generation | WASM component | Custom backend targets |
| Frontend | WASM component | New source languages |
| Validation | WASM component | Custom analyzers |
| Tasks | Task definition | Build automation |
| Hooks | Pre/post tasks | Extend built-in commands |

## Task System

### Built-in Tasks

These work automatically without configuration:

| Task | Description |
|------|-------------|
| `build` | Compile project to IR |
| `test` | Run tests |
| `check` | Lint and validate |
| `codegen` | Generate code for targets |
| `pack` | Create distributable package |
| `publish` | Publish to registry |

### Pre/Post Hooks

Extend built-in tasks with hooks:

```toml
[tasks."pre:build"]
run = "echo 'Starting build...'"

[tasks."post:build"]
run = "prettier --write .morphir-dist/"

[tasks."post:codegen"]
run = "./scripts/post-codegen.sh"
```

### Task Dependencies

Chain tasks together:

```toml
[tasks.ci]
description = "Full CI pipeline"
depends = ["check", "test", "build", "pack"]

[tasks.release]
depends = ["ci"]
run = "morphir publish --backend github"
```

## Configuration

### Registering Extensions

```toml
# morphir.toml

[extensions]
# WASM component extensions
codegen-spark = { path = "./extensions/spark-codegen.wasm" }
codegen-scala = { url = "https://extensions.morphir.dev/scala-codegen-1.0.0.wasm" }

# Extension configuration
[extensions.codegen-spark.config]
spark_version = "3.5"
```

### Extension Capabilities

Extensions declare required capabilities:

```wit
world codegen-extension {
    // Required imports
    import morphir:ir/types;
    import morphir:ir/values;

    // Provided exports
    export morphir:extension/codegen;
}
```

## Related

- **[IR v4](../ir/README.md)** - Intermediate representation format
- **[Morphir Daemon](../daemon/README.md)** - Workspace and build management
- **[Deprecated: Toolchain Framework](../../deprecated/README.md)** - Superseded design
