---
id: wit-commands
title: WIT Commands
sidebar_label: WIT Commands
sidebar_position: 11
---

# WIT Commands

Morphir provides native support for WebAssembly Interface Types (WIT) through the `morphir wit` command family. These commands allow you to compile WIT source files to Morphir IR and generate WIT source from Morphir IR.

## Overview

WIT (WebAssembly Interface Types) is the interface definition language for WebAssembly components. Morphir's WIT integration enables:

- **Compiling WIT to IR**: Parse WIT source and convert to Morphir's Intermediate Representation
- **Generating WIT from IR**: Convert Morphir IR back to WIT source
- **Round-trip Validation**: Verify semantic correctness through make + gen pipeline

## Commands

### morphir wit make

Compile WIT source to Morphir IR (frontend compilation).

```shell
morphir wit make [file.wit] [options]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `-s, --source <code>` | Inline WIT source code | - |
| `-f, --file <path>` | Path to WIT file | - |
| `-o, --output <path>` | Output path for IR JSON | - |
| `--warnings-as-errors` | Treat warnings as errors | `false` |
| `--strict` | Fail on unsupported constructs | `false` |
| `--json` | Output result as pretty-printed JSON | `false` |
| `--jsonl` | Output as JSONL (one JSON object per line) | `false` |
| `--jsonl-input <path>` | Path to JSONL file for batch processing | - |
| `-v, --verbose` | Show detailed diagnostics | `false` |

**Examples:**

```shell
# Compile a WIT file
morphir wit make example.wit -o example.ir.json

# Compile inline WIT source
morphir wit make -s "package test:example; interface foo { bar: func(); }" -o out.ir.json

# Pipe from stdin
cat example.wit | morphir wit make -o out.ir.json

# Get JSON output with diagnostics
morphir wit make example.wit --json --verbose
```

### morphir wit gen

Generate WIT source from Morphir IR (backend generation).

```shell
morphir wit gen [file.ir.json] [options]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `-f, --file <path>` | Path to IR JSON file | - |
| `-o, --output <path>` | Output path for WIT file | - |
| `--warnings-as-errors` | Treat warnings as errors | `false` |
| `--json` | Output result as JSON | `false` |
| `--jsonl` | Output as JSONL | `false` |
| `-v, --verbose` | Show detailed diagnostics | `false` |

**Examples:**

```shell
# Generate WIT from IR
morphir wit gen example.ir.json -o example.wit
```

### morphir wit build

Run the full WIT pipeline: WIT -> IR -> WIT with round-trip validation.

```shell
morphir wit build [file.wit] [options]
```

This command combines `make` and `gen` steps and validates that the round-trip conversion is semantically correct.

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `-s, --source <code>` | Inline WIT source code | - |
| `-f, --file <path>` | Path to WIT file | - |
| `-o, --output <path>` | Output path for regenerated WIT | - |
| `--warnings-as-errors` | Treat warnings as errors | `false` |
| `--strict` | Fail on unsupported constructs | `false` |
| `--json` | Output result as JSON | `false` |
| `--jsonl` | Output as JSONL | `false` |
| `--jsonl-input <path>` | Path to JSONL file for batch processing | - |
| `-v, --verbose` | Show detailed diagnostics | `false` |

**Examples:**

```shell
# Full build pipeline with output
morphir wit build example.wit -o regenerated.wit

# Build with inline source
morphir wit build -s "package test:example; interface foo { type user-id = string; }"

# JSON output for CI integration
morphir wit build example.wit --json
```

## Batch Processing with JSONL

For processing multiple WIT sources efficiently, use JSONL (JSON Lines) batch mode.

### Input Format

Create a JSONL file with one JSON object per line:

```json
{"name": "users", "source": "package app:users; interface users { type user-id = string; }"}
{"name": "orders", "file": "path/to/orders.wit"}
{"name": "products", "source": "package app:products; interface products { record product { id: string, name: string, } }"}
```

Each line must have either:
- `source`: Inline WIT source code
- `file`: Path to a WIT file

The `name` field is optional and defaults to the filename or line number.

### Running Batch Processing

```shell
# Batch make
morphir wit make --jsonl-input sources.jsonl --jsonl

# Batch build
morphir wit build --jsonl-input sources.jsonl --jsonl
```

### Output Format

JSONL output produces one JSON object per line:

**Make output:**
```json
{"name":"users","success":true,"typeCount":1,"valueCount":0}
{"name":"orders","success":false,"error":"parse error at line 5"}
```

**Build output:**
```json
{"name":"users","success":true,"roundTripValid":true,"typeCount":1,"witSource":"package app:users;\n..."}
```

## Diagnostics

All WIT commands produce structured diagnostics for errors, warnings, and informational messages.

### Severity Levels

- **ERROR**: Fatal issues that prevent compilation
- **WARN**: Potential issues that may indicate problems
- **INFO**: Informational messages about processing

### Viewing Diagnostics

Use `--verbose` to see all diagnostics:

```shell
morphir wit make example.wit --verbose
```

Diagnostics include:
- Severity level
- Diagnostic code (when available)
- Descriptive message
- Source location (file, line, column)

### JSON Diagnostic Format

When using `--json` or `--jsonl`, diagnostics are included in the output:

```json
{
  "success": false,
  "error": "parse error",
  "diagnostics": [
    {"severity": "error", "code": "WIT001", "message": "unexpected token"}
  ]
}
```

## Integration with Toolchain Framework

The WIT commands integrate with Morphir's toolchain framework. The WIT toolchain is registered as a native toolchain with three tasks:

| Task | Target | Description |
|------|--------|-------------|
| `make` | `make` | Compile WIT source to Morphir IR |
| `gen` | `gen` | Generate WIT from Morphir IR |
| `build` | `build` | Full pipeline with round-trip validation |

### Using via Toolchain API

```go
import (
    "github.com/finos/morphir/pkg/toolchain"
    wittoolchain "github.com/finos/morphir/pkg/bindings/wit/toolchain"
)

// Create and register
registry := toolchain.NewRegistry()
wittoolchain.Register(registry)

// Execute tasks
executor := toolchain.NewExecutor(registry, outputDir, ctx)
result, err := executor.ExecuteTask("wit", "make", "")
```

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Success |
| 1 | General error (parse error, invalid input, etc.) |

## See Also

- [WIT Type Mapping](wit-type-mapping) - How WIT types map to Morphir IR
- [Toolchain Integration](/docs/toolchain-integration-design) - Toolchain framework design
