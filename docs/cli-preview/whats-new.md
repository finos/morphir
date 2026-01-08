---
id: whats-new
title: What's New in CLI Preview
sidebar_label: What's New
---

# What's New in Morphir CLI Preview

This page highlights the major new features in the Morphir CLI Preview.

## WebAssembly Interface Types (WIT) Support

The CLI Preview introduces full support for WIT, the interface definition language for WebAssembly components. This enables Morphir to serve as a bridge between WIT and other ecosystems.

### Why WIT?

[WebAssembly Interface Types](https://component-model.bytecodealliance.org/design/wit.html) (WIT) is becoming the standard for defining component interfaces in the WebAssembly ecosystem. By supporting WIT, Morphir can:

- **Import WIT contracts** and validate them against Morphir models
- **Export Morphir types** to WIT for WebAssembly component generation
- **Round-trip validate** conversions between WIT and Morphir IR

### The WIT Pipeline

```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│  WIT File   │──make──▶│  Morphir IR  │──gen───▶│  WIT File   │
└─────────────┘         └──────────────┘         └─────────────┘
                               │
                               ▼
                        ┌──────────────┐
                        │    Other     │
                        │   Backends   │
                        └──────────────┘
```

The pipeline follows Morphir's established patterns:
- **make**: Frontend compilation (WIT → IR)
- **gen**: Backend generation (IR → WIT)
- **build**: Full pipeline with validation

### Example: WIT to Morphir IR

```wit
// api.wit
package mycompany:api;

interface user-service {
    record user {
        id: u64,
        name: string,
        email: string,
    }

    get-user: func(id: u64) -> option<user>;
    create-user: func(name: string, email: string) -> user;
}
```

```bash
morphir wit make api.wit -o api.ir.json
```

The IR captures:
- Package namespace (`mycompany`) and name (`api`)
- Record types with fields
- Function signatures

## JSONL Batch Processing

The CLI Preview adds JSONL (JSON Lines) support for efficient batch processing and streaming workflows.

### Why JSONL?

JSONL is ideal for:
- **CI/CD pipelines** - Each result is a separate JSON object
- **Streaming** - Process results as they arrive
- **Parallel processing** - Split input across workers
- **Error isolation** - One failure doesn't affect others

### Single Source with JSONL Output

```bash
morphir wit make -s "package a:b; interface foo { x: func(); }" --jsonl
```

Output:
```json
{"success":true,"typeCount":0,"valueCount":1,"module":{"values":[{"name":"X"}],"sourcePackage":{"namespace":"a","name":"b"}}}
```

### Batch Processing Multiple Sources

Create an input file with one JSON object per line:

```json
{"name": "user-api", "source": "package app:users; interface users { get-user: func(id: u64) -> string; }"}
{"name": "order-api", "source": "package app:orders; interface orders { create-order: func() -> u64; }"}
{"name": "inventory", "file": "./wit/inventory.wit"}
```

Process all at once:

```bash
morphir wit make --jsonl-input apis.jsonl --jsonl
```

Output (one line per input):
```json
{"name":"user-api","success":true,"typeCount":0,"valueCount":1,"module":{...}}
{"name":"order-api","success":true,"typeCount":0,"valueCount":1,"module":{...}}
{"name":"inventory","success":true,"typeCount":2,"valueCount":3,"module":{...}}
```

### IR Module Content in Output

JSONL output includes the full IR module structure:

```json
{
  "name": "api",
  "success": true,
  "typeCount": 1,
  "valueCount": 2,
  "module": {
    "types": [{"name": "User"}],
    "values": [{"name": "GetUser"}, {"name": "CreateUser"}],
    "sourcePackage": {
      "namespace": "mycompany",
      "name": "api"
    }
  }
}
```

## Diagnostic Pipeline

The WIT pipeline emits structured diagnostics for type conversion issues.

### Diagnostic Codes

| Code | Description |
|------|-------------|
| `WIT001` | Integer precision lost (e.g., u8 → Int) |
| `WIT002` | Float precision lost (f32 → Float) |
| `WIT003` | Unsupported type: flags |
| `WIT004` | Unsupported type: resource |
| `WIT005` | Round-trip validation mismatch |

### Viewing Diagnostics

```bash
# Verbose output shows all diagnostics
morphir wit make api.wit -v

# JSON output includes diagnostics array
morphir wit make api.wit --json
```

```json
{
  "success": true,
  "typeCount": 1,
  "valueCount": 2,
  "diagnostics": [
    {"severity": "warn", "code": "WIT001", "message": "lossy mapping: u64 → Int"}
  ]
}
```

### Strict Mode

Treat warnings as errors for CI enforcement:

```bash
# Fail on any warnings
morphir wit make api.wit --warnings-as-errors

# Fail on unsupported constructs
morphir wit make api.wit --strict
```

## Round-Trip Validation

The `build` command validates that WIT → IR → WIT conversions are semantically correct:

```bash
morphir wit build api.wit -o regenerated.wit
```

```
SUCCESS Compiled WIT to Morphir IR
  Types: 1, Values: 2
VALID Round-trip validation passed
```

If the round-trip produces different WIT (due to lossy conversions):

```
WARN Round-trip produced different output (lossy conversion)
```

## What's Coming Next

Future CLI Preview releases will include:

- **Full IR JSON parsing** for `morphir wit gen`
- **Additional WIT types** - flags, resources
- **IR emission strategies** - configurable JSON output formats
- **More backends** - Scala, TypeScript, Go generation from WIT

Stay tuned to the [Release Notes](release-notes/v0.4.0-alpha.1.md) for updates.
