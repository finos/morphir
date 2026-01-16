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
| [WASM Components](./wasm-component.md) | Draft | Component model integration and WIT interfaces |
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

## Extension Formats

Extensions can be distributed in several formats:

| Format | Extension | Description |
|--------|-----------|-------------|
| **WASM Component** | `.wasm` | WebAssembly component (sandboxed) |
| **Executable** | Platform-specific | JSON-RPC over stdio executable |
| **Package** | `.morphir-ext.tgz` | Tar gzipped bundle with manifest |
| **Directory** | `*/extension.toml` | Unpacked extension with manifest |

### WASM Component Extensions

Sandboxed WebAssembly components using the Component Model:

```
extensions/
└── spark-codegen.wasm    # Self-contained WASM component
```

### Executable Extensions (JSON-RPC)

Native executables that communicate via JSON-RPC over stdio:

```
extensions/
├── my-backend                    # Unix executable
├── my-backend.exe                # Windows executable
└── my-frontend/
    ├── extension.toml
    └── bin/
        ├── frontend-linux-amd64    # Linux
        ├── frontend-darwin-amd64   # macOS Intel
        ├── frontend-darwin-arm64   # macOS Apple Silicon
        └── frontend-windows-amd64.exe
```

**Platform Resolution:**

The daemon selects the appropriate executable based on OS and architecture:

| OS | Architecture | Search Pattern |
|----|--------------|----------------|
| Linux | amd64 | `*-linux-amd64`, `*-linux-x86_64`, `*` |
| Linux | arm64 | `*-linux-arm64`, `*-linux-aarch64`, `*` |
| macOS | amd64 | `*-darwin-amd64`, `*-darwin-x86_64`, `*` |
| macOS | arm64 | `*-darwin-arm64`, `*-darwin-aarch64`, `*` |
| Windows | amd64 | `*.exe`, `*-windows-amd64.exe` |

**Executable Manifest:**
```toml
# extension.toml
[extension]
id = "my-backend"
name = "My Backend"
version = "1.0.0"
type = "codegen"

# Executable configuration
[extension.executable]
# Platform-specific binaries
[extension.executable.bin]
"linux-amd64" = "bin/backend-linux-amd64"
"linux-arm64" = "bin/backend-linux-arm64"
"darwin-amd64" = "bin/backend-darwin-amd64"
"darwin-arm64" = "bin/backend-darwin-arm64"
"windows-amd64" = "bin/backend-windows-amd64.exe"

# Or single cross-platform binary (e.g., Go, Java)
# command = "bin/backend"

# Arguments passed to executable
args = ["--mode", "jsonrpc"]

# Environment variables
[extension.executable.env]
LOG_LEVEL = "info"
```

### Package Format (`.morphir-ext.tgz`)

Distributable tar gzipped packages:

```bash
# Package structure (when extracted)
spark-codegen-1.2.0/
├── extension.toml           # Required: manifest
├── codegen.wasm             # WASM component
├── README.md                # Documentation
├── LICENSE
└── examples/
    └── basic.elm
```

**Creating a Package:**
```bash
# Package an extension
morphir extension pack ./spark-codegen/
# → spark-codegen-1.2.0.morphir-ext.tgz

# Package with specific output
morphir extension pack ./spark-codegen/ -o dist/
```

**Installing a Package:**
```bash
# Install from package file
morphir extension install spark-codegen-1.2.0.morphir-ext.tgz
# Extracts to: .morphir/extensions/spark-codegen/

# Install from URL
morphir extension install https://example.com/spark-codegen-1.2.0.morphir-ext.tgz
```

**Package Manifest:**
```toml
# extension.toml in package
[extension]
id = "spark-codegen"
name = "Spark Code Generator"
version = "1.2.0"
description = "Generate Apache Spark DataFrame code from Morphir IR"
author = "Morphir Contributors"
license = "Apache-2.0"
homepage = "https://github.com/finos/morphir-spark"

# Component type and file
type = "codegen"
component = "codegen.wasm"  # WASM component
# OR
# executable = "bin/codegen"  # Native executable

targets = ["spark"]

# Dependencies on other extensions (optional)
[extension.dependencies]
morphir-ir = "^4.0.0"

# Configuration schema
[extension.options]
spark_version = { type = "string", default = "3.5", description = "Spark version" }
scala_version = { type = "string", default = "2.13", description = "Scala version" }
```

## Extension Discovery Locations

Extensions are discovered from multiple locations, in order of precedence:

### Discovery Order

1. **Explicit configuration** (`morphir.toml`)
2. **Workspace extensions** (`.morphir/extensions/`)
3. **User extensions** (`$XDG_DATA_HOME/morphir/extensions/`)
4. **System extensions** (`/usr/share/morphir/extensions/` or platform equivalent)

### Workspace Extensions

```
my-workspace/
├── morphir.toml
├── .morphir/
│   ├── extensions/                    # Auto-discovered
│   │   ├── spark-codegen.wasm         # WASM component
│   │   ├── my-backend                  # Executable (Unix)
│   │   ├── my-backend.exe              # Executable (Windows)
│   │   ├── flink-codegen/              # Directory extension
│   │   │   ├── extension.toml
│   │   │   └── codegen.wasm
│   │   └── custom-frontend/            # Executable extension
│   │       ├── extension.toml
│   │       └── bin/
│   │           ├── frontend-linux-amd64
│   │           └── frontend-darwin-arm64
│   ├── cache/
│   └── deps/
```

### User Extensions (Global)

```bash
# Linux/macOS
$XDG_DATA_HOME/morphir/extensions/
~/.local/share/morphir/extensions/      # Fallback

# macOS alternative
~/Library/Application Support/morphir/extensions/

# Windows
%LOCALAPPDATA%\morphir\extensions\
```

### System Extensions

```bash
# Linux
/usr/share/morphir/extensions/
/usr/local/share/morphir/extensions/

# macOS
/Library/Application Support/morphir/extensions/

# Windows
%PROGRAMDATA%\morphir\extensions\
```

### Explicit Configuration

Override or supplement auto-discovery in `morphir.toml`:

```toml
[extensions]
# WASM component (explicit path)
spark-codegen = { path = "./custom/spark-codegen.wasm" }

# Executable with command
my-backend = { command = "./bin/my-backend", args = ["--mode", "jsonrpc"] }

# URL (downloaded and cached)
flink-codegen = { url = "https://extensions.morphir.dev/flink-codegen-1.0.0.morphir-ext.tgz" }

# Disable auto-discovered extension
legacy-ext = { enabled = false }

# Override options for auto-discovered extension
[extensions.spark-codegen.config]
spark_version = "3.4"
```

### Discovery Resolution

```bash
# Show where each extension was discovered from
morphir extension list --show-source

# Output:
# NAME              VERSION   FORMAT       SOURCE
# spark-codegen     1.2.0     wasm         .morphir/extensions/spark-codegen.wasm
# my-backend        1.0.0     executable   .morphir/extensions/my-backend/
# flink-codegen     1.0.0     package      morphir.toml (url → cached)
# elm-frontend      0.19.1    wasm         ~/.local/share/morphir/extensions/
```

### JSON-RPC Extension Info (with Location)

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": "info-001",
  "method": "extension/info",
  "params": {
    "extension": "my-backend"
  }
}
```

**Response (Executable Extension):**
```json
{
  "jsonrpc": "2.0",
  "id": "info-001",
  "result": {
    "id": "my-backend",
    "name": "My Backend",
    "version": "1.0.0",
    "type": "codegen",
    "format": "executable",
    "source": {
      "type": "workspace",
      "path": ".morphir/extensions/my-backend/",
      "manifest": ".morphir/extensions/my-backend/extension.toml"
    },
    "executable": {
      "resolved": ".morphir/extensions/my-backend/bin/backend-darwin-arm64",
      "platform": "darwin-arm64",
      "args": ["--mode", "jsonrpc"]
    },
    "capabilities": {
      "codegen/generate": true,
      "codegen/generate-streaming": true
    }
  }
}
```

**Response (WASM Extension):**
```json
{
  "jsonrpc": "2.0",
  "id": "info-002",
  "result": {
    "id": "spark-codegen",
    "name": "Spark Code Generator",
    "version": "1.2.0",
    "type": "codegen",
    "format": "wasm",
    "source": {
      "type": "workspace",
      "path": ".morphir/extensions/spark-codegen.wasm"
    },
    "component": {
      "path": ".morphir/extensions/spark-codegen.wasm",
      "size": 245760
    },
    "capabilities": {
      "codegen/generate": true,
      "codegen/generate-streaming": true,
      "codegen/generate-incremental": true
    }
  }
}
```

### Extension Installation

```bash
# Install WASM component (to workspace)
morphir extension install spark-codegen.wasm
# → .morphir/extensions/spark-codegen.wasm

# Install package (extracts)
morphir extension install spark-codegen-1.2.0.morphir-ext.tgz
# → .morphir/extensions/spark-codegen/

# Install globally
morphir extension install --global spark-codegen.wasm
# → ~/.local/share/morphir/extensions/spark-codegen.wasm

# Install from URL
morphir extension install https://releases.example.com/spark-codegen-1.2.0.morphir-ext.tgz
# Downloads, verifies, extracts to .morphir/extensions/spark-codegen/
```

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

## Extension Development Playbook

A step-by-step guide for building Morphir extensions from scratch.

### Phase 1: Hello World (Day 1)

**Goal:** Verify your development setup and basic connectivity.

1. **Create project structure:**
```bash
mkdir my-morphir-extension && cd my-morphir-extension
# For Rust:
cargo new --lib . && cargo add wit-bindgen
# For Go:
go mod init my-morphir-extension && go get github.com/bytecodealliance/wasm-tools-go
```

2. **Implement minimal info interface:**
```rust
// src/lib.rs (Rust)
use morphir_extension::info::{ExtensionInfo, Info};

struct MyExtension;

impl Info for MyExtension {
    fn get_info() -> ExtensionInfo {
        ExtensionInfo {
            id: "my-extension".into(),
            name: "My Extension".into(),
            version: "0.1.0".into(),
            description: "My first Morphir extension".into(),
            author: Some("My Name".into()),
            homepage: None,
            license: Some("Apache-2.0".into()),
            types: vec![], // Will add later
        }
    }

    fn ping() -> bool { true }
}
```

3. **Build and install:**
```bash
# Build WASM component
cargo build --target wasm32-unknown-unknown --release
wasm-tools component new target/wasm32-unknown-unknown/release/my_extension.wasm -o my-extension.wasm

# Install to workspace
cp my-extension.wasm /path/to/workspace/.morphir/extensions/
```

4. **Verify installation:**
```bash
morphir extension list
# Should show: my-extension  0.1.0  unknown  (info only)

morphir extension ping my-extension
# Should show: my-extension: OK (Xms)

morphir extension info my-extension
# Should show full extension metadata
```

**Checkpoint:** Extension appears in list, responds to ping.

### Phase 2: Basic Functionality (Week 1)

**Goal:** Implement core functionality (compile or generate).

**For a Backend (Code Generator):**

1. **Add generator interface:**
```rust
use morphir_backend::generator::{Generator, GeneratorInfo, GenerationResult, Artifact};

impl Generator for MyExtension {
    fn info() -> GeneratorInfo {
        GeneratorInfo {
            name: "my-generator".into(),
            description: "Generates MyLang from Morphir IR".into(),
            version: "0.1.0".into(),
            target: TargetLanguage::Custom,
            custom_target: Some("mylang".into()),
            supported_granularities: vec![Granularity::Distribution],
        }
    }

    fn generate_distribution(dist: Distribution, options: GenerationOptions) -> GenerationResult {
        let artifacts = vec![
            Artifact {
                path: "output.mylang".into(),
                content: transform_to_mylang(&dist),
                source_map: None,
            }
        ];
        GenerationResult::Ok(artifacts)
    }
}
```

2. **Update extension type:**
```rust
fn get_info() -> ExtensionInfo {
    ExtensionInfo {
        // ... other fields
        types: vec![ExtensionType::Codegen],
    }
}
```

3. **Test with real IR:**
```bash
# Create test IR
morphir build /path/to/test-project

# Run your generator
morphir codegen --target mylang

# Check output
ls .morphir-dist/
```

**Checkpoint:** Generator produces valid output files.

### Phase 3: Production Quality (Month 1)

**Goal:** Add robustness features.

1. **Add capability discovery:**
```rust
impl Capabilities for MyExtension {
    fn list_capabilities() -> Vec<CapabilityInfo> {
        vec![
            CapabilityInfo {
                id: "codegen/generate".into(),
                description: "Basic code generation".into(),
                available: true,
            },
            CapabilityInfo {
                id: "codegen/options-schema".into(),
                description: "Configurable options".into(),
                available: true,
            },
        ]
    }

    fn get_targets() -> Vec<String> {
        vec!["mylang".into()]
    }

    fn get_options_schema() -> Vec<OptionSchema> {
        vec![
            OptionSchema {
                name: "indent".into(),
                option_type: OptionType::String,
                default_value: Some("\"  \"".into()),
                description: "Indentation string".into(),
                required: false,
            },
        ]
    }
}
```

2. **Add error handling:**
```rust
fn generate_distribution(dist: Distribution, options: GenerationOptions) -> GenerationResult {
    match try_generate(&dist, &options) {
        Ok(artifacts) => GenerationResult::Ok(artifacts),
        Err(e) => GenerationResult::Failed(vec![
            Diagnostic {
                severity: Severity::Error,
                code: "GEN001".into(),
                message: format!("Generation failed: {}", e),
                location: None,
            }
        ]),
    }
}
```

3. **Add module-level generation:**
```rust
fn generate_module(path: ModulePath, module: ModuleDefinition, ...) -> GenerationResult {
    // Generate for single module
}
```

**Checkpoint:** Extension handles errors gracefully, shows in `morphir extension info`.

### Phase 4: Advanced Features (Month 2+)

**Goal:** Add streaming and incremental support.

1. **Add streaming generation:**
```rust
impl backend::Streaming for MyExtension {
    fn generate_streaming(dist: Distribution, options: GenerationOptions) -> StreamHandle {
        // Start background generation
        let handle = start_generation_thread(dist, options);
        handle.id
    }

    fn poll_result(handle: StreamHandle) -> Option<ModuleGenerationResult> {
        // Return next completed module or None
    }
}
```

2. **Add incremental generation:**
```rust
impl backend::Incremental for MyExtension {
    fn generate_incremental(
        dist: Distribution,
        changed_modules: Vec<ModuleChange>,
        options: GenerationOptions,
    ) -> IncrementalGenerationResult {
        // Only regenerate affected modules
    }
}
```

3. **Update capabilities:**
```rust
fn list_capabilities() -> Vec<CapabilityInfo> {
    vec![
        // ... existing
        CapabilityInfo {
            id: "codegen/generate-streaming".into(),
            description: "Stream results as modules complete".into(),
            available: true,
        },
        CapabilityInfo {
            id: "codegen/generate-incremental".into(),
            description: "Regenerate only changed modules".into(),
            available: true,
        },
    ]
}
```

**Checkpoint:** `morphir codegen --target mylang --stream` shows incremental progress.

### Phase 5: Distribution (Month 3+)

**Goal:** Package and distribute your extension.

1. **Create package manifest:**
```toml
# extension.toml
[extension]
id = "my-extension"
name = "My Extension"
version = "1.0.0"
description = "Generate MyLang from Morphir IR"
author = "My Name"
license = "Apache-2.0"
homepage = "https://github.com/me/my-extension"

type = "codegen"
component = "my-extension.wasm"

targets = ["mylang"]

[extension.options]
indent = { type = "string", default = "  ", description = "Indentation" }
```

2. **Create distributable package:**
```bash
morphir extension pack ./
# Creates: my-extension-1.0.0.morphir-ext.tgz
```

3. **Test installation:**
```bash
# In a new workspace
morphir extension install my-extension-1.0.0.morphir-ext.tgz
morphir extension list
morphir codegen --target mylang
```

**Checkpoint:** Package installs cleanly on other machines.

### Development Tips

| Tip | Description |
|-----|-------------|
| **Start minimal** | Get `info` working before adding features |
| **Test early** | Use `morphir extension ping` after each change |
| **Check capabilities** | `morphir extension info <name>` shows what's detected |
| **Watch logs** | `morphir daemon logs` shows extension loading |
| **Iterate fast** | Hot-reload works with WASM components |

### Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| Extension not found | Wrong location | Check `.morphir/extensions/` |
| Ping fails | Missing info impl | Implement `info` interface |
| No capabilities | Not exported | Export `capabilities` interface |
| Codegen not triggered | Wrong target | Check `get_targets()` returns correct value |
| Missing options | No schema | Implement `get_options_schema()` |

### Testing Checklist

- [ ] `morphir extension list` shows your extension
- [ ] `morphir extension ping <name>` returns OK
- [ ] `morphir extension info <name>` shows correct metadata
- [ ] Capabilities appear in info output
- [ ] Target/language appears in info output
- [ ] Options schema appears in info output
- [ ] Basic generation produces valid output
- [ ] Errors produce helpful diagnostics
- [ ] Streaming shows incremental progress (if implemented)
- [ ] Incremental skips unchanged modules (if implemented)

## Future: Alternative Extension Runtimes

Beyond WASM components and native executables, several alternative extension runtimes are worth exploring for different trade-offs in performance, ease of authoring, and sandboxing.

### QuickJS

[QuickJS](https://bellard.org/quickjs/) is a small, embeddable JavaScript engine that could enable JavaScript/TypeScript extensions without WASM compilation.

**Potential Benefits:**
- Familiar language for web developers
- No compilation step (interpret directly)
- Small runtime footprint (~210KB)
- ES2020 support

**Example:**
```javascript
// extensions/my-codegen.js
export function getInfo() {
  return {
    id: "my-codegen",
    name: "My Code Generator",
    version: "1.0.0",
    type: "codegen"
  };
}

export function generate(ir, options) {
  // Transform IR to target code
  return {
    files: [
      { path: "output.ts", content: generateTypeScript(ir) }
    ]
  };
}
```

**Discovery:**
```
.morphir/extensions/
└── my-codegen.js    # Detected as QuickJS extension
```

### Javy (JavaScript → WASM)

[Javy](https://github.com/bytecodealliance/javy) compiles JavaScript to WASM, combining JavaScript's ease of authoring with WASM's sandboxing.

**Potential Benefits:**
- Write in JavaScript, run as sandboxed WASM
- Leverage existing JS ecosystem
- Same security model as WASM components
- AOT compilation for better performance than interpretation

**Workflow:**
```bash
# Author in JavaScript
cat > my-extension.js << 'EOF'
export function generate(ir) { ... }
EOF

# Compile to WASM
javy compile my-extension.js -o my-extension.wasm

# Install as normal WASM extension
morphir extension install my-extension.wasm
```

### Lua

[Lua](https://www.lua.org/) is a lightweight, embeddable scripting language often used for game scripting and configuration.

**Potential Benefits:**
- Extremely lightweight (~300KB)
- Fast startup time
- Simple, learnable syntax
- Battle-tested embedding API
- Good for simple transformations

**Example:**
```lua
-- extensions/my-transform.lua
function get_info()
  return {
    id = "my-transform",
    name = "My Transform",
    version = "1.0.0",
    type = "validator"
  }
end

function validate(ir)
  -- Check IR constraints
  local errors = {}
  for _, module in ipairs(ir.modules) do
    if not module.doc then
      table.insert(errors, {
        module = module.path,
        message = "Missing module documentation"
      })
    end
  end
  return { valid = #errors == 0, errors = errors }
end
```

### Morphir IR Extensions (Self-Hosting)

The most interesting possibility: **extensions written in Morphir itself**, compiled to IR, and interpreted or compiled by the daemon.

**Potential Benefits:**
- Dogfooding: Use Morphir to extend Morphir
- Type-safe extension authoring
- Extensions benefit from Morphir's guarantees
- Can generate extensions to multiple targets
- Ultimate validation of Morphir's expressiveness

**Example:**
```elm
-- extensions/MyCodegen.elm
module MyCodegen exposing (generate)

import Morphir.IR.Distribution exposing (Distribution)
import Morphir.Extension exposing (GeneratedFile)

generate : Distribution -> List GeneratedFile
generate distribution =
    distribution.modules
        |> List.concatMap generateModule

generateModule : Module -> List GeneratedFile
generateModule mod =
    [ { path = modulePath mod ++ ".scala"
      , content = moduleToScala mod
      }
    ]
```

**Compilation:**
```bash
# Compile extension to IR
morphir build extensions/my-codegen/

# The IR itself becomes the extension
# Daemon interprets or JIT-compiles the IR
```

**Architecture:**
```
┌─────────────────────────────────────────────────────┐
│                   Morphir Daemon                     │
├─────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │ WASM Runtime│  │ IR Interp.  │  │   Native    │ │
│  │ (wasmtime)  │  │ (Morphir IR)│  │   (exec)    │ │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘ │
│         │                │                │        │
│    ┌────┴────┐      ┌────┴────┐      ┌────┴────┐   │
│    │  .wasm  │      │  .mir   │      │  bin/*  │   │
│    │ codegen │      │ codegen │      │ codegen │   │
│    └─────────┘      └─────────┘      └─────────┘   │
└─────────────────────────────────────────────────────┘
```

**Considerations:**
- Requires IR interpreter or JIT in the daemon
- Bootstrap problem: need initial extensions to build Morphir extensions
- Performance may vary (interpreted vs compiled)
- Could compile IR extensions to WASM for production

### Runtime Comparison

| Runtime | Sandboxed | Startup | Authoring | Performance | Size |
|---------|-----------|---------|-----------|-------------|------|
| **WASM Component** | ✓ Strong | Medium | Rust/Go/C | High | Medium |
| **Native Executable** | ✗ Process | Fast | Any | Highest | Varies |
| **QuickJS** | ✓ Embedded | Fast | JS/TS | Medium | Small |
| **Javy** | ✓ WASM | Medium | JS/TS | Medium-High | Medium |
| **Lua** | ✓ Embedded | Fastest | Lua | Medium | Tiny |
| **Morphir IR** | ✓ Semantic | Varies | Morphir | Varies | Small |

### Exploration Status

| Runtime | Status | Priority |
|---------|--------|----------|
| WASM Component | **Supported** | Primary |
| Native Executable | **Supported** | Primary |
| QuickJS | Future | Medium |
| Javy | Future | Medium |
| Lua | Future | Low |
| Morphir IR | Future | **High** (dogfooding) |

> **Note:** Alternative runtimes are documented for future exploration. The current implementation focuses on WASM components and native executables. Morphir IR extensions are particularly interesting as they would validate Morphir's expressiveness and enable self-hosting.

## Related

- **[IR v4](../ir/README.md)** - Intermediate representation format
- **[Morphir Daemon](../daemon/README.md)** - Workspace and build management
- **[Deprecated: Toolchain Framework](../../deprecated/README.md)** - Superseded design
