---
title: "Type System"
description: "Specification for the Morphir Type System in IR v4"
---

# Type System

The Morphir type system is based on functional programming principles, similar to languages like Elm, Haskell, or ML.

## Type Attributes

In IR v4, types are no longer generic over their attributes. Instead, every type node contains a specific `TypeAttributes` structure.

**TypeAttributes** contains:
- **source**: Optional source code location (start/end line/column)
- **constraints**: Optional type constraints
- **extensions**: A dictionary of extension data

## Type Expressions

A **Type** is a recursive tree structure representing type expressions.

### Variable

Represents a type variable.

- **Structure**: `Variable attributes name`
- **Components**:
  - attributes: `TypeAttributes`
  - name: The variable name (`Name`)
- **Example**: The `a` in `List a`
- **JSON (compact)**: `"a"` — bare name string (distinguishable from FQName by lack of `:` and `#`)
- **JSON (expanded)**: `{"Variable": {"name": "a"}}` — object wrapper with name key

### Reference

A reference to another type or type alias.

- **Structure**: `Reference attributes fqName args`
- **Components**:
  - attributes: `TypeAttributes`
  - fqName: Fully-qualified name of the referenced type (`FQName`)
  - args: List of type arguments (`List Type`)
- **Examples**:
  - `String` → FQName: `morphir/SDK:string#string`
  - `List Int` → FQName: `morphir/SDK:list#list` with type argument `morphir/SDK:basics#int`
  - `Dict String Int` → FQName: `morphir/SDK:dict#dict` with type arguments
- **JSON (compact, no type args)**: `"morphir/SDK:string#string"` — bare FQName string
- **JSON (compact, with type args)**: `{"Reference": ["morphir/SDK:list#list", "a"]}` — array with FQName first, followed by type args
- **JSON (expanded)**: `{"Reference": {"fqname": "morphir/SDK:list#list", "args": [...]}}` — object with fqname and args keys
- **Legacy format**: `[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]]` (package, module, local name arrays)

### Tuple

A composition of multiple types in a fixed order.

- **Structure**: `Tuple attributes elements`
- **Components**:
  - attributes: `TypeAttributes`
  - elements: Element types in order (`List Type`)
- **JSON (canonical)**: `{"Tuple": ["morphir/SDK:int#int", "morphir/SDK:string#string"]}`
- **JSON (compact)**: `["morphir/SDK:int#int", "morphir/SDK:string#string"]` — a bare array in type position is always a tuple
- **JSON (expanded)**: `{"Tuple": {"elements": ["morphir/SDK:int#int", "morphir/SDK:string#string"]}}`

### Record

A composition of named fields with their types.

- **Structure**: `Record attributes fields`
- **Components**:
  - attributes: `TypeAttributes`
  - fields: Dictionary of field names to types
- **JSON (canonical)**: `{"Record": {"fields": {"field-name": "morphir/SDK:string#string", "age": "morphir/SDK:basics#int"}}}`
- **JSON (expanded)**: `{"Record": {"attributes": {...}, "fields": {...}}}`
- Fields live under `fields` so `attributes` can sit beside them (decision 0004). The field map directly under `Record` is accepted for one release and reported as `legacy_spelling` (decision 0006).

### ExtensibleRecord

A record type that can be extended with additional fields.

- **Structure**: `ExtensibleRecord attributes variable fields`
- **Components**:
  - attributes: `TypeAttributes`
  - variable: Type variable representing the extension (`Name`)
  - fields: Known fields (dictionary of names to types)
- **JSON**: `{"ExtensibleRecord": {"variable": "a", "fields": {"name": "morphir/SDK:string#string"}}}`

### Function

Represents a function type.

- **Structure**: `Function attributes parameterType returnType`
- **Components**:
  - attributes: `TypeAttributes`
  - parameterType: Parameter type (`Type`)
  - returnType: Return type (`Type`)
- **JSON**: `{"Function": {"parameterType": "morphir/SDK:int#int", "returnType": "morphir/SDK:string#string"}}`
- `argumentType`, and the Rust encoder's `arg`/`result`, are accepted for one release (decisions 0006, 0007).

### Unit

The type with exactly one value.

- **Structure**: `Unit attributes`
- **Components**:
  - attributes: `TypeAttributes`
- **JSON**: `{"Unit": {}}`

## JSON Serialization Summary

IR v4 supports two serialization modes:

### Compact Format (default)

Type expressions use maximally compact forms where context is unambiguous:

| Type Expression | JSON Format | Example |
|-----------------|-------------|---------|
| Variable | Bare name string | `"a"` |
| Reference (no args) | Bare FQName string | `"morphir/SDK:int#int"` |
| Reference (with args) | Array with fqname + args | `{"Reference": ["morphir/SDK:list#list", "a"]}` |
| Record | Object with fields wrapper | `{"Record": {"fields": {"name": "morphir/SDK:string#string"}}}` |
| Tuple | Bare array, or wrapper with array | `["a", "b"]` or `{"Tuple": ["a", "b"]}` |
| Function | Object with parameter and return | `{"Function": {"parameterType": ..., "returnType": ...}}` |
| Unit | Empty object | `{"Unit": {}}` |

**Disambiguation**: Variables and References without args are both strings, but can be distinguished:
- Variables: simple name without special characters (e.g., `"a"`, `"comparable"`)
- References: FQName format with `:` and `#` (e.g., `"morphir/SDK:int#int"`)
- A bare array is always a Tuple. A Reference with type arguments always carries the `Reference` wrapper, so `["morphir/SDK:int#int", "morphir/SDK:string#string"]` is the pair `(Int, String)`, never a parameterized reference

### Expanded Format

For tooling that prefers explicit structure, an expanded format is available:

| Type Expression | JSON Format | Example |
|-----------------|-------------|---------|
| Variable | Object with attributes and name | `{"Variable": {"attributes": {...}, "name": "a"}}` |
| Reference | Object with attributes, fqname and args | `{"Reference": {"attributes": {...}, "fqname": "morphir/SDK:list#list", "args": ["a"]}}` |
| Record | Object with attributes and fields | `{"Record": {"attributes": {...}, "fields": {...}}}` |
| Tuple | Object with attributes and elements | `{"Tuple": {"attributes": {...}, "elements": [...]}}` |
| Function | Object with attributes, parameter and return | `{"Function": {"attributes": {...}, "parameterType": ..., "returnType": ...}}` |
| Unit | Object with attributes | `{"Unit": {"attributes": {...}}}` |

**Note**: Every node's expanded payload starts with an optional `attributes` member (decision 0005). Writers use the compact form whenever attributes are empty; an expanded payload with empty attributes is accepted and never written.

## Type Specifications

A **Type Specification** defines the public interface of a type—the contract exposed to consumers of a module. Specifications contain no implementation details and are always public.

**Purpose**: When module A depends on module B, module A only sees module B's specifications, not its definitions. This enables:
- Separate compilation (consumers don't need implementation details)
- API stability (internal changes don't affect dependents)
- Information hiding (private types appear as opaque)

**Deriving specifications**: A specification can always be derived from its corresponding definition:
- `TypeAliasDefinition` → `TypeAliasSpecification`
- `CustomTypeDefinition` → `CustomTypeSpecification` (public constructors only)
- `IncompleteTypeDefinition` → `OpaqueTypeSpecification` (hides internal brokenness)

### TypeAliasSpecification

An alias for another type. Type aliases provide a new name for an existing type.

- **Structure**: `TypeAliasSpecification typeParams type`
- **Components**:
  - typeParams: List of type parameters (`List Name`)
  - type: The aliased type expression (`Type`)

**Example 1: Simple type alias (no parameters)**

```elm
type alias UserId = String
```

```json
{
  "TypeAliasSpecification": {
    "typeParams": [],
    "type": "morphir/SDK:string#string"
  }
}
```

**Example 2: Type alias with type parameters**

```elm
type alias Pair a b = ( a, b )
```

```json
{
  "TypeAliasSpecification": {
    "typeParams": ["a", "b"],
    "type": { "Tuple": ["a", "b"] }
  }
}
```

**Example 3: Record type alias**

```elm
type alias Person = { name : String, age : Int, email : Maybe String }
```

```json
{
  "TypeAliasSpecification": {
    "typeParams": [],
    "type": {
      "Record": {
        "fields": {
          "name": "morphir/SDK:string#string",
          "age": "morphir/SDK:basics#int",
          "email": { "Reference": ["morphir/SDK:maybe#maybe", "morphir/SDK:string#string"] }
        }
      }
    }
  }
}
```

**Example 4: Function type alias**

```elm
type alias Predicate a = a -> Bool
```

```json
{
  "TypeAliasSpecification": {
    "typeParams": ["a"],
    "type": { "Function": { "parameterType": "a", "returnType": "morphir/SDK:basics#bool" } }
  }
}
```

### OpaqueTypeSpecification

A type with unknown structure. Opaque types hide their internal implementation.

- **Structure**: `OpaqueTypeSpecification typeParams`
- **Components**:
  - typeParams: List of type parameters (`List Name`)

**Example 1: Simple opaque type (no parameters)**

```elm
-- Int is opaque - its internal representation is hidden
type Int
```

```json
{ "OpaqueTypeSpecification": { "typeParams": [] } }
```

**Example 2: Parameterized opaque type**

```elm
-- A set implementation where the internal structure is hidden
type Set a
```

```json
{ "OpaqueTypeSpecification": { "typeParams": ["a"] } }
```

**Example 3: Multi-parameter opaque type**

```elm
type Dict k v
```

```json
{ "OpaqueTypeSpecification": { "typeParams": ["k", "v"] } }
```

### CustomTypeSpecification

A tagged union type (sum type). Custom types define a closed set of constructors.

- **Structure**: `CustomTypeSpecification typeParams constructors`
- **Components**:
  - typeParams: List of type parameters (`List Name`)
  - constructors: Dictionary of constructor names to their arguments (`Dict Name (List (Name, Type))`)

**Example 1: Simple enumeration (no data)**

```elm
type Color = Red | Green | Blue
```

```json
{
  "CustomTypeSpecification": {
    "typeParams": [],
    "constructors": { "red": [], "green": [], "blue": [] }
  }
}
```

**Example 2: Maybe type (parameterized)**

```elm
type Maybe a = Just a | Nothing
```

```json
{
  "CustomTypeSpecification": {
    "typeParams": ["a"],
    "constructors": {
      "just": [["value", "a"]],
      "nothing": []
    }
  }
}
```

**Example 3: Result type (two type parameters)**

```elm
type Result error value = Ok value | Err error
```

```json
{
  "CustomTypeSpecification": {
    "typeParams": ["error", "value"],
    "constructors": {
      "ok": [["value", "value"]],
      "err": [["error", "error"]]
    }
  }
}
```

**Example 4: List type (recursive)**

```elm
type List a = Nil | Cons a (List a)
```

```json
{
  "CustomTypeSpecification": {
    "typeParams": ["a"],
    "constructors": {
      "nil": [],
      "cons": [["head", "a"], ["tail", { "Reference": ["morphir/SDK:list#list", "a"] }]]
    }
  }
}
```

**Example 5: Complex domain type**

```elm
type PaymentMethod
    = CreditCard { number : String, expiry : String, cvv : String }
    | BankTransfer { accountNumber : String, routingNumber : String }
    | Cash
```

```json
{
  "CustomTypeSpecification": {
    "typeParams": [],
    "constructors": {
      "credit-card": [
        ["number", "morphir/SDK:string#string"],
        ["expiry", "morphir/SDK:string#string"],
        ["cvv", "morphir/SDK:string#string"]
      ],
      "bank-transfer": [
        ["account-number", "morphir/SDK:string#string"],
        ["routing-number", "morphir/SDK:string#string"]
      ],
      "cash": []
    }
  }
}
```

### DerivedTypeSpecification

A type with platform-specific representation but known serialization.

- **Structure**: `DerivedTypeSpecification typeParams details`
- **Details**:
  - `baseType`: The type used for serialization
  - `fromBaseType`: FQName of function to convert from base type
  - `toBaseType`: FQName of function to convert to base type

**Example 1: LocalDate derived from String**

```elm
-- A date type that serializes as ISO 8601 string
type LocalDate
```

```json
{
  "DerivedTypeSpecification": {
    "typeParams": [],
    "baseType": "morphir/SDK:string#string",
    "fromBaseType": "morphir/SDK:local-date#from-i-s-o",
    "toBaseType": "morphir/SDK:local-date#to-i-s-o"
  }
}
```

**Example 2: Decimal derived from String**

```elm
-- Precise decimal avoiding floating point issues
type Decimal
```

```json
{
  "DerivedTypeSpecification": {
    "typeParams": [],
    "baseType": "morphir/SDK:string#string",
    "fromBaseType": "morphir/SDK:decimal#from-string",
    "toBaseType": "morphir/SDK:decimal#to-string"
  }
}
```

**Example 3: Money derived from record**

```elm
type Money
```

```json
{
  "DerivedTypeSpecification": {
    "typeParams": [],
    "baseType": {
      "Record": {
        "fields": {
          "amount": "morphir/SDK:decimal#decimal",
          "currency": "morphir/SDK:string#string"
        }
      }
    },
    "fromBaseType": "my-org/finance:money#from-record",
    "toBaseType": "my-org/finance:money#to-record"
  }
}
```

**Example 4: Parameterized derived type**

```elm
-- NonEmpty list that serializes as regular list
type NonEmpty a
```

```json
{
  "DerivedTypeSpecification": {
    "typeParams": ["a"],
    "baseType": { "Reference": ["morphir/SDK:list#list", "a"] },
    "fromBaseType": "my-org/collections:non-empty#from-list",
    "toBaseType": "my-org/collections:non-empty#to-list"
  }
}
```

## Type Definitions

A **Type Definition** provides the complete implementation of a type, owned by the defining module. Unlike specifications, definitions can be public or private (controlled via `AccessControlled` wrapper).

**Purpose**: Definitions contain everything needed to:
- Generate code for the type
- Perform type checking within the module
- Derive the public specification for dependents

**Access control**: Definitions are wrapped with `AccessControlled` to indicate visibility:
- `Public`: Exposed in the module's specification
- `Private`: Internal to the module, not visible to dependents

### TypeAliasDefinition

Complete definition of a type alias.

- **Structure**: `TypeAliasDefinition typeParams type`

### CustomTypeDefinition

Complete definition of a custom type.

- **Structure**: `CustomTypeDefinition typeParams constructors`
- **Components**:
  - typeParams: List of type parameters (`List Name`)
  - constructors: Access-controlled constructors (`AccessControlled Constructors`)

### IncompleteTypeDefinition (v4)

A type definition that is incomplete or broken. This enables best-effort compilation and incremental development.

- **Structure**: `IncompleteTypeDefinition typeParams incompleteness partialBody`
- **Components**:
  - typeParams: List of type parameters (`List Name`)
  - incompleteness: The reason for incompleteness (`Incompleteness`)
  - partialBody: Optional partial type body (`Option Type`)

## Incompleteness (v4)

Describes why a type or value definition is incomplete.

### Hole

Represents a reference to something that was deleted, renamed, or otherwise broken.

- **Structure**: `Hole reason`
- **Components**:
  - reason: Specific reason for the hole (`HoleReason`)

### Draft

Represents author-marked work-in-progress.

- **Structure**: `Draft notes`
- **Components**:
  - notes: Optional notes about the draft (`Option String`)

## HoleReason (v4)

Specific reasons why a Hole exists.

### UnresolvedReference

A reference to a type or value that cannot be resolved.

- **Structure**: `UnresolvedReference target`
- **Components**:
  - target: The fully-qualified name that cannot be resolved (`FQName`)

### DeletedDuringRefactor

A reference that was deleted during a refactoring operation.

- **Structure**: `DeletedDuringRefactor txId`
- **Components**:
  - txId: Transaction ID of the refactoring operation (`String`)

### TypeMismatch

A type that doesn't match expectations.

- **Structure**: `TypeMismatch expected found`
- **Components**:
  - expected: Description of expected type (`String`)
  - found: Description of found type (`String`)
