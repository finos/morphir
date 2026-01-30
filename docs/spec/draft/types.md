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
  - `String` → FQName: `morphir/sdk:string#string`
  - `List Int` → FQName: `morphir/sdk:list#list` with type argument `morphir/sdk:basics#int`
  - `Dict String Int` → FQName: `morphir/sdk:dict#dict` with type arguments
- **JSON (compact, no type args)**: `"morphir/sdk:string#string"` — bare FQName string
- **JSON (compact, with type args)**: `{"Reference": ["morphir/sdk:list#list", "a"]}` — array with FQName first, followed by type args
- **JSON (expanded)**: `{"Reference": {"fqname": "morphir/sdk:list#list", "args": [...]}}` — object with fqname and args keys
- **Legacy format**: `[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]]` (package, module, local name arrays)

### Tuple

A composition of multiple types in a fixed order.

- **Structure**: `Tuple attributes elements`
- **Components**:
  - attributes: `TypeAttributes`
  - elements: Element types in order (`List Type`)
- **JSON**: `{"Tuple": {"elements": ["morphir/sdk:int#int", "morphir/sdk:string#string"]}}`

### Record

A composition of named fields with their types.

- **Structure**: `Record attributes fields`
- **Components**:
  - attributes: `TypeAttributes`
  - fields: Dictionary of field names to types
- **JSON (compact)**: `{"Record": {"field-name": "morphir/sdk:string#string", "age": "morphir/sdk:int#int"}}`
  - Fields are stored directly under `Record` without a wrapper
  - Field names use kebab-case

### ExtensibleRecord

A record type that can be extended with additional fields.

- **Structure**: `ExtensibleRecord attributes variable fields`
- **Components**:
  - attributes: `TypeAttributes`
  - variable: Type variable representing the extension (`Name`)
  - fields: Known fields (dictionary of names to types)
- **JSON**: `{"ExtensibleRecord": {"variable": "a", "fields": {"name": "morphir/sdk:string#string"}}}`

### Function

Represents a function type.

- **Structure**: `Function attributes argumentType returnType`
- **Components**:
  - attributes: `TypeAttributes`
  - argumentType: Argument type (`Type`)
  - returnType: Return type (`Type`)
- **JSON**: `{"Function": {"argumentType": "morphir/sdk:int#int", "returnType": "morphir/sdk:string#string"}}`

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
| Reference (no args) | Bare FQName string | `"morphir/sdk:int#int"` |
| Reference (with args) | Array with fqname + args | `{"Reference": ["morphir/sdk:list#list", "a"]}` |
| Record | Object with field map | `{"Record": {"name": "morphir/sdk:string#string"}}` |
| Tuple | Object with elements | `{"Tuple": {"elements": [...]}}` |
| Function | Object with argument and return | `{"Function": {"argumentType": ..., "returnType": ...}}` |
| Unit | Empty object | `{"Unit": {}}` |

**Disambiguation**: Variables and References without args are both strings, but can be distinguished:
- Variables: simple name without special characters (e.g., `"a"`, `"comparable"`)
- References: FQName format with `:` and `#` (e.g., `"morphir/sdk:int#int"`)

### Expanded Format

For tooling that prefers explicit structure, an expanded format is available:

| Type Expression | JSON Format | Example |
|-----------------|-------------|---------|
| Variable | Object with name key | `{"Variable": {"name": "a"}}` |
| Reference | Object with fqname and args | `{"Reference": {"fqname": "morphir/sdk:list#list", "args": ["a"]}}` |
| Record | Object with field map | `{"Record": {"name": "morphir/sdk:string#string"}}` |
| Tuple | Object with elements | `{"Tuple": {"elements": [...]}}` |
| Function | Object with argument and return | `{"Function": {"argumentType": ..., "returnType": ...}}` |
| Unit | Empty object | `{"Unit": {}}` |

**Note**: The expanded format is identical to compact for Record, Tuple, Function, and Unit types. Use `morphir ir migrate --expanded` to produce expanded format output.

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
    "type": "morphir/sdk:string#string"
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
    "type": { "Tuple": { "elements": ["a", "b"] } }
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
        "name": "morphir/sdk:string#string",
        "age": "morphir/sdk:basics#int",
        "email": ["morphir/sdk:maybe#maybe", "morphir/sdk:string#string"]
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
    "type": { "Function": { "argumentType": "a", "returnType": "morphir/sdk:basics#bool" } }
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
      "cons": [["head", "a"], ["tail", ["morphir/sdk:list#list", "a"]]]
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
        ["number", "morphir/sdk:string#string"],
        ["expiry", "morphir/sdk:string#string"],
        ["cvv", "morphir/sdk:string#string"]
      ],
      "bank-transfer": [
        ["account-number", "morphir/sdk:string#string"],
        ["routing-number", "morphir/sdk:string#string"]
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
    "baseType": "morphir/sdk:string#string",
    "fromBaseType": "morphir/sdk:local-date#from-i-s-o",
    "toBaseType": "morphir/sdk:local-date#to-i-s-o"
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
    "baseType": "morphir/sdk:string#string",
    "fromBaseType": "morphir/sdk:decimal#from-string",
    "toBaseType": "morphir/sdk:decimal#to-string"
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
        "amount": "morphir/sdk:decimal#decimal",
        "currency": "morphir/sdk:string#string"
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
    "baseType": ["morphir/sdk:list#list", "a"],
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
