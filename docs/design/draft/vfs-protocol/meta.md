---
title: File Metadata ($meta)
sidebar_label: Metadata
sidebar_position: 10
---

# File Metadata ($meta)

The `$meta` key provides a standard location for file-level metadata in VFS JSON files without polluting the main schema.

## Design Principles

- **File-Level Only**: `$meta` appears at the top level of VFS files, not on individual nodes
- **Open JSON**: Values are plain JSON objects, no special processing required
- **Optional**: Files without `$meta` are valid; tools must handle its absence
- **Extensible**: Namespaced extensions allow tool-specific data
- **Non-Semantic**: Metadata does not affect IR semantics or type checking

## Relationship to Other Features

| Feature | Purpose | Scope |
|---------|---------|-------|
| **`$meta`** | Operational metadata (provenance, tooling) | File-level |
| **Decorations** | Semantic annotations (docs, deprecated) | IR nodes |
| **`formatVersion`** | Schema version for parsing | File-level |
| **Attributes** | Type-level metadata on IR nodes | Node-level |

## Structure

```json
{
  "formatVersion": "4.0.0",
  "name": "user",
  "$meta": {
    "source": "src/Domain/User.elm",
    "sourceRange": { "start": [10, 1], "end": [25, 1] },
    "compiler": "morphir-elm 3.0.0",
    "generated": "2026-01-16T12:00:00Z",
    "checksum": "sha256:a1b2c3d4...",
    "extensions": {
      "my-tool": { ... }
    }
  },
  "def": { ... }
}
```

## Standard Fields

All standard fields are optional.

### Provenance Fields

| Field | Type | Description |
|-------|------|-------------|
| `source` | `String` | Path to the source file that generated this IR |
| `sourceRange` | `SourceRange` | Location within the source file |
| `compiler` | `String` | Tool and version that generated this file |
| `generated` | `String` | ISO 8601 timestamp of generation |
| `checksum` | `String` | Content hash with algorithm prefix (e.g., `sha256:...`) |

### Source Range

```json
{
  "sourceRange": {
    "start": [10, 1],
    "end": [25, 12]
  }
}
```

- `start`: `[line, column]` (1-indexed)
- `end`: `[line, column]` (1-indexed, inclusive)

### Tooling Fields

| Field | Type | Description |
|-------|------|-------------|
| `editedBy` | `String` | Last tool/user to modify this file |
| `editedAt` | `String` | ISO 8601 timestamp of last modification |
| `locked` | `Boolean` | Hint that file should not be auto-modified |
| `generated` | `Boolean` | True if file is generated (not hand-edited) |

### Extensions

The `extensions` field provides namespaced storage for tool-specific metadata:

```json
{
  "$meta": {
    "extensions": {
      "morphir-vscode": {
        "foldingRanges": [[5, 10], [15, 20]],
        "diagnosticLevel": "warning"
      },
      "my-company/custom-tool": {
        "internalId": "proj-123-user",
        "reviewStatus": "approved"
      }
    }
  }
}
```

**Namespace conventions:**
- Simple names for well-known tools: `"morphir-vscode"`, `"morphir-cli"`
- Scoped names for organization tools: `"my-company/tool-name"`
- Avoid conflicts by using unique prefixes

## Gleam Type Definitions

```gleam
// === meta.gleam ===

/// Source location range
pub type SourceRange {
  SourceRange(
    start: #(Int, Int),  // (line, column) 1-indexed
    end: #(Int, Int),    // (line, column) 1-indexed
  )
}

/// File-level metadata
pub type FileMeta {
  FileMeta(
    // Provenance
    source: Option(String),
    source_range: Option(SourceRange),
    compiler: Option(String),
    generated: Option(String),  // ISO 8601
    checksum: Option(String),

    // Tooling
    edited_by: Option(String),
    edited_at: Option(String),  // ISO 8601
    locked: Option(Bool),
    is_generated: Option(Bool),

    // Extensions (open-ended)
    extensions: Dict(String, Dynamic),
  )
}

/// Parse $meta from a JSON object
pub fn parse_meta(json: Dynamic) -> Result(Option(FileMeta), DecodeError) {
  case dynamic.field("$meta", dynamic.dynamic)(json) {
    Ok(meta_json) -> {
      use meta <- result.try(decode_file_meta(meta_json))
      Ok(Some(meta))
    }
    Error(_) -> Ok(None)  // $meta is optional
  }
}
```

## JSON Examples

### Type Definition File

File: `.morphir-dist/pkg/my-org/domain/types/user.type.json`

```json
{
  "formatVersion": "4.0.0",
  "name": "user",
  "$meta": {
    "source": "src/Domain/User.elm",
    "sourceRange": { "start": [15, 1], "end": [22, 1] },
    "compiler": "morphir-elm 3.2.0",
    "generated": "2026-01-16T14:30:00Z",
    "checksum": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  },
  "def": {
    "TypeAliasDefinition": {
      "body": {
        "Record": {
          "fields": {
            "email": "morphir/sdk:string#string",
            "name": "morphir/sdk:string#string"
          }
        }
      }
    }
  }
}
```

### Value Definition File

File: `.morphir-dist/pkg/my-org/domain/values/create-user.value.json`

```json
{
  "formatVersion": "4.0.0",
  "name": "create-user",
  "$meta": {
    "source": "src/Domain/User.elm",
    "sourceRange": { "start": [30, 1], "end": [45, 1] },
    "compiler": "morphir-elm 3.2.0",
    "generated": "2026-01-16T14:30:00Z",
    "extensions": {
      "morphir-analyze": {
        "complexity": 5,
        "purity": "pure",
        "callGraph": ["validate-email", "generate-id"]
      }
    }
  },
  "def": {
    "access": "Public",
    "value": { ... }
  }
}
```

### Module Manifest

File: `.morphir-dist/pkg/my-org/domain/module.json`

```json
{
  "formatVersion": "4.0.0",
  "path": "my-org/domain",
  "$meta": {
    "source": "src/Domain.elm",
    "compiler": "morphir-elm 3.2.0",
    "generated": "2026-01-16T14:30:00Z",
    "extensions": {
      "morphir-docs": {
        "readme": "docs/domain.md",
        "examples": ["examples/domain-basic.elm"]
      }
    }
  },
  "types": ["user", "order", "product"],
  "values": ["create-user", "process-order"]
}
```

### Format File

File: `.morphir-dist/format.json`

```json
{
  "formatVersion": "4.0.0",
  "distribution": "Library",
  "package": "my-org/my-project",
  "version": "1.2.0",
  "$meta": {
    "compiler": "morphir-elm 3.2.0",
    "generated": "2026-01-16T14:30:00Z",
    "source": "morphir.json",
    "extensions": {
      "morphir-ci": {
        "buildId": "build-12345",
        "pipeline": "main",
        "commit": "abc123def456"
      }
    }
  }
}
```

### Hand-Edited File

```json
{
  "formatVersion": "4.0.0",
  "name": "config",
  "$meta": {
    "generated": false,
    "editedBy": "alice@example.com",
    "editedAt": "2026-01-16T15:00:00Z",
    "locked": true
  },
  "def": { ... }
}
```

## Processing Rules

### Reading

1. Parse `$meta` if present; treat absence as empty metadata
2. Unknown fields in `$meta` should be preserved (forward compatibility)
3. Unknown fields in `extensions` should be preserved
4. Invalid `$meta` structure may be treated as a warning, not an error

### Writing

1. Include `$meta` when provenance information is available
2. Preserve existing `extensions` from other tools when updating
3. Update `editedAt` and `editedBy` when modifying files
4. Recalculate `checksum` if content changes

### Merging

When merging metadata from multiple sources:

```gleam
/// Merge two FileMeta, preferring values from `override`
pub fn merge_meta(base: FileMeta, override: FileMeta) -> FileMeta {
  FileMeta(
    source: option.or(override.source, base.source),
    source_range: option.or(override.source_range, base.source_range),
    compiler: option.or(override.compiler, base.compiler),
    generated: option.or(override.generated, base.generated),
    checksum: option.or(override.checksum, base.checksum),
    edited_by: option.or(override.edited_by, base.edited_by),
    edited_at: option.or(override.edited_at, base.edited_at),
    locked: option.or(override.locked, base.locked),
    is_generated: option.or(override.is_generated, base.is_generated),
    extensions: dict.merge(base.extensions, override.extensions),
  )
}
```

## Checksum Format

Checksums use a prefixed format to identify the algorithm:

```
algorithm:hexdigest
```

**Supported algorithms:**
- `sha256:...` (recommended)
- `sha1:...` (legacy)
- `md5:...` (legacy, not recommended)

**Example:**
```json
{
  "$meta": {
    "checksum": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  }
}
```

## Validation

`$meta` validation is lenient to support forward compatibility:

| Check | Severity | Action |
|-------|----------|--------|
| Unknown standard field | Info | Preserve, log |
| Invalid field type | Warning | Ignore field, preserve raw |
| Invalid `sourceRange` | Warning | Ignore field |
| Invalid timestamp format | Warning | Preserve as string |
| Unknown extension namespace | None | Preserve |

## Security Considerations

- `$meta` should not contain secrets (API keys, credentials)
- `source` paths may reveal directory structure; consider stripping in public distributions
- `extensions` from untrusted sources should be treated as untrusted data
- `checksum` can verify integrity but not authenticity (no signatures)

## Future Considerations

### Signatures

Digital signatures could be added for authenticity:

```json
{
  "$meta": {
    "checksum": "sha256:...",
    "signature": {
      "algorithm": "ed25519",
      "publicKey": "...",
      "value": "..."
    }
  }
}
```

### Compression Hints

For large files, compression hints could guide tooling:

```json
{
  "$meta": {
    "compression": {
      "algorithm": "gzip",
      "originalSize": 102400
    }
  }
}
```

### Related Files

Cross-references to related artifacts:

```json
{
  "$meta": {
    "related": {
      "test": "tests/domain/user-test.value.json",
      "docs": "docs/domain/user.md"
    }
  }
}
```
