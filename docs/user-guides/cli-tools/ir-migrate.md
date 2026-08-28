---
id: ir-migrate
title: IR Migration Guide
sidebar_position: 10
---

# IR Migrate Command

The `morphir ir migrate` command converts Morphir IR between format versions. This is useful when upgrading projects from Classic format (V1-V3) to V4 format, or for backward compatibility when working with older tooling.

:::caution Format conversion is not available yet
In the current release, `morphir ir migrate` detects the input format, validates it, and can copy or display the IR, but the Classic ↔ V4 converter is disabled pending type system updates. Any run that requires an actual format change (for example `--target-version v4` on Classic input, or `--target-version classic` on V4 input) reports that the conversion is not yet implemented and exits with status 1. The conversion examples below describe the intended behavior once the converter is enabled.
:::

## Overview

Morphir IR has two main format generations:

| Format | Versions | Characteristics |
|--------|----------|-----------------|
| **Classic** | V1, V2, V3 | Tagged array format: `["Variable", {}, ["name"]]` |
| **V4** | 4.x | Object wrapper format: `{ "Variable": { "name": "a" } }` |

The migrate command handles bidirectional conversion between these formats while preserving semantic meaning.

## Usage

```bash
morphir ir migrate <INPUT> -o <OUTPUT> [OPTIONS]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<INPUT>` | Input source: local file path, URL, or remote source shorthand |

### Options

| Option | Description |
|--------|-------------|
| `-o, --output <OUTPUT>` | Output file path for migrated IR (if omitted, displays to console with syntax highlighting) |
| `--target-version <VERSION>` | Target format version: `latest`, `v4`/`4`, `classic`, `v3`/`3`, `v2`/`2`, `v1`/`1` (default: `latest`, which is currently `v4`) |
| `--force-refresh` | Force refresh cached remote sources |
| `--no-cache` | Skip cache entirely for remote sources |
| `--json` | Output result as JSON for scripting |

### Supported Input Sources

The `<INPUT>` argument accepts multiple source types:

| Source Type | Format | Example |
|-------------|--------|---------|
| **Local file** | File path | `./morphir-ir.json` |
| **HTTP/HTTPS** | URL | `https://example.com/morphir-ir.json` |
| **GitHub shorthand** | `github:owner/repo[@ref][/path]` | `github:finos/morphir-examples@main/examples/basic` |
| **Git URL** | `https://*.git` | `https://github.com/org/repo.git` |
| **Gist** | `gist:id[#filename]` | `gist:abc123#morphir-ir.json` |

## Examples

### Migrate Classic to V4

Convert an existing Classic format IR to the new V4 format:

```bash
morphir ir migrate ./morphir-ir.json \
    --output ./morphir-ir-v4.json \
    --target-version v4
```

Output:
```
Migrating IR from "./morphir-ir.json" to "./morphir-ir-v4.json"
Converting Classic -> V4
Migration complete.
```

### Migrate V4 to Classic

Downgrade a V4 IR file to Classic format for compatibility with older tools:

```bash
morphir ir migrate ./morphir-ir-v4.json \
    --output ./morphir-ir-classic.json \
    --target-version classic
```

Output:
```
Migrating IR from "./morphir-ir-v4.json" to "./morphir-ir-classic.json"
Converting V4 -> Classic
Migration complete.
```

### Default Behavior (Upgrade to V4)

When `--target-version` is omitted, the command defaults to V4:

```bash
morphir ir migrate ./morphir-ir.json \
    --output ./morphir-ir-migrated.json
```

### Console Output with Pager

When `--output` is omitted (and `--json` is not set), the migrated IR is displayed in an interactive pager with JSON syntax highlighting:

```bash
morphir ir migrate ./morphir-ir.json
```

The command uses (in order of preference):
1. **bat** - Best experience with built-in syntax highlighting and scrolling
2. **$PAGER** - Your configured pager (from environment variable)
3. **less** - Common pager with ANSI color support (`less -R`)
4. **most** - Alternative pager with color support
5. **more** - Basic pager (no color support)
6. **Direct output** - If no pager is available, outputs directly with syntax highlighting

This is useful for quickly inspecting migrated IR without creating a file. Use standard pager keys (q to quit, arrow keys to scroll, / to search).

### In-place Migration

To migrate in-place (overwrite the original), use the same path for input and output:

```bash
morphir ir migrate ./morphir-ir.json \
    --output ./morphir-ir.json \
    --target-version v4
```

### JSON Output for Scripting

Use `--json` to get machine-readable output for CI/CD pipelines and scripts:

```bash
morphir ir migrate ./morphir-ir.json \
    --output ./morphir-ir-v4.json \
    --json
```

Success output:
```json
{
  "success": true,
  "input": "./morphir-ir.json",
  "output": "./morphir-ir-v4.json",
  "source_format": "classic",
  "target_format": "v4"
}
```

Error output:
```json
{
  "success": false,
  "input": "./nonexistent.json",
  "output": "./output.json",
  "error": "Failed to load input: file not found"
}
```

With warnings:
```json
{
  "success": true,
  "input": "./morphir-ir.json",
  "output": "./morphir-ir-v4.json",
  "source_format": "classic",
  "target_format": "v4",
  "warnings": [
    "3 dependencies found in Classic format. Dependency conversion is not yet supported and will be omitted."
  ]
}
```

## Remote Sources

The migrate command supports fetching IR from remote sources, making it easy to work with published Morphir models without downloading them manually.

### HTTP/HTTPS URLs

Fetch and migrate IR directly from a URL:

```bash
# Migrate the LCR (Liquidity Coverage Ratio) IR - a comprehensive regulatory model
morphir ir migrate https://lcr-interactive.finos.org/server/morphir-ir.json \
    --output ./lcr-v4.json \
    --target-version v4
```

The LCR IR is a large, comprehensive example of Morphir in production use, implementing the Basel III Liquidity Coverage Ratio regulation.

### GitHub Shorthand

Use the `github:` shorthand for GitHub repositories:

```bash
# Fetch from a specific branch
morphir ir migrate github:finos/morphir-examples@main/examples/basic/morphir-ir.json \
    --output ./example-v4.json

# Fetch from a tag
morphir ir migrate github:finos/morphir-examples@v1.0.0/examples/basic/morphir-ir.json \
    --output ./example-v4.json
```

### Caching

Remote sources are cached locally to avoid repeated downloads:

```bash
# Force refresh - re-download even if cached
morphir ir migrate https://lcr-interactive.finos.org/server/morphir-ir.json \
    --output ./lcr-v4.json \
    --force-refresh

# Skip cache entirely
morphir ir migrate github:finos/morphir-examples/examples/basic/morphir-ir.json \
    --output ./example-v4.json \
    --no-cache
```

Cache is stored in `~/.cache/morphir/sources/` by default.

### Configuration

Remote source access can be configured in `morphir.toml`:

```toml
[sources]
enabled = true
allow = ["github:finos/*", "https://lcr-interactive.finos.org/*"]
deny = ["*://untrusted.com/*"]
trusted_github_orgs = ["finos", "morphir-org"]

[sources.cache]
directory = "~/.cache/morphir/sources"
max_size_mb = 500
ttl_secs = 86400  # 24 hours
```

## Real-World Example: US Federal Reserve FR 2052a Regulation

This section demonstrates migrating a real-world Morphir IR: the **Liquidity Coverage Ratio (LCR)** model, which implements the US Federal Reserve's FR 2052a Complex Institution Liquidity Monitoring Report.

### About the LCR Model

The LCR IR is a production-quality example of Morphir used for regulatory compliance:

- **Purpose**: Models data tables and business rules for liquidity reporting
- **Regulation**: US Federal Reserve FR 2052a
- **Format**: Classic (V3)
- **Size**: ~2MB, containing hundreds of type definitions and functions

The model includes:
- **Inflow tables**: Asset inflows, unsecured inflows, secured inflows
- **Outflow tables**: Deposit outflows, wholesale funding, secured funding
- **Supplemental tables**: Derivatives collateral, FX exposure, balance sheet items

### Step 1: Fetch and Inspect the IR

First, download and examine the source IR:

```bash
# Download the LCR IR
curl -o lcr-classic.json https://lcr-interactive.finos.org/server/morphir-ir.json

# Check the format version
jq '.formatVersion' lcr-classic.json
# Output: 3
```

The `formatVersion: 3` indicates this is a Classic format IR.

### Step 2: Examine the Classic Structure

Let's look at a type definition in Classic format:

```bash
# View the package structure
jq '.distribution[1]' lcr-classic.json | head -20
```

Classic format uses tagged arrays for expressions:

```json
{
  "formatVersion": 3,
  "distribution": [
    "Library",
    [["regulation"]],
    [],
    {
      "modules": [
        [
          [["regulation"], ["u", "s"], ["f", "r", "2052", "a"], ["data", "tables"]],
          {
            "types": [
              [
                ["currency"],
                ["Public", ["TypeAliasDefinition", [], ["Reference", {}, [["morphir"], ["s", "d", "k"]], [["string"]], []]]]
              ]
            ]
          }
        ]
      ]
    }
  ]
}
```

### Step 3: Migrate to V4 Format

Now migrate the IR to V4 format:

```bash
morphir ir migrate https://lcr-interactive.finos.org/server/morphir-ir.json \
    --output ./lcr-v4.json \
    --target-version v4
```

Expected output:
```
Migrating IR from "https://lcr-interactive.finos.org/server/morphir-ir.json" to "./lcr-v4.json"
Source format: Classic (V3)
Target format: V4
Downloading from remote source...
Converting 1 package, 5 modules, 847 types, 312 values...
Migration complete.
Output written to: ./lcr-v4.json
```

### Step 4: Compare the Results

Examine the V4 output structure:

```bash
# Check the new format version
jq '.formatVersion' lcr-v4.json
# Output: "4.0.0"
```

The same type definition in V4 compact format:

```json
{
  "formatVersion": "4.0.0",
  "distribution": {
    "Library": {
      "packageName": "regulation",
      "dependencies": {},
      "def": {
        "modules": {
          "regulation/u-s/f-r-2052-a/data-tables": {
            "types": {
              "currency": {
                "access": "Public",
                "def": {
                  "TypeAliasDefinition": {
                    "typeParams": [],
                    "typeExp": "morphir/s-d-k:string#string"
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```

Note the compact type expression: a simple Reference with no type arguments becomes a bare FQName string.

### Key Differences Observed

| Aspect | Classic (V3) | V4 |
|--------|-------------|-----|
| **Format version** | `3` (integer) | `"4.0.0"` (semver string) |
| **Distribution** | `["Library", [...], [...], {...}]` | `{ "Library": {...} }` |
| **Module paths** | `[["regulation"], ["u", "s"], ...]` | `"regulation/u-s/..."` (kebab-case) |
| **Type references** | `["Reference", {}, [...], [...], []]` | `"pkg:mod#name"` (bare FQName) |
| **Type variables** | `["Variable", {}, ["a"]]` | `"a"` (bare name) |
| **Value references** | `["Reference", {}, [...]]` | `{"Reference": "pkg:mod#name"}` |
| **Access modifiers** | `["Public", ...]` | `{ "access": "Public", ... }` |

### Step 5: Verify the Migration

You can verify the migration preserved all data:

```bash
# Count types in both versions
echo "Classic types: $(jq '[.. | .types? // empty | keys | length] | add' lcr-classic.json)"
echo "V4 types: $(jq '[.. | .types? // empty | keys | length] | add' lcr-v4.json)"

# Both should show the same count
```

### Using the Migrated IR

The V4 format IR can now be used with:

- **morphir-rust** tooling (schema generation, validation)
- **Modern Morphir toolchains** expecting V4 format
- **Code generators** that read the cleaner V4 structure

```bash
# Generate JSON Schema from the migrated V4 IR
morphir schema generate \
    --input ./lcr-v4.json \
    --output ./lcr-schema.json
```

## Format Differences

V4 uses a compact object notation that is both human-readable and unambiguous. The format uses contextual compaction where possible.

### Type Expressions

Type expressions use maximally compact forms since their context is unambiguous.

**Variable**

Classic: `["Variable", {}, ["a"]]`

V4 (compact): `"a"` — bare name string (no `:` or `#` distinguishes from FQName)

**Reference (no type arguments)**

Classic: `["Reference", {}, [["morphir"], ["s", "d", "k"]], [["string"]], ["string"]], []]`

V4 (compact): `"morphir/s-d-k:string#string"` — bare FQName string

**Reference (with type arguments)**

Classic: `["Reference", {}, [["morphir"], ["s", "d", "k"]], [["list"]], ["list"]], [["Variable", {}, ["a"]]]]`

V4: `{"Reference": ["morphir/s-d-k:list#list", "a"]}` — array with FQName first, followed by type args

**Record**

Classic: `["Record", {}, [[["field", "name"], type_expr], ...]]`

V4 (compact): `{"Record": {"field-name": "morphir/s-d-k:string#string", ...}}` — fields directly under Record

**Tuple**

Classic: `["Tuple", {}, [type1, type2]]`

V4: `{"Tuple": {"elements": ["morphir/s-d-k:int#int", "morphir/s-d-k:string#string"]}}`

### Value Expressions

Value expressions use object wrappers to distinguish expression types, but with compact inner values.

**Variable**

Classic: `["Variable", {}, ["x"]]`

V4: `{"Variable": "x"}` — name directly under Variable

**Reference**

Classic: `["Reference", {}, [["morphir"], ["s", "d", "k"]], [["basics"]], ["add"]]]`

V4: `{"Reference": "morphir/s-d-k:basics#add"}` — FQName directly under Reference

**Apply**

Classic:
```json
["Apply", {},
  ["Reference", {}, [["morphir"], ["s", "d", "k"]], [["basics"]], ["add"]],
  ["Literal", {}, ["IntLiteral", 1]]
]
```

V4:
```json
{
  "Apply": {
    "function": {"Reference": "morphir/s-d-k:basics#add"},
    "argument": {"Literal": {"IntLiteral": 1}}
  }
}
```

**Record**

Classic: `["Record", {}, [[["name"], value_expr], ...]]`

V4 (compact): `{"Record": {"name": {"Variable": "x"}, ...}}` — fields directly under Record

**Literal**

Classic: `["Literal", {}, ["IntLiteral", 42]]`

V4: `{"Literal": {"IntLiteral": 42}}`
```

### Module Structure

**Classic format:**
```json
{
  "formatVersion": 1,
  "distribution": ["Library", [...], [...], {
    "modules": [
      [["module", "name"], { "access": "Public", "value": {...} }]
    ]
  }]
}
```

**V4 format:**
```json
{
  "formatVersion": "4.0.0",
  "distribution": {
    "Library": {
      "packageName": "my/package",
      "dependencies": {},
      "def": {
        "modules": {
          "module/name": { "access": "Public", "value": {...} }
        }
      }
    }
  }
}
```

## Limitations

### V4 to Classic Downgrade

Some V4 constructs cannot be represented in Classic format:

- **Hole expressions**: Incomplete code placeholders
- **Native hints**: Platform-specific implementation details
- **External references**: Cross-platform bindings

Attempting to downgrade IR containing these constructs will result in an error.

### Metadata Loss

When converting between formats, some metadata may be lost or transformed:

| Classic → V4 | V4 → Classic |
|--------------|--------------|
| Empty `{}` attrs → TypeAttributes/ValueAttributes | Source locations lost |
| Array-based paths → Canonical strings | Constraints lost |
| Tuple entries → Keyed objects | Extensions preserved |

## Workflow Integration

### CI/CD Pipeline

Add migration as a build step to ensure V4 compatibility:

```yaml
# GitHub Actions example
- name: Migrate IR to V4
  run: |
    morphir ir migrate ./morphir-ir.json \
      --output ./dist/morphir-ir.json \
      --target-version v4
```

### Pre-commit Hook

Validate and migrate on commit:

```bash
#!/bin/bash
# .git/hooks/pre-commit
morphir ir migrate morphir-ir.json \
    --output morphir-ir.json \
    --target-version v4
git add morphir-ir.json
```

## Troubleshooting

### "Failed to load input"

Ensure the input file:
1. Exists at the specified path
2. Is valid JSON
3. Contains a valid Morphir IR structure

### "Cannot downgrade V4-only construct"

The IR contains V4-specific features. Either:
1. Remove the unsupported constructs from the source
2. Keep the IR in V4 format

### "Source URL not allowed by configuration"

The remote source is blocked by your `morphir.toml` configuration. The
allow/deny policy is enforced before any fetch, so cache flags such as
`--no-cache` cannot bypass it:
1. Check the `[sources.allow]` and `[sources.deny]` lists
2. Add the source URL to your allow list, or remove the matching deny rule

### "Failed to fetch source"

For remote source errors:
1. Check your network connection
2. Verify the URL is correct and accessible
3. For GitHub sources, ensure the repository is public or you have access
4. Try `--force-refresh` to bypass potentially corrupted cache
5. Check if git is installed (required for `github:` sources)

### Version Detection

The command automatically detects the input format based on:
- `formatVersion` field (1-3 = Classic, 4+ = V4)
- Distribution structure (tagged array vs object wrapper)

## See Also

- [Morphir IR Specification](../../spec/ir/morphir-ir-specification.md)
- [`morphir ir migrate` CLI reference](../../cli/ir/migrate.md)
