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

## Literals

Literal constant values used in value expressions.

- **BoolLiteral**: Boolean value (`true`, `false`)
- **CharLiteral**: Single character
- **StringLiteral**: Text string
- **IntegerLiteral**: Integer (arbitrary precision, includes negatives)
- **FloatLiteral**: Floating-point number
- **DecimalLiteral**: Arbitrary-precision decimal (stored as string for precision)

## Value Expressions

Value expressions use object wrappers to distinguish expression types, with compact inner values where possible.

### Literal

A literal constant value.

- **Structure**: `Literal attributes literal`
- **JSON**: `{"Literal": {"IntLiteral": 42}}` or `{"Literal": {"StringLiteral": "hello"}}`

### Constructor

Reference to a custom type constructor.

- **Structure**: `Constructor attributes fqName`
- **JSON**: `{"Constructor": "morphir/sdk:maybe#just"}`

### Tuple

A tuple value with multiple elements.

- **Structure**: `Tuple attributes elements`
- **JSON**: `{"Tuple": {"elements": [{"Variable": "x"}, {"Literal": {"IntLiteral": 1}}]}}`

### List

A list of values.

- **Structure**: `List attributes elements`
- **JSON**: `{"List": {"items": [{"Literal": {"IntLiteral": 1}}, {"Literal": {"IntLiteral": 2}}]}}`

### Record

A record value with named fields.

- **Structure**: `Record attributes fields`
- **Components**:
  - attributes: `ValueAttributes`
  - fields: Dictionary of field names to values (`Dict Name Value`)
- **Note**: Field order does not affect equality—two records with the same fields in different orders are considered equal
- **JSON (compact)**: `{"Record": {"name": {"Variable": "x"}, "age": {"Literal": {"IntLiteral": 25}}}}`
  - Fields stored directly under `Record` without a wrapper
  - Field names use kebab-case

### Variable

Reference to a variable in scope.

- **Structure**: `Variable attributes name`
- **JSON**: `{"Variable": "x"}` — name directly under Variable

### Reference

Reference to a defined value (function or constant).

- **Structure**: `Reference attributes fqName`
- **JSON**: `{"Reference": "morphir/sdk:basics#add"}` — FQName directly under Reference

### Field

Field access on a record.

- **Structure**: `Field attributes recordExpression fieldName`
- **JSON**: `{"Field": {"target": {"Variable": "record"}, "name": "field-name"}}`

### FieldFunction

A function that extracts a field.

- **Structure**: `FieldFunction attributes fieldName`
- **JSON**: `{"FieldFunction": "field-name"}`

### Apply

Function application.

- **Structure**: `Apply attributes function argument`
- **JSON**: `{"Apply": {"function": {"Reference": "morphir/sdk:basics#add"}, "argument": {"Literal": {"IntLiteral": 1}}}}`

### Lambda

Anonymous function (lambda abstraction).

- **Structure**: `Lambda attributes argumentPattern body`
- **Components**:
  - attributes: `ValueAttributes`
  - argumentPattern: Pattern for the function argument (`Pattern`)
  - body: The function body expression (`Value`)
- **JSON**: `{"Lambda": {"pattern": {"AsPattern": {...}}, "body": {"Variable": "x"}}}`

### LetDefinition

A let binding introducing a single value.

- **Structure**: `LetDefinition attributes name definition body`
- **JSON**: `{"LetDefinition": {"name": "x", "definition": {...}, "in": {...}}}`

### LetRecursion

Mutually recursive let bindings.

- **Structure**: `LetRecursion attributes bindings body`
- **JSON**: `{"LetRecursion": {"definitions": {"f": {...}, "g": {...}}, "in": {...}}}`

### Destructure

Pattern-based destructuring.

- **Structure**: `Destructure attributes pattern valueToDestructure body`
- **JSON**: `{"Destructure": {"pattern": {...}, "value": {...}, "in": {...}}}`

### IfThenElse

Conditional expression.

- **Structure**: `IfThenElse attributes condition thenBranch elseBranch`
- **JSON**: `{"IfThenElse": {"condition": {...}, "then": {...}, "else": {...}}}`

### PatternMatch

Pattern matching with multiple cases.

- **Structure**: `PatternMatch attributes valueToMatch cases`
- **JSON**: `{"PatternMatch": {"value": {...}, "cases": [{...}, {...}]}}`

### UpdateRecord

Record update expression.

- **Structure**: `UpdateRecord attributes recordToUpdate fieldsToUpdate`
- **Components**:
  - attributes: `ValueAttributes`
  - recordToUpdate: The record being updated (`Value`)
  - fieldsToUpdate: Dictionary of field names to new values (`Dict Name Value`)
- **Note**: Field order in updates does not affect equality
- **JSON**: `{"UpdateRecord": {"target": {"Variable": "record"}, "fields": {"name": {"Literal": {"StringLiteral": "new"}}}}}`

### Unit

The unit value.

- **Structure**: `Unit attributes`
- **JSON**: `{"Unit": {}}`

## JSON Serialization Summary

Value expressions use object wrappers to distinguish expression types:

| Value Expression | JSON Format | Example |
|------------------|-------------|---------|
| Variable | `{"Variable": name}` | `{"Variable": "x"}` |
| Reference | `{"Reference": fqname}` | `{"Reference": "morphir/sdk:basics#add"}` |
| Literal | `{"Literal": {...}}` | `{"Literal": {"IntLiteral": 42}}` |
| Constructor | `{"Constructor": fqname}` | `{"Constructor": "morphir/sdk:maybe#just"}` |
| Record | `{"Record": {fields}}` | `{"Record": {"name": {...}}}` |
| Apply | `{"Apply": {...}}` | `{"Apply": {"function": {...}, "argument": {...}}}` |
| Unit | `{"Unit": {}}` | `{"Unit": {}}` |

**Key differences from Type expressions**:
- Value expressions always use object wrappers (e.g., `{"Variable": "x"}`)
- Type expressions can use bare strings for Variables and References without args
- This distinction allows parsers to unambiguously identify expression types in any context

### Hole (v4)

An incomplete or broken reference, enabling best-effort compilation.

- **Structure**: `Hole attributes reason expectedType`
- **Components**:
  - attributes: `ValueAttributes`
  - reason: Why this hole exists (`HoleReason`)
  - expectedType: Optional expected type (`Option Type`)
- **Use cases**:
  - Reference to a deleted/renamed function
  - Placeholder during incremental development
  - Representing compilation errors without failing the entire build

### Native (v4)

A native platform operation with no IR body.

- **Structure**: `Native attributes fqName nativeInfo`
- **Components**:
  - attributes: `ValueAttributes`
  - fqName: Fully-qualified name of the native operation (`FQName`)
  - nativeInfo: Information about the native operation (`NativeInfo`)

### External (v4)

An external FFI (Foreign Function Interface) call.

- **Structure**: `External attributes externalName targetPlatform`
- **Components**:
  - attributes: `ValueAttributes`
  - externalName: Name of the external function (`String`)
  - targetPlatform: Target platform identifier (`String`)

## NativeInfo (v4)

Information about native operations.

- **Structure**: `NativeInfo hint description`
- **Components**:
  - hint: Category of native operation (`NativeHint`)
  - description: Optional human-readable description (`Option String`)

## NativeHint (v4)

Categories of native operations:

- **Arithmetic**: Basic arithmetic/logic operation
- **Comparison**: Comparison operation
- **StringOp**: String operation
- **CollectionOp**: Collection operation (map, filter, fold, etc.)
- **PlatformSpecific**: Platform-specific operation (includes platform identifier)

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

A **Value Definition** provides the complete implementation of a value or function, owned by the defining module. Like type definitions, value definitions can be public or private (controlled via `AccessControlled` wrapper).

**Purpose**: Definitions contain everything needed to:
- Generate executable code
- Perform type checking and inference
- Derive the public specification for dependents

**Access control**: Definitions are wrapped with `AccessControlled` to indicate visibility:
- `Public`: Exposed in the module's specification, callable by dependents
- `Private`: Internal to the module, not visible to dependents

### ValueDefinitionBody

A `ValueDefinition` wraps a `ValueDefinitionBody` with access control. The body can take several forms, supporting different implementation strategies:

#### ExpressionBody

A normal IR expression body.

- **Structure**: `ExpressionBody inputTypes outputType body`
- **Components**:
  - inputTypes: List of parameter names and types (`List (Name, Type)`)
  - outputType: Return type (`Type`)
  - body: The value expression implementing the logic (`Value`)

#### NativeBody (v4)

A native/builtin operation with no IR body.

- **Structure**: `NativeBody inputTypes outputType nativeInfo`
- **Components**:
  - inputTypes: List of parameter names and types (`List (Name, Type)`)
  - outputType: Return type (`Type`)
  - nativeInfo: Information about the native operation (`NativeInfo`)

#### ExternalBody (v4)

An external FFI operation with no IR body.

- **Structure**: `ExternalBody inputTypes outputType externalName targetPlatform`
- **Components**:
  - inputTypes: List of parameter names and types (`List (Name, Type)`)
  - outputType: Return type (`Type`)
  - externalName: Name of the external function (`String`)
  - targetPlatform: Target platform identifier (`String`)

#### IncompleteBody (v4)

An incomplete definition for best-effort support.

- **Structure**: `IncompleteBody inputTypes outputType incompleteness partialBody`
- **Components**:
  - inputTypes: List of parameter names and types (`List (Name, Type)`)
  - outputType: Optional return type (`Option Type`)
  - incompleteness: Reason for incompleteness (`Incompleteness`)
  - partialBody: Optional partial implementation (`Option Value`)

## Value Specifications

A **Value Specification** defines the public interface of a value—the function signature exposed to consumers. Specifications contain only the type signature, never the implementation.

**Purpose**: When module A depends on module B, module A only sees module B's value specifications. This enables:
- Type checking at module boundaries without implementation details
- API documentation generation from signatures
- Separate compilation of dependent modules

**Deriving specifications**: A specification is derived from any `ValueDefinitionBody` by extracting the input types and output type. The implementation details (`body`, `nativeInfo`, `externalName`, etc.) are discarded.

- **Structure**: `ValueSpecification inputs output`
- **Components**:
  - inputs: List of parameter names and types (`List (Name, Type)`)
  - output: Return type (`Type`)

**Note**: All `ValueDefinitionBody` variants (`ExpressionBody`, `NativeBody`, `ExternalBody`, `IncompleteBody`) produce the same `ValueSpecification` structure—consumers cannot distinguish how a value is implemented.
