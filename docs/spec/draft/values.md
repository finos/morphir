---
title: "Value System"
description: "Specification for the Morphir Value System in IR v4"
---

# Value System

Values represent both data and logic in Morphir. All computations are expressed as value expressions.

## Value Attributes

In IR v4, values no longer use a generic attribute parameter. Each value node contains a `ValueAttributes` structure.

**ValueAttributes** contains:
- **source**: Optional source code location
- **inferredType**: Optional inferred type of the value
- **extensions**: A dictionary of extension data

## Value Expressions

### Literal

A literal constant value.

- **Structure**: `Literal attributes literal`

### Constructor

Reference to a custom type constructor.

- **Structure**: `Constructor attributes fqName`

### Tuple

A tuple value with multiple elements.

- **Structure**: `Tuple attributes elements`

### List

A list of values.

- **Structure**: `List attributes elements`

### Record

A record value with named fields.

- **Structure**: `Record attributes fields`

### Variable

Reference to a variable in scope.

- **Structure**: `Variable attributes name`

### Reference

Reference to a defined value (function or constant).

- **Structure**: `Reference attributes fqName`

### Field

Field access on a record.

- **Structure**: `Field attributes recordExpression fieldName`

### FieldFunction

A function that extracts a field.

- **Structure**: `FieldFunction attributes fieldName`

### Apply

Function application.

- **Structure**: `Apply attributes function argument`

### Lambda

Anonymous function (lambda abstraction).

- **Structure**: `Lambda attributes pattern body`

### LetDefinition

A let binding introducing a single value.

- **Structure**: `LetDefinition attributes name definition body`

### LetRecursion

Mutually recursive let bindings.

- **Structure**: `LetRecursion attributes bindings body`

### Destructure

Pattern-based destructuring.

- **Structure**: `Destructure attributes pattern valueToDestructure body`

### IfThenElse

Conditional expression.

- **Structure**: `IfThenElse attributes condition thenBranch elseBranch`

### PatternMatch

Pattern matching with multiple cases.

- **Structure**: `PatternMatch attributes valueToMatch cases`

### UpdateRecord

Record update expression.

- **Structure**: `UpdateRecord attributes recordToUpdate fieldsToUpdate`

### Unit

The unit value.

- **Structure**: `Unit attributes`

## Patterns

Patterns are used for destructuring and filtering values.

- **WildcardPattern**: `WildcardPattern attributes`
- **AsPattern**: `AsPattern attributes pattern name`
- **TuplePattern**: `TuplePattern attributes patterns`
- **ConstructorPattern**: `ConstructorPattern attributes fqName patterns`
- **EmptyListPattern**: `EmptyListPattern attributes`
- **HeadTailPattern**: `HeadTailPattern attributes headPattern tailPattern`
- **LiteralPattern**: `LiteralPattern attributes literal`
- **UnitPattern**: `UnitPattern attributes`

## Value Definitions

A **Value Definition** provides the complete implementation of a value or function.

- **Structure**:
  - `inputTypes`: List of parameters with their attributes and types
  - `outputType`: Return type
  - `body`: The value expression implementing the logic
