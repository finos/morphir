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

### Access JSON Formats

V4 follows a **permissive input, canonical output** policy. Decoders accept multiple formats; encoders output canonical form.

| Format | Example | Notes |
|--------|---------|-------|
| Canonical | `"Public"`, `"Private"` | Preferred output |
| Lowercase | `"public"`, `"private"` | Accepted |
| Abbreviation | `"pub"` | Accepted (means Public) |

### AccessControlled JSON Formats

| Format | Example | Notes |
|--------|---------|-------|
| **Canonical** | `{ "Public": {...} }` | Access as key, value as value |
| Lowercase key | `{ "public": {...} }`, `{ "private": {...} }` | Accepted |
| Abbreviation key | `{ "pub": {...} }` | Accepted (means Public) |
| Legacy | `{ "access": "Public", "value": {...} }` | V3 compatibility |

**Examples:**
```json
// Canonical (encoders should output this)
{ "Public": { "TypeAliasDefinition": { "body": "morphir/SDK:string#string" } } }
{ "Private": { "CustomTypeDefinition": { "params": [], "constructors": {} } } }

// Accepted alternatives
{ "pub": { "TypeAliasDefinition": { "body": "morphir/SDK:string#string" } } }
{ "public": { "TypeAliasDefinition": { "body": "morphir/SDK:string#string" } } }
{ "access": "Public", "value": { "TypeAliasDefinition": { "body": "morphir/SDK:string#string" } } }
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
    annotations: List(Annotation),
    params: List(TypeVariable),
    body: Type(attributes),
  )

  /// Opaque - no structure, no conversion (not serializable via Morphir)
  OpaqueTypeSpecification(
    annotations: List(Annotation),
    params: List(TypeVariable),
  )

  /// Custom type with public constructors
  CustomTypeSpecification(
    annotations: List(Annotation),
    params: List(TypeVariable),
    constructors: Constructors(attributes),
  )

  /// Derived - opaque structure BUT with conversion functions (serializable)
  DerivedTypeSpecification(
    annotations: List(Annotation),
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
| `"morphir/SDK:basics#int"` | Type.Reference (no args) | Contains `:` and `#` → FQName |
| `"a"` | Type.Variable | No `:` or `#` → variable name |
| `["morphir/SDK:list#list", ...]` | Type.Reference with args | Array → parameterized type |

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
"morphir/SDK:basics#int"                           // shorthand
{ "Reference": { "fqname": "morphir/SDK:basics#int" } }  // canonical

// Parameterized type: List Int
["morphir/SDK:list#list", "morphir/SDK:basics#int"]      // shorthand
{
  "Reference": {
    "fqname": "morphir/SDK:list#list",
    "args": [{ "Reference": { "fqname": "morphir/SDK:basics#int" } }]
  }
}  // canonical

// Parameterized type: Dict String Int
["morphir/SDK:dict#dict", "morphir/SDK:string#string", "morphir/SDK:basics#int"]

// Nested: List (Maybe Int)
["morphir/SDK:list#list", ["morphir/SDK:maybe#maybe", "morphir/SDK:basics#int"]]

// Mixed: Result String a (variable as type arg)
["morphir/SDK:result#result", "morphir/SDK:string#string", "a"]
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

### Reference (ReferenceType)

V4 follows a **permissive input, canonical output** policy for Reference types.

#### No Type Arguments

| Format | Example | Notes |
|--------|---------|-------|
| **Canonical** | `"morphir/SDK:basics#int"` | Bare FQName string |
| Wrapper with FQName | `{ "Reference": "morphir/SDK:basics#int" }` | Accepted |
| Wrapper with object | `{ "Reference": { "fqname": "morphir/SDK:basics#int" } }` | Expanded form |

```json
// Canonical (encoders should output this)
"morphir/SDK:basics#int"

// Accepted alternatives
{ "Reference": "morphir/SDK:basics#int" }
{ "Reference": { "fqname": "morphir/SDK:basics#int" } }
```

#### With Type Arguments

| Format | Example | Notes |
|--------|---------|-------|
| **Canonical** | `{ "Reference": ["fqname", type1, ...] }` | Wrapper with array |
| Wrapper with object | `{ "Reference": { "fqname": "...", "args": [...] } }` | Expanded form |

:::warning
Bare arrays (e.g., `["morphir/SDK:list#list", "a"]`) are **NOT** allowed for Reference at the top level—this would conflict with TupleType which uses bare arrays.
:::

```json
// Canonical (encoders should output this for types with args)
{ "Reference": ["morphir/SDK:list#list", "morphir/SDK:basics#int"] }

// Expanded form (accepted)
{
  "Reference": {
    "fqname": "morphir/SDK:list#list",
    "args": ["morphir/SDK:basics#int"]
  }
}

// Dict String Int
{ "Reference": ["morphir/SDK:dict#dict", "morphir/SDK:string#string", "morphir/SDK:basics#int"] }
```

### Tuple (TupleType)

V4 follows a **permissive input, canonical output** policy for Tuple types.

| Format | Example | Notes |
|--------|---------|-------|
| Bare array | `[type1, type2, ...]` | Compact, unambiguous (Reference doesn't use bare arrays) |
| **Canonical** | `{ "Tuple": [type1, type2, ...] }` | Wrapper with array |
| Expanded | `{ "Tuple": { "elements": [type1, type2, ...] } }` | Wrapper with object |

:::note
Bare arrays are unambiguous for TupleType because ReferenceType does **not** allow bare arrays (to avoid this exact conflict).
:::

```json
// Bare array (most compact, accepted)
["morphir/SDK:basics#int", "morphir/SDK:string#string"]

// Canonical (encoders should output this)
{ "Tuple": ["morphir/SDK:basics#int", "morphir/SDK:string#string"] }

// Expanded form (accepted)
{
  "Tuple": {
    "elements": ["morphir/SDK:basics#int", "morphir/SDK:string#string"]
  }
}

// With nested types
{ "Tuple": ["a", "b", ["morphir/SDK:list#list", "c"]] }
```

### Record

Field names as object keys, values are the field types:

```json
// shorthand
{
  "Record": {
    "fields": {
      "user-name": "morphir/SDK:string#string",
      "age": "morphir/SDK:basics#int"
    }
  }
}

// canonical
{
  "Record": {
    "fields": {
      "user-name": { "Reference": { "fqname": "morphir/SDK:string#string" } },
      "age": { "Reference": { "fqname": "morphir/SDK:basics#int" } }
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
      "name": "morphir/SDK:string#string"
    }
  }
}

// canonical
{
  "ExtensibleRecord": {
    "variable": "a",
    "fields": {
      "name": { "Reference": { "fqname": "morphir/SDK:string#string" } }
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
{
  "Function": {
    "parameterType": "morphir/SDK:basics#int",
    "returnType": "morphir/SDK:string#string"
  }
}

// canonical
{
  "Function": {
    "parameterType": { "Reference": { "fqname": "morphir/SDK:basics#int" } },
    "returnType": { "Reference": { "fqname": "morphir/SDK:string#string" } }
  }
}
```

:::note
`parameterType` and `returnType` are the canonical member names (decision 0007).
The spellings `arg`/`result` and `argumentType` are legacy. A reader accepts them
for one release, reports a warning, and normalizes them to the canonical names.
:::

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
    "body": { "Reference": { "fqname": "morphir/SDK:string#string" } }
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
      "baseType": { "Reference": { "fqname": "morphir/SDK:string#string" } },
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
