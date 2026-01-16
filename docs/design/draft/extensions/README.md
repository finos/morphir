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

## Getting Started with Extensions

Extension development starts with a minimal "info" extension that verifies connectivity before adding features.

### Minimal Extension (Hello World)

Every extension must implement the `info` interface - this is the only required interface:

```wit
package morphir:extension@0.4.0;

/// Required interface - all extensions must implement this
interface info {
    /// Extension metadata
    record extension-info {
        /// Unique identifier (e.g., "spark-codegen")
        id: string,
        /// Human-readable name
        name: string,
        /// Version (semver)
        version: string,
        /// Description
        description: string,
        /// Author/maintainer
        author: option<string>,
        /// Homepage/repository URL
        homepage: option<string>,
        /// License identifier (SPDX)
        license: option<string>,
    }

    /// Return extension metadata
    get-info: func() -> extension-info;

    /// Health check - return true if extension is ready
    ping: func() -> bool;
}
```

**Minimal Extension (Rust):**
```rust
use morphir_extension::info::{ExtensionInfo, Info};

struct MyExtension;

impl Info for MyExtension {
    fn get_info() -> ExtensionInfo {
        ExtensionInfo {
            id: "my-extension".to_string(),
            name: "My First Extension".to_string(),
            version: "0.1.0".to_string(),
            description: "A minimal Morphir extension".to_string(),
            author: Some("My Name".to_string()),
            homepage: Some("https://github.com/me/my-extension".to_string()),
            license: Some("Apache-2.0".to_string()),
        }
    }

    fn ping() -> bool {
        true  // Extension is ready
    }
}
```

### Extension Discovery

The CLI can list and inspect all registered extensions:

```bash
# List all extensions
morphir extension list

# Output:
# NAME              VERSION   TYPE      CAPABILITIES
# spark-codegen     1.2.0     codegen   generate, streaming, incremental
# elm-frontend      0.19.1    frontend  compile, diagnostics
# my-extension      0.1.0     unknown   (info only)

# Detailed info about an extension
morphir extension info spark-codegen

# Output:
# spark-codegen v1.2.0
#   Type:         codegen
#   Description:  Generate Apache Spark DataFrame code from Morphir IR
#   Author:       Morphir Contributors
#   Homepage:     https://github.com/finos/morphir-spark
#   License:      Apache-2.0
#
#   Capabilities:
#     ✓ codegen/generate
#     ✓ codegen/generate-streaming
#     ✓ codegen/generate-incremental
#     ✓ codegen/generate-module
#     ✓ codegen/options-schema
#
#   Targets: spark
#
#   Options:
#     spark_version  string  "3.5"   Spark version to target
#     scala_version  string  "2.13"  Scala version to target

# Verify extension connectivity
morphir extension ping spark-codegen
# spark-codegen: OK (2ms)

# Ping all extensions
morphir extension ping --all
# spark-codegen:  OK (2ms)
# elm-frontend:   OK (1ms)
# my-extension:   OK (1ms)
```

### JSON-RPC Methods

**List Extensions:**
```json
{
  "jsonrpc": "2.0",
  "id": "list-001",
  "method": "extension/list",
  "params": {}
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "list-001",
  "result": {
    "extensions": [
      {
        "id": "spark-codegen",
        "name": "Spark Code Generator",
        "version": "1.2.0",
        "type": "codegen",
        "source": { "path": "./extensions/spark-codegen.wasm" },
        "capabilities": ["generate", "generate-streaming", "generate-incremental"]
      },
      {
        "id": "my-extension",
        "name": "My First Extension",
        "version": "0.1.0",
        "type": null,
        "source": { "path": "./extensions/my-extension.wasm" },
        "capabilities": []
      }
    ]
  }
}
```

**Get Extension Info:**
```json
{
  "jsonrpc": "2.0",
  "id": "info-001",
  "method": "extension/info",
  "params": {
    "extension": "spark-codegen"
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "info-001",
  "result": {
    "id": "spark-codegen",
    "name": "Spark Code Generator",
    "version": "1.2.0",
    "description": "Generate Apache Spark DataFrame code from Morphir IR",
    "author": "Morphir Contributors",
    "homepage": "https://github.com/finos/morphir-spark",
    "license": "Apache-2.0",
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
      "spark_version": {
        "type": "string",
        "default": "3.5",
        "description": "Spark version to target"
      },
      "scala_version": {
        "type": "string",
        "default": "2.13",
        "description": "Scala version to target"
      }
    }
  }
}
```

**Ping Extension:**
```json
{
  "jsonrpc": "2.0",
  "id": "ping-001",
  "method": "extension/ping",
  "params": {
    "extension": "spark-codegen"
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "ping-001",
  "result": {
    "extension": "spark-codegen",
    "status": "ok",
    "latency_ms": 2
  }
}
```

### Extension Development Workflow

1. **Start minimal**: Implement only `info` interface
2. **Verify connectivity**: `morphir extension ping my-extension`
3. **Check registration**: `morphir extension list`
4. **Add capabilities incrementally**: One interface at a time
5. **Test each capability**: Verify with CLI before adding more

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
