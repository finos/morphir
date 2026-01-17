---
title: Node References ($ref)
sidebar_label: References
sidebar_position: 11
---

# Node References ($ref)

The `$ref` mechanism provides structural deduplication within VFS JSON files, reducing repetition of common node patterns.

## Design Principles

- **File-Local Only**: References resolve within the same file, no cross-file resolution
- **JSON Schema Style**: Uses familiar `$defs` and `$ref` patterns from JSON Schema
- **Shorthand Support**: Simple names resolve to `$defs` without full pointer syntax
- **Orthogonal to FQName**: `$ref` is for structural dedup; FQName is for semantic references
- **Optional**: Files without `$ref` are valid; deduplication is an optimization

## Relationship to FQName

| Mechanism | Purpose | Scope | Example |
|-----------|---------|-------|---------|
| **FQName** | Semantic type/value reference | Cross-package | `"morphir/sdk:string#string"` |
| **`$ref`** | Structural deduplication | File-local | `{ "$ref": "user" }` |

These are complementary:
- FQName references a *type* or *value* in the IR graph
- `$ref` avoids repeating the *same JSON structure* within a file

## Structure

### Definition Section (`$defs`)

Reusable nodes are defined in a top-level `$defs` object:

```json
{
  "formatVersion": "4.0.0",
  "name": "audit-record",
  "$defs": {
    "user": { "Reference": { "fqname": "my-org/domain:types#user" } },
    "date-time": { "Reference": { "fqname": "my-org/sdk:date-time#date-time" } },
    "maybe-user": {
      "Reference": {
        "fqname": "morphir/sdk:maybe#maybe",
        "args": [{ "$ref": "user" }]
      }
    }
  },
  "def": { ... }
}
```

### Reference Syntax

References use the `$ref` key:

```json
{ "$ref": "user" }
```

## Resolution Rules

### Shorthand Resolution

A simple name (no `#` or `/`) resolves to `$defs`:

| Reference | Resolves To |
|-----------|-------------|
| `{ "$ref": "user" }` | Value of `$defs.user` |
| `{ "$ref": "date-time" }` | Value of `$defs.date-time` |

### JSON Pointer Resolution

Full JSON Pointer syntax is supported for advanced cases:

| Reference | Resolves To |
|-----------|-------------|
| `{ "$ref": "#/$defs/user" }` | Value of `$defs.user` |
| `{ "$ref": "#/def/body" }` | Value at path `def.body` |

### Resolution Algorithm

```gleam
/// Resolve a $ref within a file
pub fn resolve_ref(ref: String, root: Dynamic) -> Result(Dynamic, RefError) {
  case string.starts_with(ref, "#/") {
    // Full JSON Pointer: "#/path/to/node"
    True -> {
      let path = ref |> string.drop_left(2) |> string.split("/")
      resolve_pointer(path, root)
    }
    // Shorthand: "name" -> "$defs.name"
    False -> {
      case dynamic.field("$defs", dynamic.field(ref, dynamic.dynamic))(root) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(UnresolvedRef(ref))
      }
    }
  }
}
```

## Gleam Type Definitions

```gleam
// === refs.gleam ===

/// A reference to another node in the same file
pub type Ref {
  /// Shorthand reference to $defs entry
  DefRef(name: String)
  /// Full JSON Pointer reference
  PointerRef(pointer: List(String))
}

/// Parse a $ref value
pub fn parse_ref(ref_string: String) -> Ref {
  case string.starts_with(ref_string, "#/") {
    True -> {
      let path = ref_string |> string.drop_left(2) |> string.split("/")
      PointerRef(path)
    }
    False -> DefRef(ref_string)
  }
}

/// Errors during reference resolution
pub type RefError {
  UnresolvedRef(name: String)
  InvalidPointer(path: List(String))
  CircularRef(chain: List(String))
}

/// File with definitions and potential references
pub type FileWithDefs(a) {
  FileWithDefs(
    defs: Dict(String, Dynamic),
    content: a,
  )
}
```

## JSON Examples

### Type Definition with Repeated References

**Before (no deduplication):**
```json
{
  "formatVersion": "4.0.0",
  "name": "audit-record",
  "def": {
    "TypeAliasDefinition": {
      "body": {
        "Record": {
          "fields": {
            "created-by": { "Reference": { "fqname": "my-org/domain:types#user" } },
            "created-at": { "Reference": { "fqname": "my-org/sdk:date-time#date-time" } },
            "updated-by": { "Reference": { "fqname": "my-org/domain:types#user" } },
            "updated-at": { "Reference": { "fqname": "my-org/sdk:date-time#date-time" } },
            "deleted-by": { "Reference": {
              "fqname": "morphir/sdk:maybe#maybe",
              "args": [{ "Reference": { "fqname": "my-org/domain:types#user" } }]
            } },
            "deleted-at": { "Reference": {
              "fqname": "morphir/sdk:maybe#maybe",
              "args": [{ "Reference": { "fqname": "my-org/sdk:date-time#date-time" } }]
            } }
          }
        }
      }
    }
  }
}
```

**After (with `$ref`):**
```json
{
  "formatVersion": "4.0.0",
  "name": "audit-record",
  "$defs": {
    "user": { "Reference": { "fqname": "my-org/domain:types#user" } },
    "date-time": { "Reference": { "fqname": "my-org/sdk:date-time#date-time" } },
    "maybe-user": { "Reference": {
      "fqname": "morphir/sdk:maybe#maybe",
      "args": [{ "$ref": "user" }]
    } },
    "maybe-date-time": { "Reference": {
      "fqname": "morphir/sdk:maybe#maybe",
      "args": [{ "$ref": "date-time" }]
    } }
  },
  "def": {
    "TypeAliasDefinition": {
      "body": {
        "Record": {
          "fields": {
            "created-by": { "$ref": "user" },
            "created-at": { "$ref": "date-time" },
            "updated-by": { "$ref": "user" },
            "updated-at": { "$ref": "date-time" },
            "deleted-by": { "$ref": "maybe-user" },
            "deleted-at": { "$ref": "maybe-date-time" }
          }
        }
      }
    }
  }
}
```

### Value Definition with Shared Expressions

```json
{
  "formatVersion": "4.0.0",
  "name": "process-order",
  "$defs": {
    "get-user": {
      "Apply": {
        "function": { "Reference": { "fqname": "my-org/domain:repo#get-user" } },
        "args": [{ "Variable": { "name": "user-id" } }]
      }
    },
    "validation-error": {
      "Apply": {
        "function": { "Reference": { "fqname": "morphir/sdk:result#err" } },
        "args": [{ "Literal": { "StringLiteral": "Validation failed" } }]
      }
    }
  },
  "def": {
    "access": "Public",
    "value": {
      "ExpressionBody": {
        "body": {
          "IfThenElse": {
            "condition": { "...": "..." },
            "thenBranch": { "$ref": "get-user" },
            "elseBranch": { "$ref": "validation-error" }
          }
        }
      }
    }
  }
}
```

### Nested References (Refs within Refs)

References can reference other definitions:

```json
{
  "$defs": {
    "string": { "Reference": { "fqname": "morphir/sdk:string#string" } },
    "list-of-string": {
      "Reference": {
        "fqname": "morphir/sdk:list#list",
        "args": [{ "$ref": "string" }]
      }
    },
    "maybe-list-of-string": {
      "Reference": {
        "fqname": "morphir/sdk:maybe#maybe",
        "args": [{ "$ref": "list-of-string" }]
      }
    }
  }
}
```

Resolution order doesn't matter - refs are resolved lazily or recursively.

## Processing Rules

### Reading (Expansion)

When reading a file, expand all `$ref` nodes:

1. Parse JSON file
2. For each `$ref` encountered during traversal:
   a. Resolve the reference to its target
   b. Replace the `$ref` node with a copy of the target
   c. Recursively expand any `$ref` in the copy
3. Detect circular references (error)

```gleam
/// Expand all refs in a JSON value
pub fn expand_refs(
  value: Dynamic,
  defs: Dict(String, Dynamic),
  seen: Set(String),
) -> Result(Dynamic, RefError) {
  case decode_ref(value) {
    Ok(ref_name) -> {
      // Check for circular reference
      case set.contains(seen, ref_name) {
        True -> Error(CircularRef(set.to_list(seen)))
        False -> {
          case dict.get(defs, ref_name) {
            Ok(target) -> expand_refs(target, defs, set.insert(seen, ref_name))
            Error(_) -> Error(UnresolvedRef(ref_name))
          }
        }
      }
    }
    Error(_) -> {
      // Not a ref, recursively process children
      expand_children(value, defs, seen)
    }
  }
}
```

### Writing (Extraction)

When writing a file, optionally extract common patterns to `$defs`:

1. Traverse the IR structure
2. Identify repeated subtrees (by structural equality)
3. Move repeated subtrees to `$defs` with generated names
4. Replace occurrences with `$ref`

This is an optimization - files can be written fully expanded.

### Validation

| Check | Severity | Description |
|-------|----------|-------------|
| Unresolved ref | Error | `$ref` points to non-existent definition |
| Circular ref | Error | Reference chain forms a cycle |
| Unused def | Warning | Entry in `$defs` never referenced |
| Shadowing | Warning | `$defs` key shadows a common name |

## Interaction with Other Features

### With Type Shorthand

`$ref` and type shorthand can be used together:

```json
{
  "$defs": {
    "user": "my-org/domain:types#user",
    "list-of-users": ["morphir/sdk:list#list", { "$ref": "user" }]
  },
  "def": {
    "TypeAliasDefinition": {
      "body": {
        "Record": {
          "fields": {
            "admins": { "$ref": "list-of-users" },
            "members": { "$ref": "list-of-users" }
          }
        }
      }
    }
  }
}
```

### With $meta

`$defs` and `$meta` are independent top-level keys:

```json
{
  "formatVersion": "4.0.0",
  "name": "user",
  "$meta": { "source": "src/User.elm", "compiler": "morphir-elm 3.0.0" },
  "$defs": { "string": "morphir/sdk:string#string" },
  "def": { ... }
}
```

### With Decorations

Decorations are stored separately in `deco/` and reference IR nodes by FQName, not by `$ref`. The two systems don't interact directly.

## Reserved Keys

The following keys have special meaning and should not be used in IR content:

| Key | Purpose |
|-----|---------|
| `$ref` | Reference to another node |
| `$defs` | Definition section for reusable nodes |
| `$meta` | File-level metadata |

## Encoding Recommendations

### When to Use `$ref`

**Do use `$ref` for:**
- Types appearing 3+ times in a file
- Complex nested structures (e.g., `Maybe (List User)`)
- Common SDK type combinations

**Don't use `$ref` for:**
- Simple types appearing 1-2 times (overhead not worth it)
- Cross-file deduplication (use FQName instead)
- Semantic relationships (use FQName)

### Naming Conventions

| Pattern | Example |
|---------|---------|
| Simple type | `"string"`, `"user"`, `"date-time"` |
| Parameterized | `"list-of-string"`, `"maybe-user"` |
| Complex | `"result-string-error"`, `"dict-string-int"` |

## Future Considerations

### Cross-File References

If needed later, could extend syntax:

```json
{ "$ref": "./common.type.json#/$defs/user" }
{ "$ref": "/pkg/my-org/common/types.json#/$defs/user" }
```

This would require:
- File resolution logic
- Dependency ordering
- Circular dependency detection across files

### Reference Metadata

Could add optional metadata to refs:

```json
{ "$ref": "user", "$comment": "The creating user" }
```

### Inline Anchors

Could add YAML-style inline anchors if demand exists:

```json
{ "$anchor": "user", "Reference": { "fqname": "my-org/domain:types#user" } }
```

This is not included in the initial design to keep things simple.
