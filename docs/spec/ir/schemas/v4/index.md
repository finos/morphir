---
title: "Schema Version 4"
linkTitle: "Version 4"
weight: 1
description: "Morphir IR JSON Schema for format version 4 (Draft)"
---

# Morphir IR Schema - Version 4 (Draft)

Format version 4 is the next generation of the Morphir IR format. It replaces generic attributes with explicit `TypeAttributes` and `ValueAttributes` structures, introduces canonical string formats, and adds new value expressions for enhanced expressiveness.

## Normative layers

Version 4 separates meaning from physical storage:

- [Semantic IR model](semantic-model.md) defines versioned IR values and semantic equality.
- [JSON serialization profile](json-profile.md) defines JSON storage and the role of JSON Schema.
- [YAML serialization profile](yaml-profile.md) defines native, lossless YAML storage.
- [Document-tree profile](document-tree-files.md) maps logical documents to homogeneous JSON or YAML trees.

JSON Schema bootstraps the JSON profile. It does not make JSON the only native IR storage format.

The `formatVersion` field follows the [shared v3-and-later contract](../../format-version.md).
Integer `4` is the canonical v4.0.0 baseline. Later v4 revisions use exact release
strings such as `"4.1.0"`; prerelease and build metadata are not allowed.

## Overview

Version 4 standardizes attribute handling, introduces compact string representations, supports embedded documentation, and adds new value expressions to better represent functional programming constructs.

## Key Features

### Explicit Attributes

**TypeAttributes** and **ValueAttributes** replace the generic `a` parameter:

```yaml
TypeAttributes:
  type: object
  properties:
    source: { $ref: "#/definitions/SourceLocation" }
    constraints: { type: object }
    extensions: { type: object }

ValueAttributes:
  type: object
  properties:
    source: { $ref: "#/definitions/SourceLocation" }
    inferredType: { $ref: "#/definitions/Type" }
    extensions: { type: object }

SourceLocation:
  type: object
  required: [startLine, startColumn, endLine, endColumn]
  properties:
    startLine: { type: integer }
    startColumn: { type: integer }
    endLine: { type: integer }
    endColumn: { type: integer }
```

**Benefits:**
- Precise source code locations for better error messages
- Type inference results embedded in IR
- Extensibility through `extensions` field
- Tool-specific metadata without breaking schema

### Canonical String Formats

V4 supports compact string representations for Names, Paths, and FQNames:

**Name:**
```
Array:  ["value", "in", "u", "s", "d"]   (legacy; decodes to the string below)
String: "value-in-USD"
```

**Path:**
```
Array:  [["morphir"], ["s", "d", "k"]]
String: "morphir/SDK"
```

**FQName:**
```
Array:  [[["morphir"], ["s", "d", "k"]], [["list"]], ["map"]]
String: "morphir/SDK:list#map"
```

**Annotations:**
V4 introduces structured annotations for semantic metadata:
```json
"annotations": ["morphir/SDK:annotations#stable"]
```

**Benefits:**
- 30% smaller IR files
- More readable references
- Metadata for signatures via Annotations
- Better tooling support

### Embedded Documentation

V4 supports inline documentation for types and values:

```json
{
  "types": {
    "user-id": {
      "access": "Public",
      "doc": "Unique identifier for a user in the system",
      "TypeAliasSpecification": {
        "typeParams": [],
        "typeExp": "morphir/SDK:string#string"
      }
    }
  }
}
```

### New Value Expressions

V4 introduces several new value expression types:

- **Constructor**: Direct constructor reference (first-class constructors)
- **List**: Native list literal expression
- **FieldFunction**: Field accessor as a function (`.fieldName`)
- **LetRecursion**: Mutually recursive definitions
- **Destructure**: Pattern-based destructuring in let bindings
- **UpdateRecord**: Record update syntax (`{ record | field = value }`)
- **Unit**: Explicit unit value

**Example - Constructor:**
```elm
-- Elm code
List.map Just [1, 2, 3]

-- V4 IR (Compact Canonical)
```json
{
  "Apply": {
    "function": {
      "Apply": {
        "function": "morphir/SDK:list#map",
        "argument": "morphir/SDK:maybe#Just"
      }
    },
    "argument": [1, 2, 3]
  }
}
```

### Standalone module document support

V4 supports standalone logical module documents. Their physical extension follows the selected serialization profile:

```
my-package/
  manifest.yaml
  modules/
    MyModule.module.yaml
    Sub/
      Module.module.yaml
```

**Benefits:**
- Incremental compilation
- Parallel processing
- Better version control diffs
- Lazy loading

## Core Concepts

### Naming System

Version 4 supports both array and string formats for names:

#### Name

A **Name** represents a human-readable identifier. Segments are joined by `-`. A lowercase segment is a word; an uppercase segment is an initialism. A mixed-case segment is invalid.

- **Array format (legacy)**: `["value", "in", "u", "s", "d"]`, where a run of two or more single-letter words decodes to one initialism
- **String format**: `"value-in-USD"`
- **Pattern**: `^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$`

#### Path

A **Path** represents a hierarchical location.

- **Array format (legacy)**: `[["morphir"], ["s", "d", "k"]]`
- **String format**: `"morphir/SDK"`
- **Pattern**: `^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*$`

#### FQName

A **Fully-Qualified Name** provides globally unique identifiers.

- **Array format (legacy)**: `[pkg, mod, name]`
- **String format**: `"pkg:mod#name"`
- **Pattern**: the Path pattern, then `:`, then the Path pattern, then `#`, then the Name pattern

The full grammar, the document-tree filename escape, and the conformance corpus are in the [naming specification](../../../draft/names.md).

### Access Control

V4 accepts three spellings of an access-controlled value. The tag form is canonical:

```json
{ "Public": { ... } }                                      // canonical; "Private", "pub", "public", "private" also accepted
{ "access": "Public", "TypeAliasDefinition": { ... } }     // flattened: access beside the definition variant
{ "access": "Public", "value": { ... } }                   // legacy V3 shape
```

The flattened form is what the document-tree files and the published examples use. Encoders should output the canonical form; decoders must accept all three.

## Distribution and Package Structure

### Distribution

V4 uses wrapper object format (key-based tagging) instead of tagged arrays:

```yaml
distribution:
  oneOf:
    - $ref: "#/definitions/LibraryDistribution"
    - $ref: "#/definitions/SpecsDistribution"
    - $ref: "#/definitions/ApplicationDistribution"
```

**Library Distribution:**
```json
{
  "formatVersion": 4,
  "distribution": {
    "Library": {
      "packageName": "my-org/my-project",
      "dependencies": {
        "morphir/SDK": { "modules": [...] }
      },
      "def": { "modules": [...] }
    }
  }
}
```

**Specs Distribution:**
```json
{
  "formatVersion": 4,
  "distribution": {
    "Specs": {
      "packageName": "morphir/SDK",
      "dependencies": {
        "other/pkg": { "modules": [...] }
      },
      "spec": { "modules": [...] }
    }
  }
}
```

**Application Distribution:**
```json
{
  "formatVersion": 4,
  "distribution": {
    "Application": {
      "packageName": "my-org/my-app",
      "dependencies": {
        "morphir/SDK": { "modules": [...] }
      },
      "def": { "modules": [...] },
      "entryPoints": {
        "startup": {
          "target": "my-org/my-app:main#run",
          "kind": "main",
          "doc": "Application entry point"
        },
        "build": {
          "target": "my-org/my-app:cli#build",
          "kind": "command",
          "doc": "Build command"
        },
        "api-handler": {
          "target": "my-org/my-app:api#handle",
          "kind": "handler",
          "doc": "HTTP API handler"
        }
      }
    }
  }
}
```

> **Note on Entry Points:** The `entryPoints` object uses keys (e.g., `"startup"`, `"build"`, `"api-handler"`) as arbitrary identifiers chosen by developers. Each entry point has a `kind` field (e.g., `"main"`, `"command"`, `"handler"`) that categorizes it semantically. The name and kind can differ - for example, an entry point named `"startup"` can have `kind: "main"`, or `"api-handler"` can have `kind: "handler"`. The name is for identification, while the kind is for semantic categorization used by tooling and runtime.

## Document Tree File Formats

V4 supports VFS (Virtual File System) mode where distributions are stored as directory trees with individual files for each definition.

**Physical file profiles**:
- JSON: `manifest.json`, `module.json`, `*.type.json`, and `*.value.json`
- YAML: `manifest.yaml`, `module.yaml`, `*.type.yaml`, and `*.value.yaml`

One tree uses one serialization profile. Logical identities do not contain either extension.

**Complete Documentation**: See [Document Tree File Formats](document-tree-files.md) for:
- Complete file format specifications with detailed examples
- Required and optional fields for each file type
- Encoding styles (manifest vs inline)
- Directory structure examples
- Field details and validation rules
- Error handling and common validation errors
- Advanced examples (incomplete types, external values, complex expressions)

**Formal Schemas**: See [morphir-ir-v4-document-tree-files.yaml](/schemas/morphir-ir-v4-document-tree-files.yaml) for JSON schemas validating all document tree file formats.

## Complete Example

A complete Library distribution example showing the full structure:

```json
{
  "formatVersion": "4.0.0",
  "distribution": {
    "Library": {
      "packageName": "regulation",
      "dependencies": {
        "morphir/SDK": {
          "modules": {
            "basics": {
              "types": {
                "int": {
                  "OpaqueTypeSpecification": {}
                },
                "float": {
                  "OpaqueTypeSpecification": {}
                },
                "bool": {
                  "OpaqueTypeSpecification": {}
                }
              },
              "values": {
                "add": {
                  "inputs": {
                    "a": "morphir/SDK:basics#int",
                    "b": "morphir/SDK:basics#int"
                  },
                  "output": "morphir/SDK:basics#int"
                }
              }
            },
            "list": {
              "types": {
                "list": {
                  "TypeAliasSpecification": {
                    "typeParams": [
                      "a"
                    ],
                    "typeExp": {
                      "Reference": [
                        "morphir/SDK:list#list",
                        "a"
                      ]
                    }
                  }
                }
              },
              "values": {
                "map": {
                  "inputs": {
                    "f": {
                      "Function": {
                        "parameterType": "a",
                        "returnType": "b"
                      }
                    },
                    "list": {
                      "Reference": [
                        "morphir/SDK:list#list",
                        "a"
                      ]
                    }
                  },
                  "output": {
                    "Reference": [
                      "morphir/SDK:list#list",
                      "b"
                    ]
                  }
                }
              }
            }
          }
        }
      },
      "def": {
        "modules": {
          "u-s/f-r-2052-a/data-tables": {
            "access": "Public",
            "value": {
              "types": {
                "data-tables": {
                  "access": "Public",
                  "TypeAliasDefinition": {
                    "typeParams": [],
                    "typeExp": {
                      "Record": {
                        "fields": {
                          "inflows": "regulation:u-s/f-r-2052-a/data-tables#inflows",
                          "outflows": "regulation:u-s/f-r-2052-a/data-tables#outflows",
                          "supplemental": "regulation:u-s/f-r-2052-a/data-tables#supplemental"
                        }
                      }
                    }
                  }
                },
                "inflows": {
                  "access": "Public",
                  "TypeAliasDefinition": {
                    "typeParams": [],
                    "typeExp": {
                      "Record": {
                        "fields": {
                          "assets": {
                            "Reference": [
                              "morphir/SDK:list#list",
                              "regulation:u-s/f-r-2052-a/data-tables/inflows#assets"
                            ]
                          }
                        }
                      }
                    }
                  }
                }
              },
              "values": {
                "calculate-total": {
                  "access": "Public",
                  "ExpressionBody": {
                    "inputTypes": {
                      "tables": "regulation:u-s/f-r-2052-a/data-tables#data-tables"
                    },
                    "outputType": "morphir/SDK:basics#float",
                    "body": {
                      "Literal": {
                        "attributes": {},
                        "literal": {
                          "FloatLiteral": 0
                        }
                      }
                    }
                  }
                }
              },
              "doc": "Data tables module for regulatory reporting"
            }
          }
        }
      }
    }
  }
}
```

> **Note:** This example demonstrates the V4 wrapper object format throughout:
> - Distribution uses `{ "Library": { ... } }` wrapper
> - Modules are objects keyed by module path: `{ "module/path": {...} }`
> - Types and values within modules are objects keyed by name: `{ "type-name": {...} }`
> - Record fields are objects keyed by field name: `{ "field-name": type }`
> - Dependencies are objects keyed by package name: `{ "package/name": spec }`

### Module Definition

Enhanced with optional documentation and object-based structure:

```yaml
ModuleDefinition:
  type: object
  required: ["types", "values"]
  properties:
    types:
      type: object
      additionalProperties:
        allOf:
          - $ref: "#/definitions/AccessControlled"
          - properties:
              value:
                oneOf:
                  - type: object
                    required: ["doc", "value"]
                    properties:
                      doc: { type: string }
                      value: { $ref: "#/definitions/TypeDefinition" }
                  - $ref: "#/definitions/TypeDefinition"
      description: "Dictionary mapping type names to access-controlled type definitions"
    values:
      type: object
      additionalProperties:
        allOf:
          - $ref: "#/definitions/AccessControlled"
          - properties:
              value:
                oneOf:
                  - type: object
                    required: ["doc", "value"]
                    properties:
                      doc: { type: string }
                      value: { $ref: "#/definitions/ValueDefinition" }
                  - $ref: "#/definitions/ValueDefinition"
      description: "Dictionary mapping value names to access-controlled value definitions"
    doc: { type: string }
```

> **Note:** V4 uses object/dict format for modules, types, and values (keyed by name/path) instead of arrays. This provides O(1) lookup and maintains canonical key ordering.

## Type System

Same as V3, but with `TypeAttributes`:

### Type Expressions

- **Variable**: a bare Name string, `"a"`
- **Reference** (no arguments): a bare FQName string, `"morphir/SDK:basics#int"`
- **Reference** (with arguments): `{"Reference": [FQName, Type, ...]}`; the expanded `{"Reference": {"fqname": FQName, "args": [Type]}}` is accepted
- **Tuple**: `{"Tuple": [Type, ...]}`; a bare array `[Type, ...]` is also a tuple, and `{"Tuple": {"elements": [...]}}` is accepted
- **Record**: `{"Record": {"fields": {"field-name": Type}}}`
- **ExtensibleRecord**: `{"ExtensibleRecord": {"variable": Name, "fields": {"field-name": Type}}}`
- **Function**: `{"Function": {"parameterType": Type, "returnType": Type}}`
- **Unit**: `{"Unit": {}}`
- Every node also has an expanded spelling whose payload starts with `attributes` (decision 0005).

### Type Specifications

- **TypeAliasSpecification**
- **OpaqueTypeSpecification**
- **CustomTypeSpecification**
- **DerivedTypeSpecification** (for derived types with conversions)

## Value System

Enhanced with new expressions and `ValueAttributes`:

### Value Expressions

**Core expressions** (from V3):
- **Literal**: Constant values
- **Variable**: Reference to a variable in scope
- **Reference**: Reference to a defined value
- **Apply**: Function application
- **Lambda**: Anonymous function
- **LetDefinition**: Let binding
- **IfThenElse**: Conditional expression
- **PatternMatch**: Pattern matching
- **Field**: Record field access
- **Record**: Record literal
- **Tuple**: Tuple literal

**New in V4:**
- **Constructor**: Direct constructor reference (first-class)
- **List**: Native list literal
- **FieldFunction**: Field accessor function
- **LetRecursion**: Mutually recursive definitions
- **Destructure**: Pattern destructuring
- **UpdateRecord**: Record update syntax
- **Unit**: Explicit unit value

### Patterns

Same as V3 with `ValueAttributes`:

- **WildcardPattern**: Matches anything
- **AsPattern**: Binds a name
- **TuplePattern**: Tuple destructuring
- **ConstructorPattern**: Constructor matching
- **EmptyListPattern**: Empty list match
- **HeadTailPattern**: List cons pattern
- **LiteralPattern**: Literal matching
- **UnitPattern**: Unit pattern

### Literals

The six V3 literals plus one:

- **BoolLiteral**
- **CharLiteral**
- **StringLiteral**
- **IntegerLiteral**
- **FloatLiteral**
- **DecimalLiteral**
- **DocumentLiteral** (decision 0013)

## Migration

### From V3 to V4

1. Convert generic attributes to structured TypeAttributes/ValueAttributes
2. Optionally convert to string formats for Names/Paths/FQNames
3. Add documentation where appropriate
4. Use new value expressions where applicable

See [What's New in V4](./whats-new/) and the [Migration Guide](../migration-guide/) for details.

### From V4 to V3

Possible but **lossy**:

- Type constraints are lost
- Inferred types are lost
- Inline documentation is lost
- New value expressions must be transformed
- A `DocumentLiteral` cannot be downgraded; the writer refuses with `unsupported_v4_downgrade`

See [Migration Guide - V4 → V3](../migration-guide/#v4--v3) for details.

## Recommended Format

Version 4 is **recommended for new Morphir projects** due to:

- **Better tooling support**: Source locations and type information
- **More expressive**: New value expressions enable richer language features
- **Smaller files**: String formats reduce file size
- **Self-documenting**: Inline documentation support
- **Future-proof**: Active development and evolution

## Full Schema

See [morphir-ir-v4.yaml](/schemas/morphir-ir-v4.yaml) for the complete schema definition.

## References

- [What's New in Version 4](./whats-new/)
- [Migration Guide](../migration-guide/)
- [Morphir IR Specification](../../morphir-ir-specification/)
- [Schema Version 3](../v3/)
- [Schema Version 2](../v2/)
- [Schema Version 1](../v1/)
