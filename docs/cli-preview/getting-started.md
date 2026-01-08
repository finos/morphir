---
id: getting-started
title: Getting Started with CLI Preview
sidebar_label: Getting Started
---

# Getting Started with Morphir CLI Preview

This guide will help you get started with the Morphir CLI Preview features, including WIT support and JSONL batch processing.

## Prerequisites

- A terminal (Linux, macOS, or Windows PowerShell)
- Internet connection for installation
- Basic familiarity with command-line tools

## Installation

### Quick Install Script

#### Linux & macOS

```bash
curl -fsSL https://raw.githubusercontent.com/finos/morphir/main/scripts/install.sh | bash
```

#### Windows (PowerShell)

```powershell
iwr https://raw.githubusercontent.com/finos/morphir/main/scripts/install.sh -useb | iex
```

### Using Go Install

If you have Go 1.21+ installed:

```bash
go install github.com/finos/morphir/cmd/morphir@latest
```

### Download Binary

Download pre-built binaries from [GitHub Releases](https://github.com/finos/morphir/releases).

## Verify Installation

```bash
morphir about
```

Expected output:
```
Morphir - Functional Data Modeling
═══════════════════════════════════

Version:      0.4.0-alpha.1
Git Commit:   abc123...
Build Date:   2026-01-08
Go Version:   go1.25.5
Platform:     linux/amd64
```

## Your First WIT Compilation

Let's compile a simple WIT interface to Morphir IR.

### Create a WIT File

Create a file named `hello.wit`:

```wit
package example:hello;

interface greeter {
    /// Greet someone by name
    greet: func(name: string) -> string;

    /// Say goodbye
    goodbye: func() -> string;
}
```

### Compile to Morphir IR

```bash
morphir wit make hello.wit -o hello.ir.json
```

Output:
```
SUCCESS Compiled WIT to Morphir IR
  Types: 0, Values: 2
```

### View the IR

```bash
cat hello.ir.json
```

The IR contains the module structure with the two functions.

## Understanding the Output

### JSON Output Mode

For structured output:

```bash
morphir wit make hello.wit --json
```

```json
{
  "success": true,
  "typeCount": 0,
  "valueCount": 2,
  "diagnostics": []
}
```

### JSONL Output Mode

For streaming/batch workflows:

```bash
morphir wit make hello.wit --jsonl
```

```json
{"success":true,"typeCount":0,"valueCount":2,"module":{"values":[{"name":"Greet"},{"name":"Goodbye"}],"sourcePackage":{"namespace":"example","name":"hello"}}}
```

## Working with Types

WIT supports various types that map to Morphir IR:

### Records

```wit
package example:users;

interface user-service {
    record user {
        id: u64,
        name: string,
        email: string,
        active: bool,
    }

    get-user: func(id: u64) -> option<user>;
    create-user: func(name: string, email: string) -> user;
}
```

```bash
morphir wit make users.wit --json
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

### Understanding Diagnostics

The diagnostic `WIT001` indicates that `u64` is mapped to Morphir's `Int` type, which doesn't preserve the size or signedness information. This is expected and the conversion still succeeds.

## Round-Trip Validation

The `build` command validates that WIT can be converted to IR and back:

```bash
morphir wit build hello.wit -o hello-regenerated.wit
```

```
package example:hello;

interface greeter {
    greet: func(name: string) -> string;
    goodbye: func() -> string;
}

VALID Round-trip validation passed
```

## Batch Processing

Process multiple WIT sources efficiently:

### Create a Batch Input File

Create `sources.jsonl`:

```json
{"name": "greeter", "source": "package example:hello; interface greeter { greet: func(name: string) -> string; }"}
{"name": "users", "source": "package example:users; interface users { get-user: func(id: u64) -> string; }"}
{"name": "orders", "source": "package example:orders; interface orders { create-order: func() -> u64; }"}
```

### Process All Sources

```bash
morphir wit make --jsonl-input sources.jsonl --jsonl
```

Output (one line per source):
```json
{"name":"greeter","success":true,"typeCount":0,"valueCount":1,"module":{...}}
{"name":"users","success":true,"typeCount":0,"valueCount":1,"module":{...}}
{"name":"orders","success":true,"typeCount":0,"valueCount":1,"module":{...}}
```

### Process from Stdin

```bash
echo '{"name": "test", "source": "package a:b; interface foo { x: func(); }"}' | \
  morphir wit make --jsonl-input - --jsonl
```

## Common Workflows

### Validate WIT Files in CI

```bash
#!/bin/bash
# validate-wit.sh

# Find all WIT files and create JSONL input
find ./wit -name "*.wit" | while read f; do
    echo "{\"file\": \"$f\"}"
done > /tmp/wit-sources.jsonl

# Compile and check for failures
morphir wit make --jsonl-input /tmp/wit-sources.jsonl --jsonl > /tmp/results.jsonl

# Exit with error if any failed
if grep -q '"success":false' /tmp/results.jsonl; then
    echo "WIT validation failed:"
    grep '"success":false' /tmp/results.jsonl
    exit 1
fi

echo "All WIT files validated successfully"
```

### Strict Validation

For stricter validation (warnings become errors):

```bash
morphir wit make hello.wit --warnings-as-errors --strict
```

### Verbose Output

To see all diagnostics:

```bash
morphir wit make hello.wit -v
```

## Next Steps

- [What's New](whats-new.md) - Learn about all new features
- [WIT Command Reference](commands/wit.md) - Complete command documentation
- [Release Notes](release-notes/v0.4.0-alpha.1.md) - Detailed changelog

## Troubleshooting

### Command Not Found

After installation, you may need to add the binary to your PATH:

**Linux/macOS:**
```bash
export PATH="$PATH:/usr/local/bin"
```

**Windows:**
Restart your terminal for PATH changes to take effect.

### Parse Errors

If WIT parsing fails, check:
1. Package declaration is present (`package namespace:name;`)
2. Interface syntax is correct
3. Type references are valid

Example error:
```json
{"success":false,"error":"parse error at line 3: expected 'func'"}
```

### Unsupported Types

Some WIT types are not yet supported:
- `flags` - Use enum or record instead
- `resource` - Use record with handle field

The `--strict` flag will fail on unsupported types instead of silently ignoring them.

## Getting Help

- **Documentation**: [morphir.finos.org](https://morphir.finos.org)
- **Issues**: [GitHub Issues](https://github.com/finos/morphir/issues)
- **Discussions**: [GitHub Discussions](https://github.com/finos/morphir/discussions)
