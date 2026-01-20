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

### Reference

A reference to another type or type alias.

- **Structure**: `Reference attributes fqName args`
- **Components**:
  - attributes: `TypeAttributes`
  - fqName: Fully-qualified name of the referenced type (`FQName`)
  - args: List of type arguments (`List Type`)
- **Examples**:
  - `String` → `Reference attrs (["morphir"], ["s", "d", "k"], ["string"]) []`
  - `List Int` → `Reference attrs (["morphir"], ["s", "d", "k"], ["list"]) [intType]`

### Tuple

A composition of multiple types in a fixed order.

- **Structure**: `Tuple attributes elements`
- **Components**:
  - attributes: `TypeAttributes`
  - elements: Element types in order (`List Type`)

### Record

A composition of named fields with their types.

- **Structure**: `Record attributes fields`
- **Components**:
  - attributes: `TypeAttributes`
  - fields: List of field definitions (`List Field`)

**Field**: `{ name: Name, tpe: Type }`

### ExtensibleRecord

A record type that can be extended with additional fields.

- **Structure**: `ExtensibleRecord attributes variable fields`
- **Components**:
  - attributes: `TypeAttributes`
  - variable: Type variable representing the extension (`Name`)
  - fields: Known fields (`List Field`)

### Function

Represents a function type.

- **Structure**: `Function attributes argumentType returnType`
- **Components**:
  - attributes: `TypeAttributes`
  - argumentType: Argument type (`Type`)
  - returnType: Return type (`Type`)

### Unit

The type with exactly one value.

- **Structure**: `Unit attributes`
- **Components**:
  - attributes: `TypeAttributes`

## Type Specifications

A **Type Specification** defines the interface of a type without implementation details.

### TypeAliasSpecification

An alias for another type.

- **Structure**: `TypeAliasSpecification typeParams type`
- **Components**:
  - typeParams: List of type parameters (`List Name`)
  - type: The aliased type expression (`Type`)

### OpaqueTypeSpecification

A type with unknown structure.

- **Structure**: `OpaqueTypeSpecification typeParams`
- **Components**:
  - typeParams: List of type parameters (`List Name`)

### CustomTypeSpecification

A tagged union type (sum type).

- **Structure**: `CustomTypeSpecification typeParams constructors`
- **Components**:
  - typeParams: List of type parameters (`List Name`)
  - constructors: Dictionary of constructor names to their arguments (`Dict Name (List (Name, Type))`)

### DerivedTypeSpecification

A type with platform-specific representation but known serialization.

- **Structure**: `DerivedTypeSpecification typeParams details`
- **Details**:
  - `baseType`: The type used for serialization
  - `fromBaseType`: FQName of function to convert from base type
  - `toBaseType`: FQName of function to convert to base type

## Type Definitions

A **Type Definition** provides the complete implementation of a type.

### TypeAliasDefinition

Complete definition of a type alias.

- **Structure**: `TypeAliasDefinition typeParams type`

### CustomTypeDefinition

Complete definition of a custom type.

- **Structure**: `CustomTypeDefinition typeParams constructors`
- **Components**:
  - typeParams: List of type parameters (`List Name`)
  - constructors: Access-controlled constructors (`AccessControlled Constructors`)
