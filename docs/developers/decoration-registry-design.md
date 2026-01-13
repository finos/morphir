# Decoration Registry Design

## Overview

A decoration registry provides a catalog of available decoration types and a way to discover and manage decoration values across projects. This improves the developer experience by enabling:

- **Discovery**: Find available decoration types without knowing file paths
- **Reuse**: Share decoration schemas across projects/workspaces
- **Query**: List and search decoration values across the workspace
- **Simplified Setup**: Reference decorations by name instead of paths

## Architecture

### Two-Level Registry System

1. **Decoration Type Registry** - Catalog of decoration schemas (IR files)
2. **Decoration Value Registry** - Query interface for decoration values (already exists, but could be enhanced)

### Decoration Type Registry

A registry that catalogs available decoration types (schemas) that can be used across projects.

#### Storage Location

- **Workspace-level**: `.morphir/decorations/registry.json` (project-specific)
- **Global**: `~/.morphir/decorations/registry.json` (user-wide, optional)
- **System**: `/etc/morphir/decorations/registry.json` (system-wide, optional)

Priority: Workspace > Global > System (similar to config loading)

#### Registry Format

```json
{
  "version": "1.0",
  "types": {
    "documentation": {
      "id": "documentation",
      "display_name": "Documentation",
      "description": "Add documentation and descriptions to IR nodes",
      "ir_path": "~/.morphir/decorations/documentation/morphir-ir.json",
      "entry_point": "Morphir.Decorations.Documentation:Types:Documentation",
      "source": "workspace",
      "registered_at": "2026-01-09T10:00:00Z"
    },
    "tags": {
      "id": "tags",
      "display_name": "Tags",
      "description": "Tag IR nodes with custom labels",
      "ir_path": "decorations/tags/morphir-ir.json",
      "entry_point": "My.Project.Tags:Types:TagSet",
      "source": "workspace",
      "registered_at": "2026-01-09T11:00:00Z"
    }
  }
}
```

#### Registry Structure

```go
type DecorationTypeRegistry struct {
    types map[string]DecorationType
}

type DecorationType struct {
    ID          string    // Unique identifier (e.g., "documentation")
    DisplayName string    // Human-readable name
    Description string    // Optional description
    IRPath      string    // Path to decoration IR file
    EntryPoint  string    // FQName of entry point type
    Source      string    // "workspace", "global", "system"
    RegisteredAt time.Time
}
```

### CLI Commands

#### Type Registry Commands

```bash
# Register a decoration type
morphir decoration type register <type-id> \
  -i <ir-path> \
  -e <entry-point> \
  --display-name "My Decoration" \
  --description "Description of what this decoration does" \
  --global  # Register globally instead of workspace

# List all registered types
morphir decoration type list [--json] [--source workspace|global|system|all]

# Show details about a type
morphir decoration type show <type-id>

# Unregister a type
morphir decoration type unregister <type-id> [--global]

# Update a registered type
morphir decoration type update <type-id> [flags...]
```

#### Enhanced Setup Command

```bash
# Use registered type instead of paths
morphir decoration setup myDecoration --type documentation

# Or still use direct paths (backward compatible)
morphir decoration setup myDecoration -i path/to/ir.json -e "Package:Module:Type"
```

#### Value Registry Commands

```bash
# List all decorated nodes
morphir decoration list [--type <type-id>] [--json]

# Get decorations for a specific node
morphir decoration get <node-path> [--type <type-id>] [--json]

# Search for nodes with specific decorations
morphir decoration search --type documentation --query "description"

# Show decoration statistics
morphir decoration stats [--json]
```

## Implementation Plan

### Phase 1: Type Registry Foundation

1. **Create registry storage layer**
   - `pkg/tooling/decorations/registry/types.go` - Type registry implementation
   - Support workspace, global, and system registries
   - Load/merge registries with priority (workspace > global > system)

2. **Implement registry commands**
   - `morphir decoration type register` - Add type to registry
   - `morphir decoration type list` - List available types
   - `morphir decoration type show` - Show type details
   - `morphir decoration type unregister` - Remove type
   - `morphir decoration type update` - Update type metadata

3. **Enhance setup command**
   - Add `--type <type-id>` flag
   - Auto-populate IR path and entry point from registry
   - Maintain backward compatibility with `-i` and `-e` flags

### Phase 2: Value Query Interface

1. **Enhance value discovery**
   - `morphir decoration list` - List all decorated nodes
   - `morphir decoration get` - Get decorations for a node
   - `morphir decoration search` - Search decorations

2. **Add statistics**
   - `morphir decoration stats` - Show decoration statistics

### Phase 3: Advanced Features

1. **Registry sharing**
   - Export/import registry entries
   - Share via URL or file
   - Registry validation

2. **Auto-discovery**
   - Scan workspace for decoration IR files
   - Suggest registration for unregistered types

3. **Registry validation**
   - Validate IR files still exist
   - Check entry points are still valid
   - Clean up invalid entries

## Benefits

1. **Better UX**: Users can reference decorations by name
2. **Discovery**: Find available decoration types easily
3. **Reuse**: Share decoration schemas across projects
4. **Consistency**: Standard decoration types across workspace
5. **Query**: Easy access to decoration information

## Example Workflow

```bash
# 1. Register a decoration type (one time)
morphir decoration type register documentation \
  -i ~/.morphir/decorations/documentation/morphir-ir.json \
  -e "Morphir.Decorations.Documentation:Types:Documentation" \
  --display-name "Documentation" \
  --description "Add documentation to IR nodes" \
  --global

# 2. List available decoration types
morphir decoration type list

# 3. Set up decoration in project (uses registered type)
morphir decoration setup docs --type documentation

# 4. List all decorated nodes
morphir decoration list

# 5. Get decorations for a specific node
morphir decoration get "My.Package:Foo:Bar"

# 6. Validate all decorations
morphir decoration validate
```

## Design Decisions

### Registry Storage

- **JSON format**: Simple, human-readable, easy to edit
- **Multiple sources**: Workspace, global, system (like config)
- **Priority merging**: Workspace overrides global, global overrides system

### Type IDs

- **Simple strings**: Easy to reference (e.g., "documentation", "tags")
- **Validation**: Must be valid identifiers
- **Uniqueness**: Enforced per source level

### Backward Compatibility

- **Existing commands still work**: `-i` and `-e` flags remain
- **Registry is optional**: Projects can still use direct paths
- **Gradual adoption**: Teams can adopt registry over time

## Future Enhancements

1. **Remote registries**: Fetch decoration types from URLs
2. **Decoration marketplace**: Share decoration types publicly
3. **Versioning**: Support multiple versions of decoration types
4. **Dependencies**: Decoration types can depend on other types
5. **Templates**: Pre-configured decoration setups
