---
title: Values Module
sidebar_label: Values
sidebar_position: 4
---

# Values Module

This module defines the value expressions, literals, patterns, and value definitions for Morphir IR.

## Literals

Literal constant values.

```gleam
// === literal.gleam ===

/// Literal constant values
pub type Literal {
  /// Boolean: true, false
  BoolLiteral(value: Bool)

  /// Single character
  CharLiteral(value: String)

  /// Text string
  StringLiteral(value: String)

  /// Integer (arbitrary precision in IR)
  WholeNumberLiteral(value: Int)

  /// Floating-point
  FloatLiteral(value: Float)

  /// Arbitrary-precision decimal (stored as string for precision)
  DecimalLiteral(value: String)
}
```

## Patterns

Patterns for destructuring and matching.

```gleam
// === pattern.gleam ===

/// Patterns for destructuring and matching
pub type Pattern(attributes) {
  /// Matches anything, binds nothing: `_`
  WildcardPattern(attributes: attributes)

  /// Binds a name while matching: `x` or `(a, b) as pair`
  AsPattern(
    attributes: attributes,
    pattern: Pattern(attributes),
    name: Name,
  )

  /// Matches tuple: `(a, b, c)`
  TuplePattern(
    attributes: attributes,
    elements: List(Pattern(attributes)),
  )

  /// Matches constructor: `Just x`, `Nothing`
  ConstructorPattern(
    attributes: attributes,
    constructor: FQName,
    args: List(Pattern(attributes)),
  )

  /// Matches empty list: `[]`
  EmptyListPattern(attributes: attributes)

  /// Matches head :: tail: `x :: xs`
  HeadTailPattern(
    attributes: attributes,
    head: Pattern(attributes),
    tail: Pattern(attributes),
  )

  /// Matches literal: `42`, `"hello"`, `True`
  LiteralPattern(attributes: attributes, literal: Literal)

  /// Matches unit: `()`
  UnitPattern(attributes: attributes)
}
```

## Value Expressions

Value expressions form the core computation language.

```gleam
// === value.gleam ===

/// Value expressions - the core computation language
pub type Value(attributes) {
  // ===== Literals & Data Construction =====

  /// Literal constant
  Literal(attributes: attributes, literal: Literal)

  /// Constructor reference: `Just`, `Nothing`
  Constructor(attributes: attributes, fqname: FQName)

  /// Tuple: `(1, "hello", True)`
  Tuple(attributes: attributes, elements: List(Value(attributes)))

  /// List: `[1, 2, 3]`
  List(attributes: attributes, items: List(Value(attributes)))

  /// Record: `{ name = "Alice", age = 30 }`
  /// Field order does not affect equality
  Record(attributes: attributes, fields: Dict(Name, Value(attributes)))

  /// Unit value: `()`
  Unit(attributes: attributes)

  // ===== References =====

  /// Variable reference: `x`, `myValue`
  Variable(attributes: attributes, name: Name)

  /// Reference to defined value: `List.map`, `MyModule.myFunction`
  Reference(attributes: attributes, fqname: FQName)

  // ===== Field Access =====

  /// Field access: `record.fieldName`
  Field(
    attributes: attributes,
    record: Value(attributes),
    field_name: Name,
  )

  /// Field accessor function: `.fieldName`
  FieldFunction(attributes: attributes, field_name: Name)

  // ===== Function Application =====

  /// Function application: `f x` (curried, one arg at a time)
  Apply(
    attributes: attributes,
    function: Value(attributes),
    argument: Value(attributes),
  )

  /// Lambda: `\x -> x + 1`
  Lambda(
    attributes: attributes,
    argument_pattern: Pattern(attributes),
    body: Value(attributes),
  )

  // ===== Let Bindings =====

  /// Single let binding: `let x = 1 in x + 1`
  LetDefinition(
    attributes: attributes,
    name: Name,
    definition: ValueDefinitionBody(attributes),
    in_value: Value(attributes),
  )

  /// Mutually recursive let: `let f = ... g ...; g = ... f ... in ...`
  LetRecursion(
    attributes: attributes,
    bindings: Dict(Name, ValueDefinitionBody(attributes)),
    in_value: Value(attributes),
  )

  /// Pattern destructuring: `let (a, b) = tuple in a + b`
  Destructure(
    attributes: attributes,
    pattern: Pattern(attributes),
    value_to_destructure: Value(attributes),
    in_value: Value(attributes),
  )

  // ===== Control Flow =====

  /// Conditional: `if cond then a else b`
  IfThenElse(
    attributes: attributes,
    condition: Value(attributes),
    then_branch: Value(attributes),
    else_branch: Value(attributes),
  )

  /// Pattern match: `case x of ...`
  PatternMatch(
    attributes: attributes,
    subject: Value(attributes),
    cases: List(#(Pattern(attributes), Value(attributes))),
  )

  // ===== Record Update =====

  /// Record update: `{ record | field = newValue }`
  /// Field order does not affect equality
  UpdateRecord(
    attributes: attributes,
    record: Value(attributes),
    updates: Dict(Name, Value(attributes)),
  )

  // ===== Special Values (v4 additions) =====

  /// Incomplete/broken reference (for best-effort generation)
  Hole(
    attributes: attributes,
    reason: HoleReason,
    expected_type: Option(Type(attributes)),
  )

  /// Native platform operation (no IR body)
  Native(
    attributes: attributes,
    fqname: FQName,
    native_info: NativeInfo,
  )

  /// External FFI call
  External(
    attributes: attributes,
    external_name: String,
    target_platform: String,
  )
}

/// Information about native operations
pub type NativeInfo {
  NativeInfo(
    hint: NativeHint,
    description: Option(String),
  )
}

pub type NativeHint {
  /// Basic arithmetic/logic operation
  Arithmetic
  /// Comparison operation
  Comparison
  /// String operation
  StringOp
  /// Collection operation (map, filter, fold, etc.)
  CollectionOp
  /// Platform-specific operation
  PlatformSpecific(platform: String)
}
```

## Value Definitions

```gleam
// === value_definition.gleam ===

/// The body of a value definition (used in let bindings and top-level definitions)
pub type ValueDefinitionBody(attributes) {
  /// Normal IR expression body
  ExpressionBody(
    input_types: List(#(Name, Type(attributes))),
    output_type: Type(attributes),
    body: Value(attributes),
  )

  /// Native/builtin operation (no IR body)
  NativeBody(
    input_types: List(#(Name, Type(attributes))),
    output_type: Type(attributes),
    native_info: NativeInfo,
  )

  /// External FFI (no IR body)
  ExternalBody(
    input_types: List(#(Name, Type(attributes))),
    output_type: Type(attributes),
    external_name: String,
    target_platform: String,
  )

  /// Incomplete definition (v4 - best-effort support)
  IncompleteBody(
    input_types: List(#(Name, Type(attributes))),
    output_type: Option(Type(attributes)),
    incompleteness: Incompleteness,
    partial_body: Option(Value(attributes)),
  )
}

/// Top-level value definition (in a module)
pub type ValueDefinition(attributes) {
  ValueDefinition(
    body: AccessControlled(ValueDefinitionBody(attributes)),
  )
}

/// Value specification - the public interface (signature only, no implementation)
pub type ValueSpecification(attributes) {
  ValueSpecification(
    inputs: List(#(Name, Type(attributes))),
    output: Type(attributes),
  )
}
```

## JSON Serialization Examples

### Literal Examples

```json
{ "BoolLiteral": { "value": true } }
{ "StringLiteral": { "value": "hello world" } }
{ "WholeNumberLiteral": { "value": 42 } }
{ "FloatLiteral": { "value": 3.14159 } }
{ "DecimalLiteral": { "value": "123456789.987654321" } }
{ "CharLiteral": { "value": "A" } }
```

### Pattern Examples

#### WildcardPattern

```json
{ "WildcardPattern": {} }
```

#### AsPattern (variable binding)

Name becomes the key, pattern is the value:

```json
{ "AsPattern": { "x": { "WildcardPattern": {} } } }
```

Simple variable binding (most common case):

```json
{ "AsPattern": { "user-name": { "WildcardPattern": {} } } }
```

#### TuplePattern

```json
{
  "TuplePattern": {
    "elements": [
      { "AsPattern": { "a": { "WildcardPattern": {} } } },
      { "AsPattern": { "b": { "WildcardPattern": {} } } }
    ]
  }
}
```

#### ConstructorPattern

```json
{
  "ConstructorPattern": {
    "constructor": "morphir/sdk:maybe#just",
    "args": [
      { "AsPattern": { "value": { "WildcardPattern": {} } } }
    ]
  }
}
```

#### HeadTailPattern

```json
{
  "HeadTailPattern": {
    "head": { "AsPattern": { "x": { "WildcardPattern": {} } } },
    "tail": { "AsPattern": { "xs": { "WildcardPattern": {} } } }
  }
}
```

#### LiteralPattern

```json
{ "LiteralPattern": { "literal": { "WholeNumberLiteral": { "value": 42 } } } }
```

### Value Expression Examples

#### Literal

```json
{
  "Literal": {
    "literal": { "WholeNumberLiteral": { "value": 42 } }
  }
}
```

#### Variable

```json
{ "Variable": { "name": "user-name" } }
```

#### Reference

```json
{ "Reference": { "fqname": "morphir/sdk:list#map" } }
```

#### Constructor

```json
{ "Constructor": { "fqname": "morphir/sdk:maybe#just" } }
```

#### Tuple

```json
{
  "Tuple": {
    "elements": [
      { "Literal": { "literal": { "WholeNumberLiteral": { "value": 1 } } } },
      { "Literal": { "literal": { "StringLiteral": { "value": "hello" } } } }
    ]
  }
}
```

#### List

```json
{
  "List": {
    "items": [
      { "Literal": { "literal": { "WholeNumberLiteral": { "value": 1 } } } },
      { "Literal": { "literal": { "WholeNumberLiteral": { "value": 2 } } } }
    ]
  }
}
```

#### Record (fields as object keys, sorted alphabetically)

```json
{
  "Record": {
    "fields": {
      "age": { "Literal": { "literal": { "WholeNumberLiteral": { "value": 30 } } } },
      "name": { "Literal": { "literal": { "StringLiteral": { "value": "Alice" } } } }
    }
  }
}
```

#### Field Access

```json
{
  "Field": {
    "record": { "Variable": { "name": "user" } },
    "fieldName": "email"
  }
}
```

#### FieldFunction

```json
{ "FieldFunction": { "fieldName": "email" } }
```

#### Apply (function application)

```json
{
  "Apply": {
    "function": { "Reference": { "fqname": "morphir/sdk:list#map" } },
    "argument": { "Variable": { "name": "transform" } }
  }
}
```

#### Lambda

```json
{
  "Lambda": {
    "argumentPattern": { "AsPattern": { "x": { "WildcardPattern": {} } } },
    "body": {
      "Apply": {
        "function": {
          "Apply": {
            "function": { "Reference": { "fqname": "morphir/sdk:basics#add" } },
            "argument": { "Variable": { "name": "x" } }
          }
        },
        "argument": { "Literal": { "literal": { "WholeNumberLiteral": { "value": 1 } } } }
      }
    }
  }
}
```

#### LetDefinition

Name becomes the key:

```json
{
  "LetDefinition": {
    "x": {
      "def": {
        "ExpressionBody": {
          "outputType": { "Reference": { "fqname": "morphir/sdk:basics#int" } },
          "body": { "Literal": { "literal": { "WholeNumberLiteral": { "value": 42 } } } }
        }
      },
      "inValue": {
        "Apply": {
          "function": {
            "Apply": {
              "function": { "Reference": { "fqname": "morphir/sdk:basics#add" } },
              "argument": { "Variable": { "name": "x" } }
            }
          },
          "argument": { "Literal": { "literal": { "WholeNumberLiteral": { "value": 1 } } } }
        }
      }
    }
  }
}
```

#### LetRecursion

Binding names as keys:

```json
{
  "LetRecursion": {
    "bindings": {
      "is-even": {
        "ExpressionBody": {
          "inputTypes": [["n", { "Reference": { "fqname": "morphir/sdk:basics#int" } }]],
          "outputType": { "Reference": { "fqname": "morphir/sdk:basics#bool" } },
          "body": { "Variable": { "name": "..." } }
        }
      },
      "is-odd": {
        "ExpressionBody": {
          "inputTypes": [["n", { "Reference": { "fqname": "morphir/sdk:basics#int" } }]],
          "outputType": { "Reference": { "fqname": "morphir/sdk:basics#bool" } },
          "body": { "Variable": { "name": "..." } }
        }
      }
    },
    "inValue": { "Variable": { "name": "is-even" } }
  }
}
```

#### IfThenElse

```json
{
  "IfThenElse": {
    "condition": { "Variable": { "name": "is-valid" } },
    "thenBranch": { "Literal": { "literal": { "StringLiteral": { "value": "yes" } } } },
    "elseBranch": { "Literal": { "literal": { "StringLiteral": { "value": "no" } } } }
  }
}
```

#### PatternMatch

```json
{
  "PatternMatch": {
    "subject": { "Variable": { "name": "maybe-value" } },
    "cases": [
      [
        { "ConstructorPattern": { "constructor": "morphir/sdk:maybe#just", "args": [{ "AsPattern": { "v": { "WildcardPattern": {} } } }] } },
        { "Variable": { "name": "v" } }
      ],
      [
        { "ConstructorPattern": { "constructor": "morphir/sdk:maybe#nothing" } },
        { "Literal": { "literal": { "WholeNumberLiteral": { "value": 0 } } } }
      ]
    ]
  }
}
```

#### UpdateRecord

```json
{
  "UpdateRecord": {
    "record": { "Variable": { "name": "user" } },
    "updates": {
      "age": { "Literal": { "literal": { "WholeNumberLiteral": { "value": 31 } } } }
    }
  }
}
```

#### Hole (v4 - incomplete value)

```json
{
  "Hole": {
    "reason": {
      "UnresolvedReference": { "target": "my-org/project:module#deleted-function" }
    },
    "expectedType": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
  }
}
```

#### Native (v4 - platform operation)

```json
{
  "Native": {
    "fqname": "morphir/sdk:basics#add",
    "nativeInfo": {
      "hint": { "Arithmetic": {} },
      "description": "Integer addition"
    }
  }
}
```

### Value Definition Examples

#### ExpressionBody

Input names as keys:

```json
{
  "ExpressionBody": {
    "inputTypes": {
      "x": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
    },
    "outputType": { "Reference": { "fqname": "morphir/sdk:basics#int" } },
    "body": {
      "Apply": {
        "function": {
          "Apply": {
            "function": { "Reference": { "fqname": "morphir/sdk:basics#add" } },
            "argument": { "Variable": { "name": "x" } }
          }
        },
        "argument": { "Literal": { "literal": { "WholeNumberLiteral": { "value": 1 } } } }
      }
    }
  }
}
```

#### NativeBody (builtin operation)

```json
{
  "NativeBody": {
    "inputTypes": {
      "a": { "Reference": { "fqname": "morphir/sdk:basics#int" } },
      "b": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
    },
    "outputType": { "Reference": { "fqname": "morphir/sdk:basics#int" } },
    "nativeInfo": {
      "hint": { "Arithmetic": {} }
    }
  }
}
```

#### ValueSpecification (signature only)

```json
{
  "ValueSpecification": {
    "inputs": {
      "x": { "Reference": { "fqname": "morphir/sdk:basics#int" } },
      "y": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
    },
    "output": { "Reference": { "fqname": "morphir/sdk:basics#int" } }
  }
}
```
