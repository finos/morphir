---
id: decorations-cli-reference
sidebar_position: 1
---

# Decoration CLI Reference

Complete reference for all decoration-related CLI commands.

## Commands Overview

- `morphir decoration setup` - Set up a decoration in project configuration
- `morphir decoration validate` - Validate decoration values against schemas
- `morphir decoration list` - List all decorated nodes
- `morphir decoration get` - Get decorations for a specific node
- `morphir decoration search` - Search for decorated nodes
- `morphir decoration stats` - Show decoration statistics
- `morphir decoration type register` - Register a decoration type
- `morphir decoration type list` - List registered decoration types
- `morphir decoration type show` - Show decoration type details
- `morphir decoration type unregister` - Unregister a decoration type

## decoration setup

Set up a decoration configuration in `morphir.json` or `morphir.toml`.

### Usage

```bash
morphir decoration setup [decoration-id] [flags]
```

### Flags

- `--type <type-id>` - Use a registered decoration type (alternative to `-i/-e`)
- `-i, --ir <path>` - Path to decoration IR file (required if `--type` not used)
- `-e, --entry-point <fqname>` - Entry point FQName (required if `--type` not used)
- `--storage-location <path>` - Path to decoration values file (default: `<decoration-id>-values.json`)
- `--display-name <name>` - Display name for the decoration (default: derived from decoration-id or type)

### Examples

```bash
# Using a registered type
morphir decoration setup docs --type documentation

# Using direct paths
morphir decoration setup myDecoration \
  -i decorations/morphir-ir.json \
  -e "My.Decoration:Module:Type" \
  --display-name "My Decoration"
```

## decoration validate

Validate all decoration values in the current project against their schemas.

### Usage

```bash
morphir decoration validate [flags]
```

### Flags

- `--json` - Output results as JSON

### Examples

```bash
# Validate all decorations
morphir decoration validate

# Validate with JSON output
morphir decoration validate --json
```

## decoration list

List all IR nodes that have decorations attached.

### Usage

```bash
morphir decoration list [flags]
```

### Flags

- `--type <type-id>` - Filter by decoration type ID
- `--json` - Output as JSON

### Examples

```bash
# List all decorated nodes
morphir decoration list

# List nodes with specific decoration type
morphir decoration list --type documentation
```

## decoration get

Get all decorations for a specific IR node.

### Usage

```bash
morphir decoration get <node-path> [flags]
```

### Arguments

- `<node-path>` - Node path in format `PackageName:ModuleName:LocalName` or `PackageName:ModuleName`

### Flags

- `--type <type-id>` - Filter by decoration type ID
- `--json` - Output as JSON

### Examples

```bash
# Get all decorations for a node
morphir decoration get "My.Package:Foo:bar"

# Get specific decoration type
morphir decoration get "My.Package:Foo:bar" --type documentation
```

## decoration search

Search for nodes with decorations matching criteria.

### Usage

```bash
morphir decoration search [flags]
```

### Flags

- `--type <type-id>` - Filter by decoration type ID (required)
- `--query <text>` - Search query (future: content-based search)

### Examples

```bash
# Search for nodes with documentation decoration
morphir decoration search --type documentation
```

## decoration stats

Display statistics about decorations in the current project.

### Usage

```bash
morphir decoration stats [flags]
```

### Flags

- `--json` - Output as JSON

### Examples

```bash
# Show decoration statistics
morphir decoration stats
```

## decoration type register

Register a decoration type in the registry for reuse across projects.

### Usage

```bash
morphir decoration type register <type-id> [flags]
```

### Arguments

- `<type-id>` - Unique identifier for the decoration type

### Flags

- `-i, --ir <path>` - Path to decoration IR file (required)
- `-e, --entry-point <fqname>` - Entry point FQName (required)
- `--display-name <name>` - Display name for the decoration (required)
- `--description <text>` - Description of the decoration
- `--global` - Register in global registry instead of workspace

### Examples

```bash
# Register in workspace
morphir decoration type register documentation \
  -i decorations/morphir-ir.json \
  -e "Documentation.Decoration:Types:Documentation" \
  --display-name "Documentation"

# Register globally
morphir decoration type register documentation \
  -i ~/.morphir/decorations/documentation/morphir-ir.json \
  -e "Documentation.Decoration:Types:Documentation" \
  --display-name "Documentation" \
  --global
```

## decoration type list

List all registered decoration types.

### Usage

```bash
morphir decoration type list [flags]
```

### Flags

- `--source <source>` - Filter by source (workspace, global, system, all) (default: all)
- `--json` - Output as JSON

### Examples

```bash
# List all types
morphir decoration type list

# List only workspace types
morphir decoration type list --source workspace
```

## decoration type show

Show detailed information about a registered decoration type.

### Usage

```bash
morphir decoration type show <type-id> [flags]
```

### Arguments

- `<type-id>` - Decoration type identifier

### Examples

```bash
morphir decoration type show documentation
```

## decoration type unregister

Remove a decoration type from the registry.

### Usage

```bash
morphir decoration type unregister <type-id> [flags]
```

### Arguments

- `<type-id>` - Decoration type identifier

### Flags

- `--global` - Unregister from global registry instead of workspace

### Examples

```bash
# Unregister from workspace
morphir decoration type unregister documentation

# Unregister from global registry
morphir decoration type unregister documentation --global
```

## Exit Codes

All commands follow standard exit code conventions:
- `0` - Success
- `1` - General error
- `2` - Invalid arguments or configuration

## JSON Output

Commands that support `--json` output machine-readable JSON suitable for automation and scripting. The JSON format is consistent and well-structured for parsing.
