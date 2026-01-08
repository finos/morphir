---
id: wit-command
title: morphir wit Command Reference
sidebar_label: morphir wit
---

# morphir wit Command Reference

The `morphir wit` command group provides tools for working with WebAssembly Interface Types (WIT).

## Overview

```bash
morphir wit <subcommand> [options]
```

### Subcommands

| Command | Description |
|---------|-------------|
| `make` | Compile WIT to Morphir IR (frontend) |
| `gen` | Generate WIT from Morphir IR (backend) |
| `build` | Full pipeline: WIT → IR → WIT with validation |

---

## morphir wit make

Compile a WIT file or inline source to Morphir IR.

### Synopsis

```bash
morphir wit make [file.wit] [options]
```

### Description

The `make` command parses WIT source code and converts it to Morphir's intermediate representation (IR). This is the "frontend" step in the compilation pipeline.

Input can be provided as:
- A file path (positional argument or `-f` flag)
- Inline source code (`-s` flag)
- Standard input (piped)
- JSONL batch file (`--jsonl-input` flag)

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--source <wit>` | `-s` | WIT source code (inline) |
| `--file <path>` | `-f` | Path to WIT file |
| `--output <path>` | `-o` | Output path for IR JSON |
| `--warnings-as-errors` | | Treat warnings as errors |
| `--strict` | | Fail on unsupported constructs |
| `--json` | | Output result as JSON (pretty-printed) |
| `--jsonl` | | Output as JSONL (one JSON object per line) |
| `--jsonl-input <path>` | | Path to JSONL file with batch inputs |
| `--verbose` | `-v` | Show detailed diagnostics |

### Examples

#### Compile from file

```bash
morphir wit make example.wit -o example.ir.json
```

#### Compile inline source

```bash
morphir wit make -s "package a:b; interface foo { x: func(); }"
```

#### Pipe from stdin

```bash
cat example.wit | morphir wit make -o out.ir.json
```

#### Get JSON output

```bash
morphir wit make example.wit --json
```

Output:
```json
{
  "success": true,
  "typeCount": 2,
  "valueCount": 3,
  "diagnostics": []
}
```

#### Get JSONL output

```bash
morphir wit make example.wit --jsonl
```

Output:
```json
{"success":true,"typeCount":2,"valueCount":3,"module":{"types":[...],"values":[...]}}
```

### Exit Codes

| Code | Description |
|------|-------------|
| 0 | Success (or success with warnings in JSONL mode) |
| 1 | Failure (parse error, unsupported construct in strict mode) |

---

## morphir wit gen

Generate WIT source code from Morphir IR.

### Synopsis

```bash
morphir wit gen [file.ir.json] [options]
```

### Description

The `gen` command converts Morphir IR back to WIT source code. This is the "backend" step in the compilation pipeline.

:::note Work in Progress
Full IR JSON parsing is not yet implemented. Use `morphir wit build` for round-trip operations.
:::

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--file <path>` | `-f` | Path to IR JSON file |
| `--output <path>` | `-o` | Output path for WIT file |
| `--warnings-as-errors` | | Treat warnings as errors |
| `--json` | | Output result as JSON |
| `--jsonl` | | Output as JSONL |
| `--verbose` | `-v` | Show detailed diagnostics |

### Examples

```bash
# Generate WIT from IR (when implemented)
morphir wit gen example.ir.json -o example.wit
```

---

## morphir wit build

Run the full WIT compilation pipeline with round-trip validation.

### Synopsis

```bash
morphir wit build [file.wit] [options]
```

### Description

The `build` command combines `make` and `gen` steps:

1. **Parse** WIT source to domain model
2. **Convert** to Morphir IR
3. **Generate** WIT from IR
4. **Validate** round-trip fidelity

This is useful for:
- Validating that WIT can be represented in Morphir IR
- Detecting lossy type conversions
- Normalizing WIT format

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--source <wit>` | `-s` | WIT source code (inline) |
| `--file <path>` | `-f` | Path to WIT file |
| `--output <path>` | `-o` | Output path for regenerated WIT |
| `--warnings-as-errors` | | Treat warnings as errors |
| `--strict` | | Fail on unsupported constructs |
| `--json` | | Output result as JSON |
| `--jsonl` | | Output as JSONL |
| `--jsonl-input <path>` | | Path to JSONL file with batch inputs |
| `--verbose` | `-v` | Show detailed diagnostics |

### Examples

#### Round-trip validation

```bash
morphir wit build example.wit -o regenerated.wit
```

Output:
```
Wrote WIT to regenerated.wit
VALID Round-trip validation passed
```

#### Check for lossy conversions

```bash
morphir wit build -s "package a:b; interface foo { get: func() -> u8; }" -v
```

Output:
```
Diagnostics:
  WARN [WIT001] lossy mapping: u8 → Int

package a:b;

interface foo {
    get: func() -> u8;
}

VALID Round-trip validation passed
```

---

## JSONL Batch Mode

Both `make` and `build` commands support JSONL batch processing for efficient multi-source workflows.

### Input Format

Each line in the JSONL input file is a JSON object with:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Optional identifier (defaults to filename or line number) |
| `source` | string | Inline WIT source code |
| `file` | string | Path to WIT file |

One of `source` or `file` must be provided.

### Example Input File

```json
{"name": "api-v1", "source": "package app:api; interface api { call: func(); }"}
{"name": "types", "file": "./wit/types.wit"}
{"name": "api-v2", "source": "package app:api@2.0; interface api { call: func() -> string; }"}
```

### Processing Batch Input

```bash
# From file
morphir wit make --jsonl-input sources.jsonl --jsonl

# From stdin
cat sources.jsonl | morphir wit make --jsonl-input - --jsonl
```

### Output Format

Each input produces one output line:

```json
{"name":"api-v1","success":true,"typeCount":0,"valueCount":1,"module":{...}}
{"name":"types","success":true,"typeCount":2,"valueCount":0,"module":{...}}
{"name":"api-v2","success":true,"typeCount":0,"valueCount":1,"module":{...}}
```

### Mixed Success/Failure

When some inputs fail, the command:
1. Outputs JSONL for all inputs (successful and failed)
2. Exits with code 1 if any input failed

```json
{"name":"valid","success":true,"typeCount":0,"valueCount":1,"module":{...}}
{"name":"invalid","success":false,"error":"parse error: unexpected token"}
{"name":"valid2","success":true,"typeCount":0,"valueCount":1,"module":{...}}
```

---

## Output Fields

### Make Output

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Input identifier (batch mode) |
| `success` | boolean | Whether compilation succeeded |
| `typeCount` | number | Number of types in module |
| `valueCount` | number | Number of values/functions in module |
| `module` | object | IR module content (JSONL mode) |
| `error` | string | Error message (on failure) |
| `diagnostics` | array | Array of diagnostic objects |

### Build Output

All make fields, plus:

| Field | Type | Description |
|-------|------|-------------|
| `roundTripValid` | boolean | Whether round-trip validation passed |
| `witSource` | string | Generated WIT source code |

### Module Object

| Field | Type | Description |
|-------|------|-------------|
| `types` | array | Type definitions |
| `values` | array | Value/function definitions |
| `doc` | string | Module documentation |
| `sourcePackage` | object | Original WIT package info |

### Diagnostic Object

| Field | Type | Description |
|-------|------|-------------|
| `severity` | string | `error`, `warn`, or `info` |
| `code` | string | Diagnostic code (e.g., `WIT001`) |
| `message` | string | Human-readable message |

---

## Diagnostic Codes

| Code | Severity | Description |
|------|----------|-------------|
| `WIT001` | warn | Integer precision lost (u8/u16/u32/u64/s8/s16/s32/s64 → Int) |
| `WIT002` | warn | Float precision lost (f32 → Float) |
| `WIT003` | error | Unsupported type: flags |
| `WIT004` | error | Unsupported type: resource |
| `WIT005` | warn | Round-trip produced semantically different output |

---

## Type Mapping

### Lossless Mappings

| WIT Type | Morphir IR |
|----------|------------|
| `bool` | `Bool` |
| `string` | `String` |
| `f64` | `Float` |
| `char` | `Char` |
| `list<T>` | `List T` |
| `option<T>` | `Maybe T` |
| `result<T, E>` | `Result E T` |
| `tuple<...>` | `Tuple` |
| `record { ... }` | `TypeRecord` |
| `variant { ... }` | Custom type with constructors |
| `enum { ... }` | Custom type with unit constructors |

### Lossy Mappings

| WIT Type | Morphir IR | What's Lost |
|----------|------------|-------------|
| `u8`, `u16`, `u32`, `u64` | `Int` | Size, signedness |
| `s8`, `s16`, `s32`, `s64` | `Int` | Size |
| `f32` | `Float` | Precision hint |

### Unsupported Types

| WIT Type | Status |
|----------|--------|
| `flags` | Not yet supported |
| `resource` | Not yet supported |

---

## Examples

### CI/CD Integration

```bash
#!/bin/bash
# Validate all WIT files in a directory

find ./wit -name "*.wit" -exec echo '{"file":"{}"}' \; > /tmp/sources.jsonl

morphir wit make --jsonl-input /tmp/sources.jsonl --jsonl > /tmp/results.jsonl

# Check for failures
if grep -q '"success":false' /tmp/results.jsonl; then
    echo "Validation failed:"
    grep '"success":false' /tmp/results.jsonl
    exit 1
fi

echo "All WIT files validated successfully"
```

### Generate IR for All APIs

```bash
# Create JSONL from directory
for f in ./wit/*.wit; do
    echo "{\"name\": \"$(basename $f .wit)\", \"file\": \"$f\"}"
done > apis.jsonl

# Compile all
morphir wit make --jsonl-input apis.jsonl --jsonl > compiled.jsonl

# Extract module data
jq -c 'select(.success) | .module' compiled.jsonl
```

### Strict Mode for Production

```bash
# Fail on any warnings or unsupported constructs
morphir wit make api.wit --warnings-as-errors --strict -o api.ir.json
```
