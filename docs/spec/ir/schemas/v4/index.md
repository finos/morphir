---
title: "Schema Version 4"
linkTitle: "Version 4"
weight: 1
description: "Morphir IR JSON Schema for format version 4 (Draft)"
---

# Morphir IR Schema - Version 4 (Draft)

Format version 4 is the next generation of the Morphir IR format. It replaces generic attributes with explicit `TypeAttributes` and `ValueAttributes` structures, introduces canonical string formats, and adds new value expressions for enhanced expressiveness.

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
Array:  ["value", "in", "u", "s", "d"]
String: "value-in-u-s-d"
```

**Path:**
```
Array:  [["morphir"], ["s", "d", "k"]]
String: "morphir/s-d-k"
```

**FQName:**
```
Array:  [[["morphir"], ["s","d","k"]], [["list"]], ["map"]]
String: "morphir/s-d-k:list#map"
```

**Benefits:**
- 30% smaller IR files
- More readable references
- Faster parsing
- Better error messages

### Embedded Documentation

V4 supports inline documentation for types and values:

```json
{
  "types": [
    [
      ["user", "id"],
      {
        "access": "Public",
        "value": {
          "doc": "Unique identifier for a user in the system",
          "value": ["TypeAliasSpecification", [], [...]]
        }
      }
    ]
  ]
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

-- V4 IR
["Apply", {},
  ["Apply", {},
    ["Reference", {}, "morphir/s-d-k:list#map"],
    ["Constructor", {}, "morphir/s-d-k:maybe#Just"]],
  ["List", {}, [...]]]
```

### Module.json Support

V4 officially supports standalone `module.json` files:

```
my-package/
  morphir-ir.json
  modules/
    MyModule.module.json
    Sub/
      Module.module.json
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

A **Name** represents a human-readable identifier.

- **Array format**: `["value", "in", "u", "s", "d"]`
- **String format**: `"value-in-u-s-d"`
- **Pattern**: `^[a-z0-9]+(-[a-z0-9]+|-(\\([a-z]+\\)))*$`

#### Path

A **Path** represents a hierarchical location.

- **Array format**: `[["morphir"], ["s", "d", "k"]]`
- **String format**: `"morphir/s-d-k"`
- **Pattern**: `^[a-z0-9-()]+(/[a-z0-9-()]+)*$`

#### FQName

A **Fully-Qualified Name** provides globally unique identifiers.

- **Array format**: `[[pkg], [mod], [name]]`
- **String format**: `"pkg:mod#name"`
- **Pattern**: `^[a-z0-9-()/]+:[a-z0-9-()/]+#[a-z0-9-()]+$`

### Access Control

Same as V3:

```yaml
AccessControlled:
  type: object
  required: ["access", "value"]
  properties:
    access:
      enum: ["Public", "Private"]
    value: {}
```

## Distribution and Package Structure

### Distribution

Same structure as V3, but with V4 attributes:

```yaml
distribution:
  type: array
  minItems: 4
  maxItems: 4
  items:
    - const: "Library"
    - $ref: "#/definitions/PackageName"
    - $ref: "#/definitions/Dependencies"
    - $ref: "#/definitions/PackageDefinition"
```

### Module Definition

Enhanced with optional documentation:

```yaml
ModuleDefinition:
  type: object
  required: ["types", "values"]
  properties:
    types:
      type: array
      items:
        - $ref: "#/definitions/Name"
        - allOf:
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
    values:
      # Similar structure with doc support
    doc: { type: string }
```

## Type System

Same as V3, but with `TypeAttributes`:

### Type Expressions

- **Variable**: `["Variable", TypeAttributes, name]`
- **Reference**: `["Reference", TypeAttributes, fqName, typeArgs]`
- **Tuple**: `["Tuple", TypeAttributes, elementTypes]`
- **Record**: `["Record", TypeAttributes, fields]`
- **ExtensibleRecord**: `["ExtensibleRecord", TypeAttributes, variable, fields]`
- **Function**: `["Function", TypeAttributes, argType, returnType]`
- **Unit**: `["Unit", TypeAttributes]`

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

Same as V3:

- **BoolLiteral**
- **CharLiteral**
- **StringLiteral**
- **WholeNumberLiteral**
- **FloatLiteral**
- **DecimalLiteral**

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

See [Migration Guide - V4 → V3](../migration-guide/#v4--v3) for details.

## Recommended Format

Version 4 is **recommended for new Morphir projects** due to:

- **Better tooling support**: Source locations and type information
- **More expressive**: New value expressions enable richer language features
- **Smaller files**: String formats reduce file size
- **Self-documenting**: Inline documentation support
- **Future-proof**: Active development and evolution

## Full Schema

See [morphir-ir-v4.yaml](./morphir-ir-v4.yaml) for the complete schema definition.

## References

- [What's New in Version 4](./whats-new/)
- [Migration Guide](../migration-guide/)
- [Morphir IR Specification](../../morphir-ir-specification/)
- [Schema Version 3](../v3/)
- [Schema Version 2](../v2/)
- [Schema Version 1](../v1/)
