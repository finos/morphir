---
title: CLI-Daemon Interaction
sidebar_label: CLI Interaction
sidebar_position: 10
status: draft
tracking:
  github_issues: [392, 394]
---

# CLI-Daemon Interaction

This document defines how the Morphir CLI communicates with the Morphir Daemon, including connection modes, transport protocols, and lifecycle management.

## Overview

The Morphir CLI can operate in multiple modes depending on the use case:

| Mode | Description | Use Case |
|------|-------------|----------|
| **Embedded** | Daemon runs in-process | Simple commands, scripts, CI |
| **Local Daemon** | Connects to local daemon process | IDE integration, watch mode, development |
| **Remote Daemon** | Connects to remote daemon | Team servers, cloud builds |

## Connection Modes

### Embedded Mode (Default)

In embedded mode, the CLI starts an in-process daemon for the duration of the command. This is the simplest mode and requires no external daemon process.

```bash
# Embedded mode (default)
morphir build
morphir test
morphir codegen --target spark
```

**Characteristics:**
- No persistent state between commands
- Full compilation on each invocation
- Suitable for CI/CD pipelines and scripts
- No daemon process management required

### Local Daemon Mode

In local daemon mode, the CLI connects to a running daemon process on the local machine. This enables incremental builds, file watching, and IDE integration.

```bash
# Start the daemon
morphir daemon start

# Commands connect to running daemon
morphir build          # Uses cached state
morphir watch          # Streams file changes
morphir workspace add ./packages/new-project

# Stop the daemon
morphir daemon stop
```

**Characteristics:**
- Persistent in-memory state
- Incremental compilation
- File watching support
- Shared across CLI invocations and IDE

### Remote Daemon Mode

In remote daemon mode, the CLI connects to a daemon running on a remote server. This enables team-shared build servers and cloud-based compilation.

```bash
# Connect to remote daemon
morphir --daemon https://build.example.com:9742 build

# Or via environment variable
export MORPHIR_DAEMON_URL=https://build.example.com:9742
morphir build
```

**Characteristics:**
- Shared build cache across team

## Ad-Hoc Compilation Mode

For quick experimentation and integration workloads, Morphir supports ad-hoc compilation without requiring a full project structure. This enables:

- **Quick prototyping**: Try out Morphir without project setup
- **Piped workflows**: Integration with shell pipelines
- **Single-file compilation**: Compile individual files directly
- **Code generation testing**: Generate code from snippets

### Input Language Selection

Ad-hoc compilation requires specifying the input language (frontend) since there's no `morphir.toml` to infer it from:

```bash
# Explicit language selection
morphir compile --lang elm snippet.elm
morphir compile --lang morphir-dsl snippet.morphir

# Inferred from file extension
morphir compile snippet.elm      # Infers Elm frontend
morphir compile snippet.morphir  # Infers Morphir DSL frontend

# For stdin, language must be specified
echo "module Ex exposing (..)" | morphir compile --lang elm -
```

**Supported Languages:**

| Language | Flag | File Extensions |
|----------|------|-----------------|
| Elm | `--lang elm` | `.elm` |
| Morphir DSL | `--lang morphir-dsl` | `.morphir`, `.mdsl` |
| (Extension) | `--lang <ext-name>` | Per extension |

### Stdin Input (Piping)

Pipe Morphir source code directly to the CLI:

```bash
# Compile from stdin (language required)
echo 'module Example exposing (add)

add : Int -> Int -> Int
add a b = a + b' | morphir compile --lang elm -

# Codegen from stdin
cat myfile.elm | morphir codegen --target spark --lang elm -

# Pipe through multiple tools
morphir compile --lang elm - < snippet.elm | morphir codegen --target typescript -
```

**JSON-RPC Method:**
```json
{
  "jsonrpc": "2.0",
  "id": "compile-001",
  "method": "compile/snippet",
  "params": {
    "language": "elm",
    "source": "module Example exposing (add)\n\nadd : Int -> Int -> Int\nadd a b = a + b",
    "options": {
      "moduleName": "Example"
    }
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "compile-001",
  "result": {
    "ir": { "...compiled module IR..." },
    "diagnostics": []
  }
}
```

### Single File Compilation

Compile a single file without a project:

```bash
# Compile single file (language inferred from .elm extension)
morphir compile src/Example.elm

# Explicit language
morphir compile --lang elm src/Example.elm

# Compile and generate code
morphir compile src/Example.elm | morphir codegen --target spark

# Compile with inferred module name
morphir compile Example.elm
# Module name inferred as "Example" from filename
```

### Multiple Files (No Project)

Compile a set of files without a `morphir.toml`:

```bash
# Compile multiple files
morphir compile src/Types.elm src/Logic.elm src/Api.elm

# Using glob patterns
morphir compile "src/**/*.elm"

# With explicit output
morphir compile src/*.elm --output dist/
```

**JSON-RPC Method:**
```json
{
  "jsonrpc": "2.0",
  "id": "compile-002",
  "method": "compile/files",
  "params": {
    "language": "elm",
    "files": [
      { "path": "Types.elm", "source": "module Types exposing (..)\n..." },
      { "path": "Logic.elm", "source": "module Logic exposing (..)\n..." }
    ],
    "options": {
      "packageName": "adhoc"
    }
  }
}
```

### Inline Expressions

Evaluate or compile inline expressions (useful for REPL-like workflows):

```bash
# Compile an expression
morphir eval "List.map (\\x -> x * 2) [1, 2, 3]"

# Type-check an expression
morphir check --expr "\\x -> x + 1"

# Generate code for an expression
morphir codegen --target typescript --expr "\\a b -> a + b"
```

**JSON-RPC Method:**
```json
{
  "jsonrpc": "2.0",
  "id": "eval-001",
  "method": "compile/expression",
  "params": {
    "expression": "List.map (\\x -> x * 2) [1, 2, 3]",
    "context": {
      "imports": ["List"]
    }
  }
}
```

### Ad-Hoc Codegen

Generate code from IR or source without a project. The `--target` flag selects the backend:

```bash
# Codegen from compiled IR (stdin)
morphir compile snippet.elm | morphir codegen --target spark -

# Codegen from source file directly
morphir codegen --target typescript src/Example.elm

# Codegen with inline source
morphir codegen --target spark --source "module Ex exposing (f)\nf x = x + 1"

# Multiple targets
morphir codegen --target spark --target typescript src/Example.elm
```

**Available Targets:**

| Target | Flag | Output Language |
|--------|------|-----------------|
| Spark | `--target spark` | Scala (Spark API) |
| Scala | `--target scala` | Pure Scala |
| TypeScript | `--target typescript` | TypeScript |
| JSON Schema | `--target json-schema` | JSON Schema |
| (Extensions) | `--target <name>` | Via WASM backends |

**Target Options:**
```bash
# Pass options to target
morphir codegen --target spark --option spark_version=3.5

# List available targets
morphir codegen --list-targets
```

**Streaming Ad-Hoc Codegen:**
```bash
# Stream codegen output as it's generated
morphir compile "src/*.elm" | morphir codegen --target spark --stream -
```

### Output Formats

Ad-hoc compilation supports multiple output formats:

```bash
# Output IR as JSON (default)
morphir compile snippet.elm

# Output IR as compact JSON
morphir compile snippet.elm --format json-compact

# Output just the types
morphir compile snippet.elm --format types

# Pretty-print the IR
morphir compile snippet.elm --format pretty
```

### Temporary Project Context

For ad-hoc compilation that needs dependencies, specify them inline:

```bash
# With SDK dependency
morphir compile snippet.elm --with-dep morphir/sdk

# With custom package name
morphir compile snippet.elm --package my-org/experiment

# With multiple dependencies
morphir compile snippet.elm \
  --with-dep morphir/sdk \
  --with-dep "acme/utils@1.0.0"
```

**JSON-RPC Method:**
```json
{
  "jsonrpc": "2.0",
  "id": "compile-003",
  "method": "compile/snippet",
  "params": {
    "language": "elm",
    "source": "module Example exposing (..)\nimport Json.Decode\n...",
    "options": {
      "packageName": "my-org/experiment",
      "dependencies": [
        { "name": "morphir/sdk", "version": "latest" },
        { "name": "morphir/json", "version": "1.0.0" }
      ]
    }
  }
}
```

### Use Cases

| Use Case | Command |
|----------|---------|
| Quick syntax check | `echo "x = 1" \| morphir check -` |
| Prototype a function | `morphir compile snippet.elm` |
| Test codegen output | `morphir codegen --target spark snippet.elm` |
| Shell pipeline | `cat src.elm \| morphir compile - \| morphir codegen --target ts -` |
| CI validation | `morphir compile --check-only "src/**/*.elm"` |
| REPL-style eval | `morphir eval "1 + 2"` |

### Limitations

Ad-hoc mode has some limitations compared to project mode:

| Feature | Ad-Hoc | Project |
|---------|--------|---------|
| Dependency resolution | Manual (`--with-dep`) | Automatic |
| Incremental compilation | No | Yes |
| Caching | No | Yes |
| Multi-module imports | Limited | Full |
| Watch mode | No | Yes |
| IDE integration | No | Yes |

For anything beyond quick prototyping, create a project with `morphir init`.
- Centralized dependency resolution
- Requires authentication (see [Security](#security))

## Transport Protocols

### HTTP/JSON-RPC (Primary)

The primary transport is JSON-RPC 2.0 over HTTP. This provides a standard, debuggable protocol that works across network boundaries.

```
┌─────────────┐         HTTP/JSON-RPC          ┌─────────────┐
│             │  ─────────────────────────────► │             │
│  Morphir    │                                 │   Morphir   │
│    CLI      │  ◄───────────────────────────── │   Daemon    │
│             │         JSON-RPC Response       │             │
└─────────────┘                                 └─────────────┘
```

**Default Ports:**
- Local daemon: `http://localhost:9741`
- Remote daemon: `https://<host>:9742` (TLS required)

**Request Format:**
```json
{
  "jsonrpc": "2.0",
  "id": "req-001",
  "method": "workspace/build",
  "params": {
    "projects": ["my-org/core"]
  }
}
```

**Response Format:**
```json
{
  "jsonrpc": "2.0",
  "id": "req-001",
  "result": {
    "success": true,
    "diagnostics": []
  }
}
```

### Unix Domain Socket (Local Only)

For local daemon connections, Unix domain sockets provide lower latency and better security than TCP.

```bash
# Socket location
$XDG_RUNTIME_DIR/morphir/daemon.sock
# Fallback: /tmp/morphir-<uid>/daemon.sock
```

The CLI automatically uses the socket when available:
```bash
# CLI checks for socket first, falls back to HTTP
morphir build
```

### Stdio (LSP/Embedded)

For IDE integration via LSP and embedded mode, the daemon communicates over stdin/stdout:

```
┌─────────────┐         stdin/stdout           ┌─────────────┐
│             │  ─────────────────────────────► │             │
│    IDE      │         JSON-RPC               │   Morphir   │
│   (LSP)     │  ◄───────────────────────────── │   Daemon    │
│             │                                 │  (stdio)    │
└─────────────┘                                 └─────────────┘
```

**Launch Command (LSP):**
```bash
morphir daemon --stdio
```

## Daemon Lifecycle

### Starting the Daemon

```bash
# Start daemon in background (default)
morphir daemon start

# Start with specific options
morphir daemon start --port 9741 --workspace /path/to/workspace

# Start in foreground (for debugging)
morphir daemon start --foreground

# Start with verbose logging
morphir daemon start --log-level debug
```

**Startup Sequence:**
1. Check for existing daemon (via pidfile/socket)
2. If running, verify health and exit
3. Bind to transport (socket/port)
4. Write pidfile to `$XDG_RUNTIME_DIR/morphir/daemon.pid`
5. Initialize workspace (if specified)
6. Begin accepting connections

### Daemon Status

```bash
# Check daemon status
morphir daemon status
```

**Output:**
```
Morphir Daemon
  Status:    running
  PID:       12345
  Uptime:    2h 34m
  Socket:    /run/user/1000/morphir/daemon.sock
  HTTP:      http://localhost:9741
  Workspace: /home/user/my-workspace (open)
  Projects:  3 loaded, 0 stale
  Memory:    124 MB
```

### Health Check

```bash
# Health check (exit code 0 if healthy)
morphir daemon health
```

**JSON-RPC Method:**
```json
{
  "jsonrpc": "2.0",
  "id": "health-001",
  "method": "daemon/health",
  "params": {}
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "health-001",
  "result": {
    "status": "healthy",
    "version": "0.4.0",
    "uptime_seconds": 9240,
    "workspace": {
      "root": "/home/user/my-workspace",
      "state": "open",
      "projects": 3
    }
  }
}
```

### Stopping the Daemon

```bash
# Graceful shutdown
morphir daemon stop

# Force stop (SIGKILL)
morphir daemon stop --force

# Restart
morphir daemon restart
```

**Shutdown Sequence:**
1. Stop accepting new connections
2. Complete in-flight requests (with timeout)
3. Flush pending writes
4. Close workspace
5. Remove pidfile and socket
6. Exit

### Auto-Start

The CLI can automatically start a daemon when needed:

```toml
# morphir.toml or ~/.config/morphir/config.toml
[daemon]
auto_start = true          # Start daemon if not running
auto_stop = false          # Keep daemon running after CLI exits
idle_timeout = "30m"       # Stop after idle period (0 = never)
```

## Extension Management

The CLI provides commands to discover, inspect, and manage extensions.

### List Extensions

```bash
# List all registered extensions
morphir extension list

# Output:
# NAME              VERSION   TYPE      STATUS   CAPABILITIES
# spark-codegen     1.2.0     codegen   ready    generate, streaming, incremental
# elm-frontend      0.19.1    frontend  ready    compile, diagnostics
# my-extension      0.1.0     -         ready    (info only)

# List with details
morphir extension list --verbose

# Filter by type
morphir extension list --type codegen
morphir extension list --type frontend
```

### Inspect Extension

```bash
# Get detailed info about an extension
morphir extension info spark-codegen

# Output:
# spark-codegen v1.2.0
# ═══════════════════════════════════════════════════════
#   Type:         codegen
#   Description:  Generate Apache Spark DataFrame code from Morphir IR
#   Author:       Morphir Contributors
#   Homepage:     https://github.com/finos/morphir-spark
#   License:      Apache-2.0
#   Source:       ./extensions/spark-codegen.wasm
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

# Output as JSON
morphir extension info spark-codegen --json
```

### Verify Extension Health

```bash
# Ping single extension
morphir extension ping spark-codegen
# spark-codegen: OK (2ms)

# Ping all extensions
morphir extension ping --all
# spark-codegen:  OK (2ms)
# elm-frontend:   OK (1ms)
# my-extension:   OK (1ms)

# Ping with timeout
morphir extension ping spark-codegen --timeout 5s
```

### Extension Installation

```bash
# Install from URL
morphir extension install https://extensions.morphir.dev/spark-codegen-1.2.0.wasm

# Install from local file
morphir extension install ./my-extension.wasm

# Install from registry (future)
morphir extension install morphir/spark-codegen@1.2.0

# Uninstall
morphir extension uninstall spark-codegen

# Update
morphir extension update spark-codegen
```

### Extension Configuration

```bash
# Show extension config
morphir extension config spark-codegen

# Set extension option
morphir extension config spark-codegen --set spark_version=3.5

# Reset to defaults
morphir extension config spark-codegen --reset
```

## CLI Command Mapping

### Command to JSON-RPC Translation

| CLI Command | JSON-RPC Method | Notes |
|-------------|-----------------|-------|
| `morphir build` | `workspace/buildAll` | Builds all projects |
| `morphir build --stream` | `workspace/buildStreaming` | Streaming build with per-module notifications |
| `morphir build <project>` | `compile/project` | Builds specific project |
| `morphir test` | `workspace/test` | Runs tests |
| `morphir check` | `workspace/check` | Runs linting/validation |
| `morphir codegen` | `codegen/generate` | Generates code for targets |
| `morphir codegen --stream` | `codegen/generateStreaming` | Streaming codegen with per-module notifications |
| `morphir watch` | `workspace/watch` | Enables file watching |
| `morphir workspace init` | `workspace/create` | Creates new workspace |
| `morphir workspace add` | `workspace/addProject` | Adds project to workspace |
| `morphir clean` | `workspace/clean` | Cleans build artifacts |
| `morphir compile -` | `compile/snippet` | Compile from stdin |
| `morphir compile <file>` | `compile/files` | Compile single file (no project) |
| `morphir compile <files...>` | `compile/files` | Compile multiple files (no project) |
| `morphir eval <expr>` | `compile/expression` | Evaluate inline expression |
| `morphir check --expr <expr>` | `compile/expression` | Type-check inline expression |
| `morphir extension list` | `extension/list` | List registered extensions |
| `morphir extension info <ext>` | `extension/info` | Get extension details |
| `morphir extension ping <ext>` | `extension/ping` | Verify extension connectivity |
| `morphir extension install` | `extension/install` | Install extension |
| `morphir extension uninstall` | `extension/uninstall` | Remove extension |

### Streaming Operations

Morphir tasks like `build` and `codegen` support streaming to avoid producing all output in one shot. This is critical for large projects where:

- Compilation/generation takes significant time
- Results should appear progressively
- Early errors should surface immediately
- Memory shouldn't hold the entire output

#### Streaming Model

```
┌─────────┐      ┌─────────┐      ┌─────────────────────────┐
│   CLI   │─────►│ Request │─────►│        Daemon           │
│         │      └─────────┘      │                         │
│         │                       │  ┌─────────────────┐    │
│         │◄─────────────────────────│ Notification 1  │    │
│         │                       │  └─────────────────┘    │
│         │◄─────────────────────────│ Notification 2  │    │
│         │                       │  └─────────────────┘    │
│         │◄─────────────────────────│ Notification N  │    │
│         │                       │  └─────────────────┘    │
│         │◄─────────────────────────│ Final Response  │    │
└─────────┘                       └─────────────────────────┘
```

#### Streaming Build

```bash
morphir build --stream
```

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": "build-001",
  "method": "workspace/buildStreaming",
  "params": {
    "projects": ["my-org/domain"],
    "streaming": {
      "granularity": "module",
      "includeIR": true
    }
  }
}
```

**Notifications (streamed as modules compile):**
```json
{ "method": "build/started", "params": { "project": "my-org/domain", "modules": 12 } }
{ "method": "build/moduleCompiled", "params": { "module": ["Domain", "Types"], "status": "ok" } }
{ "method": "build/moduleCompiled", "params": { "module": ["Domain", "User"], "status": "ok" } }
{ "method": "build/moduleCompiled", "params": { "module": ["Domain", "Order"], "status": "partial", "diagnostics": [...] } }
```

**Final Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "build-001",
  "result": { "success": true, "modulesCompiled": 12, "durationMs": 3421 }
}
```

#### Streaming Codegen

```bash
morphir codegen --target spark --stream
```

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": "codegen-001",
  "method": "codegen/generateStreaming",
  "params": {
    "target": "spark",
    "streaming": {
      "granularity": "module",
      "writeImmediately": true
    }
  }
}
```

**Notifications (streamed as files are generated):**
```json
{ "method": "codegen/started", "params": { "target": "spark", "modules": 12 } }
{ "method": "codegen/moduleGenerated", "params": { "module": ["Domain", "Types"], "files": ["Types.scala"] } }
{ "method": "codegen/moduleGenerated", "params": { "module": ["Domain", "User"], "files": ["User.scala"] } }
{ "method": "codegen/fileWritten", "params": { "path": "src/main/scala/domain/User.scala" } }
```

#### CLI Streaming Display

The CLI renders streaming notifications in real-time:

```
Building my-org/domain (12 modules)
  ✓ Domain.Types          [42ms]
  ✓ Domain.User           [38ms]
  ⚠ Domain.Order          [51ms] (2 warnings)
  ● Domain.Product        [compiling...]
```

#### Cancellation

Streaming operations can be cancelled mid-flight:

```json
{
  "jsonrpc": "2.0",
  "method": "$/cancelRequest",
  "params": { "id": "build-001" }
}
```

The daemon stops processing and returns partial results:

```json
{
  "jsonrpc": "2.0",
  "id": "build-001",
  "result": {
    "cancelled": true,
    "modulesCompiled": 5,
    "modulesRemaining": 7
  }
}
```

### Progress Notifications

For non-streaming operations, progress is reported via LSP-style notifications:

```bash
morphir build --progress
```

**Progress Notifications:**
```json
{
  "jsonrpc": "2.0",
  "method": "$/progress",
  "params": {
    "token": "build-001",
    "value": {
      "kind": "report",
      "message": "Compiling my-org/core...",
      "percentage": 45
    }
  }
}
```

### Diagnostic Streaming

Build diagnostics stream as they're discovered (not batched until the end):

```json
{
  "jsonrpc": "2.0",
  "method": "textDocument/publishDiagnostics",
  "params": {
    "uri": "file:///path/to/src/Domain/User.elm",
    "diagnostics": [
      {
        "range": { "start": { "line": 10, "character": 5 }, "end": { "line": 10, "character": 15 } },
        "severity": 1,
        "message": "Type mismatch: expected Int, got String"
      }
    ]
  }
}
```

This allows the CLI to display errors immediately and IDEs to show diagnostics in real-time.

## Connection Management

### Discovery

The CLI discovers the daemon in this order:

1. **Explicit URL**: `--daemon <url>` or `MORPHIR_DAEMON_URL`
2. **Unix Socket**: `$XDG_RUNTIME_DIR/morphir/daemon.sock`
3. **Local HTTP**: `http://localhost:9741`
4. **Embedded**: Start in-process daemon

```bash
# Explicit daemon URL
morphir --daemon http://localhost:9741 build

# Environment variable
export MORPHIR_DAEMON_URL=http://localhost:9741
morphir build
```

### Connection Timeout

```toml
# ~/.config/morphir/config.toml
[daemon]
connect_timeout = "5s"     # Time to wait for connection
request_timeout = "60s"    # Time to wait for response
```

### Reconnection

If the daemon connection is lost during a long-running operation:

1. CLI detects connection failure
2. Attempts reconnection (3 retries with exponential backoff)
3. If daemon is gone, offers to restart
4. Resumes operation if state is recoverable

```
Connection lost. Attempting to reconnect...
  Retry 1/3: connection refused
  Retry 2/3: connection refused
  Retry 3/3: connected

Daemon restarted. Rebuilding project state...
```

## Security

### Local Daemon

Local daemon connections are secured by:
- Unix socket permissions (owner-only by default)
- Pidfile verification
- No authentication required for local connections

### Remote Daemon

Remote daemon connections require:
- TLS encryption (HTTPS)
- Authentication token

```bash
# Set authentication token
export MORPHIR_DAEMON_TOKEN=<token>

# Or via config file
# ~/.config/morphir/config.toml
[daemon]
url = "https://build.example.com:9742"
token = "<token>"  # Or use keyring/credential helper
```

**Token Authentication:**
```json
{
  "jsonrpc": "2.0",
  "id": "auth-001",
  "method": "daemon/authenticate",
  "params": {
    "token": "<bearer-token>"
  }
}
```

### Capability Restrictions

Remote daemons can restrict capabilities:

```json
{
  "jsonrpc": "2.0",
  "id": "caps-001",
  "method": "daemon/capabilities",
  "params": {}
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "caps-001",
  "result": {
    "capabilities": {
      "workspace/create": false,
      "workspace/build": true,
      "workspace/watch": false,
      "codegen/generate": true,
      "extensions/install": false
    }
  }
}
```

## Configuration

### Daemon Configuration

```toml
# morphir.toml (project/workspace level)
[daemon]
# Connection settings
port = 9741
socket = true              # Enable Unix socket

# Behavior
auto_start = true
idle_timeout = "30m"

# Resource limits
max_memory = "2GB"
max_projects = 50
```

### Global Configuration

```toml
# ~/.config/morphir/config.toml (user level)
[daemon]
# Default daemon URL for remote connections
url = "https://build.example.com:9742"
token_command = "pass show morphir/daemon-token"

# Local daemon settings
auto_start = true
log_level = "info"
log_file = "~/.local/state/morphir/daemon.log"
```

## Error Handling

### Connection Errors

| Error | CLI Behavior |
|-------|--------------|
| Daemon not running | Auto-start (if enabled) or prompt user |
| Connection refused | Retry with backoff, then fail |
| Authentication failed | Prompt for credentials or fail |
| Timeout | Retry or fail with message |

### Request Errors

JSON-RPC errors are mapped to CLI exit codes:

| JSON-RPC Error Code | Exit Code | Meaning |
|---------------------|-----------|---------|
| -32700 | 2 | Parse error |
| -32600 | 2 | Invalid request |
| -32601 | 2 | Method not found |
| -32602 | 2 | Invalid params |
| -32603 | 1 | Internal error |
| -32000 to -32099 | 1 | Server errors |

**Error Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "req-001",
  "error": {
    "code": -32603,
    "message": "Compilation failed",
    "data": {
      "diagnostics": [...]
    }
  }
}
```

## Logging and Debugging

### Daemon Logs

```bash
# View daemon logs
morphir daemon logs

# Follow logs
morphir daemon logs -f

# Log location
~/.local/state/morphir/daemon.log
```

### Debug Mode

```bash
# Enable verbose CLI output
morphir --verbose build

# Enable JSON-RPC tracing
morphir --trace-rpc build

# Trace output
--> {"jsonrpc":"2.0","id":"1","method":"workspace/build","params":{}}
<-- {"jsonrpc":"2.0","id":"1","result":{"success":true}}
```

### Diagnostics Dump

```bash
# Dump daemon state for debugging
morphir daemon dump > daemon-state.json
```

## Related

- **[Morphir Daemon](./README.md)** - Daemon overview and architecture
- **[Build Operations](./build.md)** - Build orchestration details
- **[File Watching](./watching.md)** - Watch mode implementation
- **[IR v4](../ir/README.md)** - JSON-RPC protocol and type specifications
