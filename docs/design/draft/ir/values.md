---
title: Values Module
sidebar_label: Values
sidebar_position: 4
---

# Values Module

> **Status:** `Hole` stays a value expression; `Native` and `External` are removed from it and are definition bodies only ([decision 0008](../../../../kb/bundles/morphir/morphir-ir/decisions/0008-hole-is-an-expression-native-and-external-are-definition-bodies.md)). Bare arrays are lists and bare scalars are literals at value position ([decision 0009](../../../../kb/bundles/morphir/morphir-ir/decisions/0009-bare-arrays-are-lists-and-bare-scalars-are-literals-at-value-position.md)).

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

  /// Integer (arbitrary precision in IR, includes negatives)
  IntegerLiteral(value: Int)

  /// Floating-point
  FloatLiteral(value: Float)

  /// Arbitrary-precision decimal (stored as string for precision)
  DecimalLiteral(value: String)
}
```

### Migration from v1/v2/v3

| v1/v2/v3 | v4 | Notes |
|----------|----|----|
| `WholeNumberLiteral` | `IntegerLiteral` | **Breaking change**: Renamed for correctness (whole numbers are non-negative; integers include negatives) |

Decoders should accept both `WholeNumberLiteral` and `IntegerLiteral` for backwards compatibility. V4 encoders should output `IntegerLiteral`.

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

  /// External FFI: per-target bindings with an optional fallback body
  ExternalBody(
    input_types: List(#(Name, Type(attributes))),
    output_type: Type(attributes),
    externals: List(ExternalBinding),
    body: Option(Value(attributes)),
  )

  /// Incomplete definition (v4 - best-effort support)
  IncompleteBody(
    input_types: List(#(Name, Type(attributes))),
    output_type: Option(Type(attributes)),
    incompleteness: Incompleteness,
    partial_body: Option(Value(attributes)),
  )
}

/// One target's binding for an external operation
pub type ExternalBinding {
  ExternalBinding(target_platform: String, external_name: String)
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
    annotations: List(Annotation),
    inputs: List(#(Name, Type(attributes))),
    output: Type(attributes),
  )
}
```

## JSON Serialization Examples

### Literal Examples

V4 follows a **permissive input, canonical output** policy for Literals.

#### Literal (within LiteralValue or LiteralPattern)

| Literal Type | Canonical | Compact | Notes |
|--------------|-----------|---------|-------|
| BoolLiteral | `{ "BoolLiteral": { "value": true } }` | `{ "BoolLiteral": true }` | |
| StringLiteral | `{ "StringLiteral": { "value": "hello" } }` | `{ "StringLiteral": "hello" }` | |
| IntegerLiteral | `{ "IntegerLiteral": { "value": 42 } }` | `{ "IntegerLiteral": 42 }` | Renamed from WholeNumberLiteral |
| FloatLiteral | `{ "FloatLiteral": { "value": 3.14 } }` | `{ "FloatLiteral": 3.14 }` | |
| DecimalLiteral | `{ "DecimalLiteral": { "value": "123.456" } }` | `{ "DecimalLiteral": "123.456" }` | String for precision |
| CharLiteral | `{ "CharLiteral": { "value": "A" } }` | `{ "CharLiteral": "A" }` | |

#### LiteralValue (Value expression wrapping a Literal)

| Format | Example | Notes |
|--------|---------|-------|
| **Canonical** | `{ "Literal": { "IntegerLiteral": 42 } }` | Compact literal inside |
| Expanded | `{ "Literal": { "literal": { "IntegerLiteral": { "value": 42 } } } }` | With attributes |
| With attributes | `{ "Literal": { "attributes": {...}, "literal": {...} } }` | Full form |

```json
// Canonical forms (encoders should output these)
{ "BoolLiteral": true }
{ "StringLiteral": "hello world" }
{ "IntegerLiteral": 42 }
{ "FloatLiteral": 3.14159 }
{ "DecimalLiteral": "123456789.987654321" }
{ "CharLiteral": "A" }

// Expanded forms (accepted)
{ "BoolLiteral": { "value": true } }
{ "StringLiteral": { "value": "hello world" } }
{ "IntegerLiteral": { "value": 42 } }
{ "FloatLiteral": { "value": 3.14159 } }
{ "DecimalLiteral": { "value": "123456789.987654321" } }
{ "CharLiteral": { "value": "A" } }

// Legacy (accepted for backwards compatibility)
{ "WholeNumberLiteral": 42 }
{ "WholeNumberLiteral": { "value": 42 } }
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

V4 follows a **permissive input, canonical output** policy for TuplePattern.

| Format | Example | Notes |
|--------|---------|-------|
| Bare array | `[pattern1, pattern2, ...]` | Compact, unambiguous |
| **Canonical** | `{ "TuplePattern": [pattern1, pattern2, ...] }` | Wrapper with array |
| Expanded | `{ "TuplePattern": { "patterns": [pattern1, ...] } }` | Wrapper with object |

:::note
Bare arrays are unambiguous for TuplePattern because no other pattern type uses bare arrays at the top level.
:::

```json
// Bare array (most compact, accepted)
[
  { "AsPattern": { "a": { "WildcardPattern": {} } } },
  { "AsPattern": { "b": { "WildcardPattern": {} } } }
]

// Canonical (encoders should output this)
{
  "TuplePattern": [
    { "AsPattern": { "a": { "WildcardPattern": {} } } },
    { "AsPattern": { "b": { "WildcardPattern": {} } } }
  ]
}

// Expanded form (accepted)
{
  "TuplePattern": {
    "patterns": [
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
    "constructor": "morphir/SDK:maybe#just",
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

V4 follows a **permissive input, canonical output** policy for LiteralPattern.

| Format | Example | Notes |
|--------|---------|-------|
| **Ultra-compact** | `{ "LiteralPattern": 42 }` | Direct primitive value |
| Canonical | `{ "LiteralPattern": { "IntegerLiteral": 42 } }` | Compact literal |
| Expanded | `{ "LiteralPattern": { "literal": { "IntegerLiteral": { "value": 42 } } } }` | Full form |

```json
// Ultra-compact (most ergonomic)
{ "LiteralPattern": 42 }
{ "LiteralPattern": "hello" }
{ "LiteralPattern": true }

// Canonical (encoders should output this)
{ "LiteralPattern": { "IntegerLiteral": 42 } }
{ "LiteralPattern": { "StringLiteral": "hello" } }
{ "LiteralPattern": { "BoolLiteral": true } }

// Expanded form (accepted)
{ "LiteralPattern": { "literal": { "IntegerLiteral": { "value": 42 } } } }
```

### Value Shorthand

V4 supports compact shorthand for value expressions when attributes are empty.

| Type | Shorthand | Canonical | Notes |
|------|-----------|-----------|-------|
| Bool | `true` | `{"Literal": {"BoolLiteral": true}}` | |
| Number | `42` | `{"Literal": {"IntegerLiteral": 42}}` | |
| Reference | `"pkg:mod#val"` | `{"Reference": "pkg:mod#val"}` | If string matches FQName pattern |
| Variable | `"name"` | `{"Variable": "name"}` | If string matches Name pattern |
| List | `[v1, v2]` | `{"List": [v1, v2]}` | |

:::note Disambiguation
- Strings are first checked against the **FQName** pattern.
- If it doesn't match, it's checked against the **Name** pattern for a `Variable`.
- **String Literals** and **Tuples** must always use explicit wrappers to avoid ambiguity.
:::

#### Value Expression Examples

#### Literal

```json
{
  "Literal": {
    "literal": { "IntegerLiteral": { "value": 42 } }
  }
}
```

#### Variable

```json
{ "Variable": { "name": "user-name" } }
```

#### Reference

```json
{ "Reference": { "fqname": "morphir/SDK:list#map" } }
```

#### Constructor

```json
{ "Constructor": { "fqname": "morphir/SDK:maybe#just" } }
```

#### Tuple (TupleValue)

V4 follows a **permissive input, canonical output** policy for TupleValue.

| Format | Example | Notes |
|--------|---------|-------|
| **Canonical** | `{ "Tuple": [value1, value2, ...] }` | Wrapper with array |
| Expanded | `{ "Tuple": { "elements": [value1, ...] } }` | Wrapper with object |

:::warning
A Tuple always carries its wrapper. A bare array at value position is a List (decision 0009), so `[value1, value2]` on its own never decodes to a Tuple.
:::

```json
// Canonical (encoders should output this)
{
  "Tuple": [
    { "Literal": { "IntegerLiteral": 1 } },
    { "Literal": { "StringLiteral": "hello" } }
  ]
}

// Expanded form (accepted)
{
  "Tuple": {
    "elements": [
      { "Literal": { "IntegerLiteral": 1 } },
      { "Literal": { "StringLiteral": "hello" } }
    ]
  }
}
```

#### List (ListValue)

V4 follows a **permissive input, canonical output** policy for ListValue.

| Format | Example | Notes |
|--------|---------|-------|
| **Canonical** | `{ "List": [value1, value2, ...] }` | Wrapper with array |
| Expanded | `{ "List": { "items": [value1, ...] } }` | Wrapper with object |
| Shorthand | `[value1, value2, ...]` | Bare array |

:::note
A bare array at value position is a List (decision 0009). There is no ambiguity with Tuple, because a Tuple always carries its wrapper. Writers still emit the canonical wrapped form.
:::

```json
// Canonical (encoders should output this)
{
  "List": [
    { "Literal": { "IntegerLiteral": 1 } },
    { "Literal": { "IntegerLiteral": 2 } }
  ]
}

// Expanded form (accepted)
{
  "List": {
    "items": [
      { "Literal": { "IntegerLiteral": 1 } },
      { "Literal": { "IntegerLiteral": 2 } }
    ]
  }
}
```

#### Record (fields as object keys, sorted alphabetically)

```json
{
  "Record": {
    "fields": {
      "age": { "Literal": { "literal": { "IntegerLiteral": { "value": 30 } } } },
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
    "function": { "Reference": { "fqname": "morphir/SDK:list#map" } },
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
            "function": { "Reference": { "fqname": "morphir/SDK:basics#add" } },
            "argument": { "Variable": { "name": "x" } }
          }
        },
        "argument": { "Literal": { "literal": { "IntegerLiteral": { "value": 1 } } } }
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
          "outputType": { "Reference": { "fqname": "morphir/SDK:basics#int" } },
          "body": { "Literal": { "literal": { "IntegerLiteral": { "value": 42 } } } }
        }
      },
      "inValue": {
        "Apply": {
          "function": {
            "Apply": {
              "function": { "Reference": { "fqname": "morphir/SDK:basics#add" } },
              "argument": { "Variable": { "name": "x" } }
            }
          },
          "argument": { "Literal": { "literal": { "IntegerLiteral": { "value": 1 } } } }
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
          "inputTypes": [["n", { "Reference": { "fqname": "morphir/SDK:basics#int" } }]],
          "outputType": { "Reference": { "fqname": "morphir/SDK:basics#bool" } },
          "body": { "Variable": { "name": "..." } }
        }
      },
      "is-odd": {
        "ExpressionBody": {
          "inputTypes": [["n", { "Reference": { "fqname": "morphir/SDK:basics#int" } }]],
          "outputType": { "Reference": { "fqname": "morphir/SDK:basics#bool" } },
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
        { "ConstructorPattern": { "constructor": "morphir/SDK:maybe#just", "args": [{ "AsPattern": { "v": { "WildcardPattern": {} } } }] } },
        { "Variable": { "name": "v" } }
      ],
      [
        { "ConstructorPattern": { "constructor": "morphir/SDK:maybe#nothing" } },
        { "Literal": { "literal": { "IntegerLiteral": { "value": 0 } } } }
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
      "age": { "Literal": { "literal": { "IntegerLiteral": { "value": 31 } } } }
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
    "expectedType": { "Reference": { "fqname": "morphir/SDK:basics#int" } }
  }
}
```

Decision 0008 removes `Native` and `External` as value expressions. A native or foreign operation is always a
definition (`NativeBody` or `ExternalBody`); every use site is a `Reference` to it.

### Value Definition Examples

#### ExpressionBody

Input names as keys:

```json
{
  "ExpressionBody": {
    "inputTypes": {
      "x": { "Reference": { "fqname": "morphir/SDK:basics#int" } }
    },
    "outputType": { "Reference": { "fqname": "morphir/SDK:basics#int" } },
    "body": {
      "Apply": {
        "function": {
          "Apply": {
            "function": { "Reference": { "fqname": "morphir/SDK:basics#add" } },
            "argument": { "Variable": { "name": "x" } }
          }
        },
        "argument": { "Literal": { "literal": { "IntegerLiteral": { "value": 1 } } } }
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
      "a": { "Reference": { "fqname": "morphir/SDK:basics#int" } },
      "b": { "Reference": { "fqname": "morphir/SDK:basics#int" } }
    },
    "outputType": { "Reference": { "fqname": "morphir/SDK:basics#int" } },
    "nativeInfo": {
      "hint": { "Arithmetic": {} }
    }
  }
}
```

#### ExternalBody (external operation, two bindings and a fallback)

```json
{
  "ExternalBody": {
    "inputTypes": {
      "x": { "Reference": { "fqname": "morphir/SDK:basics#int" } }
    },
    "outputType": { "Reference": { "fqname": "morphir/SDK:basics#int" } },
    "externals": [
      { "targetPlatform": "erlang", "externalName": "math:abs" },
      { "targetPlatform": "javascript", "externalName": "Math.abs" }
    ],
    "body": { "Variable": { "name": "x" } }
  }
}
```

#### ValueSpecification (signature only)

```json
{
  "ValueSpecification": {
    "inputs": {
      "x": { "Reference": { "fqname": "morphir/SDK:basics#int" } },
      "y": { "Reference": { "fqname": "morphir/SDK:basics#int" } }
    },
    "output": { "Reference": { "fqname": "morphir/SDK:basics#int" } }
  }
}
```
