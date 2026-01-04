---
title: "Schema Version 1"
linkTitle: "Version 1"
weight: 3
description: "Morphir IR JSON Schema for format version 1"
---

# Morphir IR Schema - Version 1

Format version 1 is the original Morphir IR format. It uses lowercase tag names throughout and has a different module structure compared to later versions.

## Overview

Version 1 of the Morphir IR format uses lowercase tags for all constructs. This includes distribution types, access control levels, type tags, value expression tags, pattern tags, and literal tags.

## Key Characteristics

### Tag Capitalization

All tags in version 1 are lowercase:

- **Distribution**: `"library"` (not `"Library"`)
- **Access Control**: `"public"` and `"private"` (not `"Public"` and `"Private"`)
- **Type Tags**: `"variable"`, `"reference"`, `"tuple"`, `"record"`, etc.
- **Value Tags**: `"apply"`, `"lambda"`, `"let_definition"`, etc.
- **Pattern Tags**: `"as_pattern"`, `"wildcard_pattern"`, `"constructor_pattern"`, etc.
- **Literal Tags**: `"bool_literal"`, `"string_literal"`, `"whole_number_literal"`, etc.

### Module Structure

In version 1, modules are represented as objects with `name` and `def` fields:

```yaml
ModuleEntry:
  type: object
  required: ["name", "def"]
  properties:
    name:
      $ref: "#/definitions/ModuleName"
    def:
      type: array
      minItems: 2
      maxItems: 2
      items:
        - $ref: "#/definitions/AccessLevel"
        - $ref: "#/definitions/ModuleDefinition"
```

This differs from version 2+, where modules are represented as arrays: `[modulePath, accessControlled]`.

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
  description: |
    A Name is a list of lowercase words that represents a human-readable identifier.
    Example: ["value", "in", "u", "s", "d"] can be rendered as valueInUSD or value_in_USD.
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
  description: |
    A Path is a list of Names representing a hierarchical location in the IR structure.
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

#### Access Levels

Manages visibility of types and values.

- **Levels**: `"public"` (visible externally) or `"private"` (package-only)
- **Purpose**: Controls API exposure
- **Version 1 note**: Lowercase access levels (`"public"`, `"private"`)

```yaml
AccessLevel:
  type: string
  enum: ["public", "private"]
```

## Distribution and Package Structure

### Distribution

A **Distribution** represents a complete, self-contained package with all dependencies.

- **Current type**: library (only supported distribution type)
- **Structure**: `["library", packageName, dependencies, packageDefinition]`
- **Purpose**: Output of compilation process, ready for execution or transformation
- **Version 1 note**: Uses lowercase `"library"` tag

```yaml
distribution:
  type: array
  minItems: 4
  maxItems: 4
  items:
    - type: string
      const: "library"
    - $ref: "#/definitions/PackageName"
    - $ref: "#/definitions/Dependencies"
    - $ref: "#/definitions/PackageDefinition"
```

### Package Definition

Complete implementation of a package with all details.

- **Contains**: All modules (public and private)
- **Includes**: Type signatures and implementations
- **Purpose**: Full package representation for processing
- **Version 1 note**: Modules stored as objects with `{"name": ..., "def": [accessLevel, moduleDefinition]}`

### Package Specification

Public interface of a package.

- **Contains**: Only publicly exposed modules
- **Includes**: Only type signatures, no implementations
- **Purpose**: Dependency interface

## Module Structure Details

### Module Entry (Version 1 specific)

In version 1, modules use an object structure with explicit name and def fields:

```yaml
ModuleEntry:
  type: object
  required: ["name", "def"]
  properties:
    name:
      $ref: "#/definitions/ModuleName"
    def:
      type: array
      minItems: 2
      maxItems: 2
      items:
        - $ref: "#/definitions/AccessLevel"
        - $ref: "#/definitions/ModuleDefinition"
```

### Module Definition

Complete implementation of a module.

- **Contains**: All types and values (public and private) with implementations
- **Structure**: Dictionary of type names to type definitions, and value names to value definitions
- **Purpose**: Complete module implementation

### Module Specification

Public interface of a module.

- **Contains**: Only publicly exposed types and values
- **Includes**: Type signatures only, no implementations
- **Purpose**: Module's public API

## Type System

The type system is based on functional programming principles, supporting:

**Version 1 note**: All type tags are **lowercase** in version 1.

### Type Expressions

#### variable

Represents a type variable (generic parameter).

- **Structure**: `["variable", attributes, name]`
- **Example**: The `a` in `List a`
- **Purpose**: Enables polymorphic types

```yaml
VariableType:
  type: array
  minItems: 3
  maxItems: 3
  items:
    - const: "variable"
    - $ref: "#/definitions/Attributes"
    - $ref: "#/definitions/Name"
```

#### reference

Reference to another type or type alias.

- **Structure**: `["reference", attributes, fqName, typeArgs]`
- **Examples**: `String`, `List Int`, `Maybe a`
- **Purpose**: References built-in types, custom types, or type aliases

```yaml
ReferenceType:
  type: array
  minItems: 4
  maxItems: 4
  items:
    - const: "reference"
    - $ref: "#/definitions/Attributes"
    - $ref: "#/definitions/FQName"
    - type: array
      items:
        $ref: "#/definitions/Type"
```

#### tuple

Composition of multiple types in fixed order.

- **Structure**: `["tuple", attributes, elementTypes]`
- **Example**: `(Int, String, Bool)`
- **Purpose**: Product types with positional access

#### record

Composition of named fields with types.

- **Structure**: `["record", attributes, fields]`
- **Example**: `{firstName: String, age: Int}`
- **Purpose**: Product types with named field access
- **Note**: All fields are required

#### function

Function type representation.

- **Structure**: `["function", attributes, argType, returnType]`
- **Example**: `Int -> String`
- **Purpose**: Represents function and lambda types
- **Note**: Multi-argument functions use currying (nested function types)

### Type Specifications

#### type_alias_specification

An alias for another type.

- **Structure**: `["type_alias_specification", typeParams, aliasedType]`
- **Example**: `type alias UserId = String`
- **Purpose**: Meaningful name for type expression

#### custom_type_specification

Tagged union type (sum type).

- **Structure**: `["custom_type_specification", typeParams, constructors]`
- **Example**: `type Result e a = Ok a | Err e`
- **Purpose**: Choice between multiple alternatives

#### opaque_type_specification

Type with unknown structure.

- **Structure**: `["opaque_type_specification", typeParams]`
- **Characteristics**: Structure hidden, no automatic serialization
- **Purpose**: Encapsulates implementation details

## Value System

All data and logic in Morphir are represented as value expressions.

**Version 1 note**: All value tags are **lowercase** in version 1.

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

**Version 1 note**: All pattern tags are **lowercase** in version 1.

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

**Version 1 note**: All literal tags are **lowercase** in version 1.

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

## Migration from Version 1

When migrating from version 1 to version 2 or 3:

1. **Capitalize distribution tag**: `"library"` → `"Library"`
2. **Capitalize access control**: `"public"` → `"Public"`, `"private"` → `"Private"`
3. **Update module structure**: Convert `{"name": ..., "def": ...}` to `[modulePath, accessControlled]`
4. **Capitalize type tags**: `"variable"` → `"Variable"`, etc.
5. **For version 3**: Also capitalize value and pattern tags

## Full Schema

For the complete schema definition, see the [full schema page](./full/).

## References

- [Morphir IR Specification](../../morphir-ir-specification/)
- [Schema Version 2](../v2/)
- [Schema Version 3](../v3/)

