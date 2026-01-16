---
title: Types Module
sidebar_label: Types
sidebar_position: 3
---

# Types Module

This module defines the type system for Morphir IR, including type expressions, specifications, and definitions.

## Access Control

```gleam
// === access.gleam ===

/// Visibility level for definitions
pub type Access {
  Public
  Private
}

/// Wraps any definition with visibility control
pub type AccessControlled(a) {
  AccessControlled(access: Access, value: a)
}
```

## Type Expressions

Type expressions describe the shape of data.

```gleam
// === types.gleam ===

// Note: TypeVariable is defined in naming.gleam as an opaque newtype wrapper

// ============================================================
// TYPE EXPRESSIONS (What shape is this data?)
// ============================================================

/// Type expressions
pub type Type(attributes) {
  /// Type variable: `a`, `comparable`
  Variable(attributes: attributes, name: TypeVariable)

  /// Reference to named type: `String`, `MyModule.User`
  Reference(
    attributes: attributes,
    fqname: FQName,
    args: List(Type(attributes)),
  )

  /// Tuple: `(Int, String)`
  Tuple(attributes: attributes, elements: List(Type(attributes)))

  /// Record: `{ name: String, age: Int }`
  Record(attributes: attributes, fields: List(Field(attributes)))

  /// Extensible record: `{ a | name: String }`
  ExtensibleRecord(
    attributes: attributes,
    variable: TypeVariable,
    fields: List(Field(attributes)),
  )

  /// Function: `Int -> String`
  Function(
    attributes: attributes,
    arg: Type(attributes),
    result: Type(attributes),
  )

  /// Unit type: `()`
  Unit(attributes: attributes)
}

/// Record field
pub type Field(attributes) {
  Field(name: Name, field_type: Type(attributes))
}

/// Constructor for custom types
pub type Constructor(attributes) {
  Constructor(name: Name, args: List(#(Name, Type(attributes))))
}

pub type Constructors(attributes) =
  List(Constructor(attributes))
```

## Type Specifications

Type specifications define the public contract exposed to consumers - they contain no implementation details.

```gleam
// ============================================================
// TYPE SPECIFICATIONS (Public Interface)
// ============================================================

/// Details for derived type conversion
pub type DerivedTypeSpecificationDetails(attributes) {
  DerivedTypeSpecificationDetails(
    base_type: Type(attributes),
    from_base_type: FQName,  // Constructor: BaseType -> DerivedType
    to_base_type: FQName,    // Accessor: DerivedType -> BaseType
  )
}

/// Type specification - the public contract exposed to consumers
pub type TypeSpecification(attributes) {
  /// Type alias visible to consumers
  TypeAliasSpecification(
    params: List(TypeVariable),
    body: Type(attributes),
  )

  /// Opaque - no structure, no conversion (not serializable via Morphir)
  OpaqueTypeSpecification(params: List(TypeVariable))

  /// Custom type with public constructors
  CustomTypeSpecification(
    params: List(TypeVariable),
    constructors: Constructors(attributes),
  )

  /// Derived - opaque structure BUT with conversion functions (serializable)
  DerivedTypeSpecification(
    params: List(TypeVariable),
    details: DerivedTypeSpecificationDetails(attributes),
  )
}
```

## Type Definitions

Type definitions contain the full implementation owned by the module.

```gleam
// ============================================================
// TYPE DEFINITIONS (Implementation)
// ============================================================

/// Reason a type definition is incomplete
pub type Incompleteness {
  /// Reference to something that was deleted/renamed
  Hole(reason: HoleReason)
  /// Author-marked work-in-progress
  Draft(notes: Option(String))
}

/// Specific reason for a Hole
pub type HoleReason {
  UnresolvedReference(target: FQName)
  DeletedDuringRefactor(tx_id: String)
  TypeMismatch(expected: String, found: String)
}

/// Type definition - the full implementation owned by the module
pub type TypeDefinition(attributes) {
  /// Sum type implementation
  CustomTypeDefinition(
    params: List(TypeVariable),
    access: AccessControlled(Constructors(attributes)),
  )

  /// Type alias implementation
  TypeAliasDefinition(params: List(TypeVariable), body: Type(attributes))

  /// Incomplete type (v4: Hole or Draft)
  IncompleteTypeDefinition(
    params: List(TypeVariable),
    incompleteness: Incompleteness,
    partial_body: Option(Type(attributes)),
  )
}
```

## JSON Serialization

### Type and Value Shorthand

For compact, readable IRs, type expressions support shorthand forms when attributes are empty/null.

#### Shorthand Rules

| Form | Interpretation | Disambiguation |
|------|----------------|----------------|
| `"morphir/sdk:basics#int"` | Type.Reference (no args) | Contains `:` and `#` → FQName |
| `"a"` | Type.Variable | No `:` or `#` → variable name |
| `["morphir/sdk:list#list", ...]` | Type.Reference with args | Array → parameterized type |

#### Disambiguation Logic

```
if string contains ":" and "#":
    → FQName reference (Type.Reference or Value.Reference)
else if string (no special chars):
    → Variable name (Type.Variable)
else if array:
    → Parameterized type: first element is FQName, rest are type args
else if object:
    → Canonical wrapper object format
```

#### Shorthand Examples

```json
// Variable
"a"                                    // shorthand
{ "Variable": { "name": "a" } }        // canonical

// Simple reference (no type args)
"morphir/sdk:basics#int"                           // shorthand
{ "Reference": { "fqname": "morphir/sdk:basics#int" } }  // canonical

// Parameterized type: List Int
["morphir/sdk:list#list", "morphir/sdk:basics#int"]      // shorthand
{
  "Reference": {
    "fqname": "morphir/sdk:list#list",
    "args": [{ "Reference": { "fqname": "morphir/sdk:basics#int" } }]
  }
}  // canonical

// Parameterized type: Dict String Int
["morphir/sdk:dict#dict", "morphir/sdk:string#string", "morphir/sdk:basics#int"]

// Nested: List (Maybe Int)
["morphir/sdk:list#list", ["morphir/sdk:maybe#maybe", "morphir/sdk:basics#int"]]

// Mixed: Result String a (variable as type arg)
["morphir/sdk:result#result", "morphir/sdk:string#string", "a"]
```

#### Encoding/Decoding Rules

**Encoding (output):**
- Use shorthand when attributes are empty/null
- Prefer shorthand for readability
- Fall back to canonical for types with attributes

**Decoding (input - permissive):**
- Accept both shorthand and canonical forms
- String → check for FQName pattern or variable
- Array → parameterized type
- Object → canonical form

## Type Expression Examples

Examples show both shorthand and canonical forms.

### Variable

```json
"a"                                    // shorthand
{ "Variable": { "name": "a" } }        // canonical
```

### Reference (no type arguments)

```json
"morphir/sdk:basics#int"                           // shorthand
{ "Reference": { "fqname": "morphir/sdk:basics#int" } }  // canonical
```

### Reference (with type arguments)

```json
// List Int
["morphir/sdk:list#list", "morphir/sdk:basics#int"]   // shorthand

// canonical
{
  "Reference": {
    "fqname": "morphir/sdk:list#list",
    "args": [
      { "Reference": { "fqname": "morphir/sdk:basics#int" } }
    ]
  }
}
```

### Tuple

```json
// shorthand
{
  "Tuple": {
    "elements": ["morphir/sdk:basics#int", "morphir/sdk:string#string"]
  }
}

// canonical
{
  "Tuple": {
    "elements": [
      { "Reference": { "fqname": "morphir/sdk:basics#int" } },
      { "Reference": { "fqname": "morphir/sdk:string#string" } }
    ]
  }
}
```

### Record

Field names as object keys, values are the field types:

```json
// shorthand
{
  "Record": {
    "fields": {
      "user-name": "morphir/sdk:string#string",
      "age": "morphir/sdk:basics#int"
    }
  }
}

// canonical
{
  "Record": {
    "fields": {
      "user-name": { "Reference": { "fqname": "morphir/sdk:string#string" } },
      "age": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
    }
  }
}
```

### ExtensibleRecord

```json
// shorthand
{
  "ExtensibleRecord": {
    "variable": "a",
    "fields": {
      "name": "morphir/sdk:string#string"
    }
  }
}

// canonical
{
  "ExtensibleRecord": {
    "variable": "a",
    "fields": {
      "name": { "Reference": { "fqname": "morphir/sdk:string#string" } }
    }
  }
}
```

:::note
Decoding also accepts the legacy array format for backwards compatibility:
```json
{ "Record": { "fields": [{ "name": "age", "fieldType": { "Reference": { "fqname": "..." } } }] } }
```
:::

### Function

```json
// shorthand
{ "Function": { "arg": "morphir/sdk:basics#int", "result": "morphir/sdk:string#string" } }

// canonical
{
  "Function": {
    "arg": { "Reference": { "fqname": "morphir/sdk:basics#int" } },
    "result": { "Reference": { "fqname": "morphir/sdk:string#string" } }
  }
}
```

### Unit

```json
{ "Unit": {} }
```

## Type Definition Examples

### CustomTypeDefinition

`type Maybe a = Just a | Nothing`

```json
{
  "CustomTypeDefinition": {
    "params": ["a"],
    "access": {
      "access": "Public",
      "value": [
        { "name": "just", "args": [["value", { "Variable": { "name": "a" } }]] },
        { "name": "nothing" }
      ]
    }
  }
}
```

### TypeAliasDefinition

`type alias UserId = String`

```json
{
  "TypeAliasDefinition": {
    "body": { "Reference": { "fqname": "morphir/sdk:string#string" } }
  }
}
```

### IncompleteTypeDefinition (v4)

```json
{
  "IncompleteTypeDefinition": {
    "params": ["a"],
    "incompleteness": {
      "Hole": {
        "reason": { "UnresolvedReference": { "target": "my-org/project:domain#missing-type" } }
      }
    }
  }
}
```

## Type Specification Examples

### DerivedTypeSpecification

`LocalDate` backed by `String` with conversion functions:

```json
{
  "DerivedTypeSpecification": {
    "details": {
      "baseType": { "Reference": { "fqname": "morphir/sdk:string#string" } },
      "fromBaseType": "my-org/sdk:local-date#from-string",
      "toBaseType": "my-org/sdk:local-date#to-string"
    }
  }
}
```

## Backwards Compatible Decoding

The decoder accepts multiple formats for compatibility with v1/v2/v3:

| Format | Example | Source |
|--------|---------|--------|
| Wrapper object | `{ "Variable": { "name": "a" } }` | v4 canonical |
| Tagged array (capitalized) | `["Variable", {}, ["a"]]` | v2/v3 |
| Tagged array (lowercase) | `["variable", {}, ["a"]]` | v1 |

```gleam
/// Decode a Type from JSON, accepting multiple formats
pub fn decode_type(json: Dynamic) -> Result(Type, DecodeError) {
  // Try wrapper object first (v4 canonical)
  case decode_wrapper_object(json) {
    Ok(t) -> Ok(t)
    Error(_) -> {
      // Fall back to tagged array (v1/v2/v3 compat)
      decode_tagged_array(json)
    }
  }
}
```
