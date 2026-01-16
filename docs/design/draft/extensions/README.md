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

Extensions are **capability-based** - they declare which features they implement, allowing incremental development. An extension doesn't need to implement everything; it exports only what it supports.

```wit
world codegen-extension {
    // Required imports (what the extension needs)
    import morphir:ir/types;
    import morphir:ir/values;

    // Provided exports (what the extension offers)
    export morphir:extension/codegen;

    // Optional exports (implement incrementally)
    // export morphir:extension/codegen-streaming;
    // export morphir:extension/codegen-incremental;
}
```

## Capability-Based Design

Extensions implement features incrementally through optional interfaces:

### Frontend Capabilities

| Capability | Interface | Description |
|------------|-----------|-------------|
| **Basic** | `frontend/compile` | Compile source to IR (required) |
| **Streaming** | `frontend/compile-streaming` | Stream module-by-module results |
| **Incremental** | `frontend/compile-incremental` | Recompile only changed files |
| **Fragment** | `frontend/compile-fragment` | Compile code fragments (IDE) |
| **Diagnostics** | `frontend/diagnostics` | Rich error messages with fixes |

**Minimal Frontend:**
```wit
world minimal-frontend {
    import morphir:ir/types;
    export frontend/compile;  // Only basic compilation
}
```

**Full-Featured Frontend:**
```wit
world full-frontend {
    import morphir:ir/types;
    export frontend/compile;
    export frontend/compile-streaming;
    export frontend/compile-incremental;
    export frontend/compile-fragment;
    export frontend/diagnostics;
}
```

### Backend/Codegen Capabilities

| Capability | Interface | Description |
|------------|-----------|-------------|
| **Basic** | `codegen/generate` | Generate code for target (required) |
| **Streaming** | `codegen/generate-streaming` | Stream file-by-file output |
| **Incremental** | `codegen/generate-incremental` | Regenerate only changed modules |
| **Module-level** | `codegen/generate-module` | Generate single module |
| **Options** | `codegen/options-schema` | Declare configurable options |

**Minimal Backend:**
```wit
world minimal-backend {
    import morphir:ir/distributions;
    export codegen/generate;  // Only basic generation
}
```

### Capability Negotiation

The daemon queries extension capabilities at load time:

**JSON-RPC:**
```json
{
  "jsonrpc": "2.0",
  "id": "caps-001",
  "method": "extension/capabilities",
  "params": {
    "extension": "codegen-spark"
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "caps-001",
  "result": {
    "extension": "codegen-spark",
    "type": "codegen",
    "capabilities": {
      "codegen/generate": true,
      "codegen/generate-streaming": true,
      "codegen/generate-incremental": true,
      "codegen/generate-module": true,
      "codegen/options-schema": true
    },
    "targets": ["spark"],
    "options": {
      "spark_version": { "type": "string", "default": "3.5" },
      "scala_version": { "type": "string", "default": "2.13" }
    }
  }
}
```

### Graceful Degradation

When an extension lacks a capability, Morphir falls back gracefully:

| Missing Capability | Fallback Behavior |
|-------------------|-------------------|
| `compile-streaming` | Compile all at once, return single result |
| `compile-incremental` | Full recompilation on every change |
| `generate-streaming` | Generate all files, return at end |
| `generate-module` | Generate full distribution |

**CLI Feedback:**
```bash
$ morphir codegen --target spark --stream
Warning: spark-codegen does not support streaming, generating all at once...
```

### Incremental Implementation Path

Recommended order for implementing extension capabilities:

**Frontend:**
1. `compile` - Basic compilation (MVP)
2. `diagnostics` - Better error messages
3. `compile-incremental` - Watch mode support
4. `compile-streaming` - Large project support
5. `compile-fragment` - IDE integration

**Backend:**
1. `generate` - Basic codegen (MVP)
2. `options-schema` - Configurable output
3. `generate-module` - Granular generation
4. `generate-incremental` - Efficient rebuilds
5. `generate-streaming` - Large project support

## Related

- **[IR v4](../ir/README.md)** - Intermediate representation format
- **[Morphir Daemon](../daemon/README.md)** - Workspace and build management
- **[Deprecated: Toolchain Framework](../../deprecated/README.md)** - Superseded design
