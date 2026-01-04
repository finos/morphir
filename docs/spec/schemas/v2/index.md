---
title: "Schema Version 2"
linkTitle: "Version 2"
weight: 2
description: "Morphir IR JSON Schema for format version 2"
---

# Morphir IR Schema - Version 2

Format version 2 introduced capitalized tags for distribution, access control, and types, while keeping value and pattern tags lowercase.

## Overview

Version 2 of the Morphir IR format represents a transition between version 1 (all lowercase) and version 3 (all capitalized). It uses capitalized tags for distribution, access control, and types, but keeps value expressions and patterns in lowercase.

## Key Characteristics

### Tag Capitalization

Version 2 uses a mixed capitalization approach:

**Capitalized:**
- **Distribution**: `"Library"` (capitalized)
- **Access Control**: `"Public"` and `"Private"` (capitalized)
- **Type Tags**: `"Variable"`, `"Reference"`, `"Tuple"`, `"Record"`, etc.

**Lowercase:**
- **Value Tags**: `"apply"`, `"lambda"`, `"let_definition"`, etc.
- **Pattern Tags**: `"as_pattern"`, `"wildcard_pattern"`, etc.
- **Literal Tags**: `"bool_literal"`, `"string_literal"`, etc.

### Module Structure

Version 2 changed the module structure from objects to arrays:

```yaml
modules:
  type: array
  items:
    type: array
    minItems: 2
    maxItems: 2
    items:
      - $ref: "#/definitions/ModuleName"
      - allOf:
          - $ref: "#/definitions/AccessControlled"
          - properties:
              value:
                $ref: "#/definitions/ModuleDefinition"
```

This is a significant change from version 1's `{"name": ..., "def": ...}` structure.

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
- **Version 2 note**: Capitalized access levels (`"Public"`, `"Private"`)

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
- **Version 2 note**: Uses capitalized `"Library"` tag

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
- **Version 2 note**: Modules stored as arrays of `[name, accessControlledDefinition]` pairs

### Package Specification

Public interface of a package.

- **Contains**: Only publicly exposed modules
- **Includes**: Only type signatures, no implementations
- **Purpose**: Dependency interface

## Module Structure Details

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

**Version 2 note**: Type tags are **capitalized** in version 2.

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

**Version 2 note**: Value tags are **lowercase** in version 2.

### Value Expressions

#### literal

Literal constant value.

- **Structure**: `["literal", attributes, literal]`
- **Types**: bool_literal, char_literal, string_literal, whole_number_literal, float_literal, decimal_literal
- **Purpose**: Represents constant data

#### variable

Reference to a variable in scope.

- **Structure**: `["variable", attributes, name]`
- **Example**: References to function parameters or let-bound variables
- **Purpose**: Accesses values bound in current scope

#### reference

Reference to a defined value (function or constant).

- **Structure**: `["reference", attributes, fqName]`
- **Example**: `Morphir.SDK.List.map`, `Basics.add`
- **Purpose**: Invokes or references defined functions

#### apply

Function application.

- **Structure**: `["apply", attributes, function, argument]`
- **Example**: `add 1 2` (nested apply nodes for currying)
- **Purpose**: Invokes functions with arguments

```yaml
ApplyValue:
  type: array
  minItems: 4
  maxItems: 4
  items:
    - const: "apply"
    - $ref: "#/definitions/Attributes"
    - $ref: "#/definitions/Value"
    - $ref: "#/definitions/Value"
```

#### lambda

Anonymous function.

- **Structure**: `["lambda", attributes, argumentPattern, body]`
- **Example**: `\x -> x + 1`
- **Purpose**: Creates inline functions

```yaml
LambdaValue:
  type: array
  minItems: 4
  maxItems: 4
  items:
    - const: "lambda"
    - $ref: "#/definitions/Attributes"
    - $ref: "#/definitions/Pattern"
    - $ref: "#/definitions/Value"
```

#### let_definition

Let binding introducing a single value.

- **Structure**: `["let_definition", attributes, bindingName, definition, inExpr]`
- **Example**: `let x = 5 in x + x`
- **Purpose**: Introduces local bindings

#### if_then_else

Conditional expression.

- **Structure**: `["if_then_else", attributes, condition, thenBranch, elseBranch]`
- **Example**: `if x > 0 then "positive" else "non-positive"`
- **Purpose**: Conditional logic

#### pattern_match

Pattern matching with multiple cases.

- **Structure**: `["pattern_match", attributes, valueToMatch, cases]`
- **Example**: `case maybeValue of Just x -> x; Nothing -> 0`
- **Purpose**: Conditional logic based on structure

### Patterns

Used for destructuring and filtering values.

**Version 2 note**: Pattern tags are **lowercase** in version 2.

#### wildcard_pattern

Matches any value without binding.

- **Structure**: `["wildcard_pattern", attributes]`
- **Syntax**: `_`
- **Purpose**: Ignores a value

#### as_pattern

Binds a name to a matched value.

- **Structure**: `["as_pattern", attributes, nestedPattern, variableName]`
- **Special case**: Simple variable binding uses `as_pattern` with `wildcard_pattern`
- **Purpose**: Captures matched values

#### constructor_pattern

Matches specific type constructor and arguments.

- **Structure**: `["constructor_pattern", attributes, fqName, argPatterns]`
- **Example**: `Just x` matches `Just` with pattern `x`
- **Purpose**: Destructures and filters tagged unions

### Literals

**Version 2 note**: Literal tags are **lowercase** in version 2.

#### bool_literal

Boolean literal.

- **Structure**: `["bool_literal", boolean]`
- **Values**: `true` or `false`

```yaml
BoolLiteral:
  type: array
  minItems: 2
  maxItems: 2
  items:
    - const: "bool_literal"
    - type: boolean
```

#### string_literal

Text string literal.

- **Structure**: `["string_literal", string]`
- **Example**: `"hello"`

```yaml
StringLiteral:
  type: array
  minItems: 2
  maxItems: 2
  items:
    - const: "string_literal"
    - type: string
```

#### whole_number_literal

Integer literal.

- **Structure**: `["whole_number_literal", integer]`
- **Example**: `42`, `-17`

## Migration from Version 2

When migrating from version 2 to version 3:

1. **Capitalize value tags**: `"apply"` → `"Apply"`, `"lambda"` → `"Lambda"`, etc.
2. **Capitalize pattern tags**: `"as_pattern"` → `"AsPattern"`, `"wildcard_pattern"` → `"WildcardPattern"`, etc.
3. **Capitalize literal tags**: `"bool_literal"` → `"BoolLiteral"`, `"string_literal"` → `"StringLiteral"`, etc.

## Full Schema

For the complete schema definition, see the [full schema page](./full/).

## References

- [Morphir IR Specification](../../morphir-ir-specification/)
- [Schema Version 1](../v1/)
- [Schema Version 3](../v3/)

