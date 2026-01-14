---
title: "Schema Version 3"
linkTitle: "Version 3"
weight: 1
description: "Morphir IR JSON Schema for format version 3 (Current)"
---

# Morphir IR Schema - Version 3

Format version 3 is the current version of the Morphir IR format. It uses capitalized tags throughout for consistency and clarity.

## Overview

Version 3 of the Morphir IR format standardizes on capitalized tags for all constructs. This provides a consistent naming convention across the entire IR structure.

## Key Characteristics

### Tag Capitalization

All tags in version 3 are capitalized:

- **Distribution**: `"Library"`
- **Access Control**: `"Public"` and `"Private"`
- **Type Tags**: `"Variable"`, `"Reference"`, `"Tuple"`, `"Record"`, etc.
- **Value Tags**: `"Apply"`, `"Lambda"`, `"LetDefinition"`, etc.
- **Pattern Tags**: `"AsPattern"`, `"WildcardPattern"`, `"ConstructorPattern"`, etc.
- **Literal Tags**: `"BoolLiteral"`, `"StringLiteral"`, `"WholeNumberLiteral"`, etc.

## Core Concepts

### Naming System

The Morphir IR uses a sophisticated naming system independent of any specific naming convention.

#### Name

A **Name** represents a human-readable identifier made up of one or more words.

- **Structure**: Array of lowercase word strings
- **Purpose**: Atomic unit for all identifiers
- **Example**: `["value", "in", "u", "s", "d"]` renders as `valueInUSD` or `value_in_USD`

```yaml
Name:
  type: array
  items:
    type: string
    pattern: "^[a-z][a-z0-9]*$"
  minItems: 1
```

#### Path

A **Path** represents a hierarchical location in the IR structure.

- **Structure**: List of Names
- **Purpose**: Identifies packages and modules
- **Example**: `[["morphir"], ["s", "d", "k"], ["string"]]` for the String module

```yaml
Path:
  type: array
  items:
    $ref: "#/definitions/Name"
  minItems: 1
```

#### Fully-Qualified Name (FQName)

Provides globally unique identifiers for types and values.

- **Structure**: `[packagePath, modulePath, localName]`
- **Purpose**: Unambiguous references across package boundaries

```yaml
FQName:
  type: array
  minItems: 3
  maxItems: 3
  items:
    - $ref: "#/definitions/PackageName"
    - $ref: "#/definitions/ModuleName"
    - $ref: "#/definitions/Name"
```

### Access Control

#### AccessControlled

Manages visibility of types and values.

- **Structure**: `{access, value}`
- **Access levels**: `"Public"` (visible externally) or `"Private"` (package-only)
- **Purpose**: Controls API exposure

```yaml
AccessControlled:
  type: object
  required: ["access", "value"]
  properties:
    access:
      type: string
      enum: ["Public", "Private"]
    value:
      description: "The value being access controlled."
```

## Distribution and Package Structure

### Distribution

A **Distribution** represents a complete, self-contained package with all dependencies.

- **Current type**: Library (only supported distribution type)
- **Structure**: `["Library", packageName, dependencies, packageDefinition]`
- **Purpose**: Output of compilation process, ready for execution or transformation

```yaml
distribution:
  type: array
  minItems: 4
  maxItems: 4
  items:
    - type: string
      const: "Library"
    - $ref: "#/definitions/PackageName"
    - $ref: "#/definitions/Dependencies"
    - $ref: "#/definitions/PackageDefinition"
```

### Package Definition

Complete implementation of a package with all details.

- **Contains**: All modules (public and private)
- **Includes**: Type signatures and implementations
- **Purpose**: Full package representation for processing

### Package Specification

Public interface of a package.

- **Contains**: Only publicly exposed modules
- **Includes**: Only type signatures, no implementations
- **Purpose**: Dependency interface

## Module Structure

### Module Definition

Complete implementation of a module.

- **Contains**: All types and values (public and private) with implementations
- **Structure**: Dictionary of type names to AccessControlled type definitions, and value names to AccessControlled value definitions
- **Purpose**: Complete module implementation

### Module Specification

Public interface of a module.

- **Contains**: Only publicly exposed types and values
- **Includes**: Type signatures only, no implementations
- **Purpose**: Module's public API

## Type System

The type system is based on functional programming principles, supporting:

### Type Expressions

#### Variable

Represents a type variable (generic parameter).

- **Structure**: `["Variable", attributes, name]`
- **Example**: The `a` in `List a`
- **Purpose**: Enables polymorphic types

```yaml
VariableType:
  type: array
  minItems: 3
  maxItems: 3
  items:
    - const: "Variable"
    - $ref: "#/definitions/Attributes"
    - $ref: "#/definitions/Name"
```

#### Reference

Reference to another type or type alias.

- **Structure**: `["Reference", attributes, fqName, typeArgs]`
- **Examples**: `String`, `List Int`, `Maybe a`
- **Purpose**: References built-in types, custom types, or type aliases

```yaml
ReferenceType:
  type: array
  minItems: 4
  maxItems: 4
  items:
    - const: "Reference"
    - $ref: "#/definitions/Attributes"
    - $ref: "#/definitions/FQName"
    - type: array
      items:
        $ref: "#/definitions/Type"
```

#### Tuple

Composition of multiple types in fixed order.

- **Structure**: `["Tuple", attributes, elementTypes]`
- **Example**: `(Int, String, Bool)`
- **Purpose**: Product types with positional access

#### Record

Composition of named fields with types.

- **Structure**: `["Record", attributes, fields]`
- **Example**: `{firstName: String, age: Int}`
- **Purpose**: Product types with named field access
- **Note**: All fields are required

#### Function

Function type representation.

- **Structure**: `["Function", attributes, argType, returnType]`
- **Example**: `Int -> String`
- **Purpose**: Represents function and lambda types
- **Note**: Multi-argument functions use currying (nested Function types)

### Type Specifications

#### TypeAliasSpecification

An alias for another type.

- **Structure**: `["TypeAliasSpecification", typeParams, aliasedType]`
- **Example**: `type alias UserId = String`
- **Purpose**: Meaningful name for type expression

#### CustomTypeSpecification

Tagged union type (sum type).

- **Structure**: `["CustomTypeSpecification", typeParams, constructors]`
- **Example**: `type Result e a = Ok a | Err e`
- **Purpose**: Choice between multiple alternatives

#### OpaqueTypeSpecification

Type with unknown structure.

- **Structure**: `["OpaqueTypeSpecification", typeParams]`
- **Characteristics**: Structure hidden, no automatic serialization
- **Purpose**: Encapsulates implementation details

## Value System

All data and logic in Morphir are represented as value expressions.

### Value Expressions

#### Literal

Literal constant value.

- **Structure**: `["Literal", attributes, literal]`
- **Types**: BoolLiteral, CharLiteral, StringLiteral, WholeNumberLiteral, FloatLiteral, DecimalLiteral
- **Purpose**: Represents constant data

#### Variable

Reference to a variable in scope.

- **Structure**: `["Variable", attributes, name]`
- **Example**: References to function parameters or let-bound variables
- **Purpose**: Accesses values bound in current scope

#### Reference

Reference to a defined value (function or constant).

- **Structure**: `["Reference", attributes, fqName]`
- **Example**: `Morphir.SDK.List.map`, `Basics.add`
- **Purpose**: Invokes or references defined functions

#### Apply

Function application.

- **Structure**: `["Apply", attributes, function, argument]`
- **Example**: `add 1 2` (nested Apply nodes for currying)
- **Purpose**: Invokes functions with arguments

#### Lambda

Anonymous function.

- **Structure**: `["Lambda", attributes, argumentPattern, body]`
- **Example**: `\x -> x + 1`
- **Purpose**: Creates inline functions

#### LetDefinition

Let binding introducing a single value.

- **Structure**: `["LetDefinition", attributes, bindingName, definition, inExpr]`
- **Example**: `let x = 5 in x + x`
- **Purpose**: Introduces local bindings

#### IfThenElse

Conditional expression.

- **Structure**: `["IfThenElse", attributes, condition, thenBranch, elseBranch]`
- **Example**: `if x > 0 then "positive" else "non-positive"`
- **Purpose**: Conditional logic

#### PatternMatch

Pattern matching with multiple cases.

- **Structure**: `["PatternMatch", attributes, valueToMatch, cases]`
- **Example**: `case maybeValue of Just x -> x; Nothing -> 0`
- **Purpose**: Conditional logic based on structure

### Patterns

Used for destructuring and filtering values.

#### WildcardPattern

Matches any value without binding.

- **Structure**: `["WildcardPattern", attributes]`
- **Syntax**: `_`
- **Purpose**: Ignores a value

#### AsPattern

Binds a name to a matched value.

- **Structure**: `["AsPattern", attributes, nestedPattern, variableName]`
- **Special case**: Simple variable binding uses `AsPattern` with `WildcardPattern`
- **Purpose**: Captures matched values

#### ConstructorPattern

Matches specific type constructor and arguments.

- **Structure**: `["ConstructorPattern", attributes, fqName, argPatterns]`
- **Example**: `Just x` matches `Just` with pattern `x`
- **Purpose**: Destructures and filters tagged unions

### Literals

#### BoolLiteral

Boolean literal.

- **Structure**: `["BoolLiteral", boolean]`
- **Values**: `true` or `false`

```yaml
BoolLiteral:
  type: array
  minItems: 2
  maxItems: 2
  items:
    - const: "BoolLiteral"
    - type: boolean
```

#### StringLiteral

Text string literal.

- **Structure**: `["StringLiteral", string]`
- **Example**: `"hello"`

```yaml
StringLiteral:
  type: array
  minItems: 2
  maxItems: 2
  items:
    - const: "StringLiteral"
    - type: string
```

#### WholeNumberLiteral

Integer literal.

- **Structure**: `["WholeNumberLiteral", integer]`
- **Example**: `42`, `-17`

## Recommended Format

Version 3 is the recommended format for new Morphir IR files. It provides:

- **Consistency**: All tags follow the same capitalization convention
- **Clarity**: Capitalized tags are easier to distinguish in JSON
- **Future-proof**: This format will be maintained going forward

## Full Schema

For the complete schema definition, see the [full schema page](./full/).

## References

- [Morphir IR Specification](../../morphir-ir-specification/)
- [Schema Version 1](../v1/)
- [Schema Version 2](../v2/)
