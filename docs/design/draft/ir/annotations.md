---
title: Annotations
sidebar_label: Annotations
sidebar_position: 2.6
status: draft
---

# Annotations

Annotations provide a way to attach structured metadata to IR specification types. Unlike attributes, which are used for implementation-level metadata (like source locations or inferred types), annotations are used for higher-level semantic labeling of signatures, similar to annotations in Java or Scala.

## Annotation Structure

An annotation consists of a fully qualified name (the annotation type) and a set of arguments. Arguments can be positional (a list of values) or named (a mapping from names to values).

```gleam
pub type Annotation {
  Annotation(
    name: FQName,
    arguments: List(AnnotationArgument)
  )
}

pub type AnnotationArgument {
  /// Positional argument
  PositionalArgument(value: Value)
  /// Named argument: @MyAnno(name = "value")
  NamedArgument(name: Name, value: Value)
}
```

## JSON Serialization

Annotations support a canonical object format and a compact shorthand string format.

### Shorthand Format (Compact)

For simple annotations, a string format is supported: `fqname:value`.

| Case | Format | Note |
|------|--------|------|
| Marker (0 args) | `"package:module#name"` | Just the FQName string |
| Single Value (1 arg) | `"package:module#name:value"` | FQName followed by colon and value |

**Examples:**
- `"morphir/sdk:annotations#stable"`
- `"my-org/sdk:annotations#deprecated:Use new-function instead"`
- `"my-org/sdk:annotations#version:1.0.0"`

### Object Format (Canonical)
```json
{
  "name": "my-org/sdk:annotations#deprecated",
  "arguments": [
    { "Literal": { "StringLiteral": "Use new-function instead" } }
  ]
}
```

### Named Arguments
```json
{
  "name": "my-org/sdk:annotations#info",
  "arguments": [
    { "name": "author", "value": { "Literal": { "StringLiteral": "Damian" } } },
    { "name": "version", "value": { "Literal": { "StringLiteral": "1.0.0" } } }
  ]
}
```

### Mixed Arguments
```json
{
  "name": "my-org/sdk:annotations#task",
  "arguments": [
    { "Literal": { "StringLiteral": "Refactor this" } },
    { "name": "priority", "value": { "Literal": { "IntegerLiteral": 1 } } }
  ]
}
```

## Usage Examples and Use Cases

These examples show how common Scala/Java annotations translate into the Morphir IR v4 canonical representation.

### 1. Stability and Life-cycle
Used to communicate the stability of an API or its deprecation status.

**Source (Scala):**
```scala
@deprecated("Use newMethod instead", "2.0.0")
@stable
def oldMethod(x: Int): Int = ???
```

**Transformed IR (JSON):**
```json
{
  "annotations": [
    {
      "name": "morphir/sdk:annotations#deprecated",
      "arguments": [
        { "Literal": { "StringLiteral": "Use newMethod instead" } },
        { "Literal": { "StringLiteral": "2.0.0" } }
      ]
    },
    "morphir/sdk:annotations#stable"
  ]
}
```

### 2. Physical Schema Mapping
Used to provide hints for code generation or database mapping (e.g. JSON field names).

**Source (Scala):**
```scala
@jsonName("user_id")
case class User(id: String)
```

**Transformed IR (JSON):**
```json
{
  "CustomTypeSpecification": {
    "annotations": [
      "my-org/sdk:annotations#json-name:user_id"
    ],
    "typeParams": [],
    "constructors": { ... }
  }
}
```

### 3. Custom Metadata and Tooling Hints
Used for domain-specific labeling or to provide hints to downstream tools (e.g. security audits).

**Source (Scala):**
```scala
@security(level = SecurityLevel.High, roles = Array("admin", "auditor"))
def transferFunds(amount: Double): Unit = ???
```

**Transformed IR (JSON):**
```json
{
  "annotations": [
    {
      "name": "my-org/security:annotations#security",
      "arguments": [
        { 
          "name": "level", 
          "value": { "Reference": "my-org/security:types#security-level.high" } 
        },
        { 
          "name": "roles", 
          "value": { 
            "List": [
              { "Literal": { "StringLiteral": "admin" } },
              { "Literal": { "StringLiteral": "auditor" } }
            ] 
          } 
        }
      ]
    }
  ]
}
```

## Specification Integration

Annotations are only supported on **Specification** types in Morphir IR v4.

### Module Specification
```json
{
  "ModuleSpecification": {
    "annotations": [
      { "name": "my-org/sdk:annotations#stable", "arguments": [] }
    ],
    "types": { ... },
    "values": { ... }
  }
}
```

### Type Specification
```json
{
  "TypeAliasSpecification": {
    "annotations": [
      { "name": "my-org/sdk:annotations#json-name", "arguments": [{ "Literal": { "StringLiteral": "user_id" } }] }
    ],
    "typeParams": [],
    "typeExp": "morphir/sdk:string#string"
  }
}
```

### Value Specification
```json
{
  "ValueSpecification": {
    "annotations": [
      { "name": "my-org/sdk:annotations#pure", "arguments": [] }
    ],
    "inputs": { ... },
    "output": { ... }
  }
}
```
