# Values

Value expressions. At value position a bare string is a Variable or a Reference, a bare boolean or number is a literal, and a bare array is a List (decision 0009); a Tuple always carries its wrapper. Every node has an expanded spelling whose payload starts with `attributes` (decision 0005).

## values-0001: Literal shorthands {node=Value}

```yaml canonical
Literal:
  IntegerLiteral: 42
```

```json canonical
{ "Literal": { "IntegerLiteral": 42 } }
```

```json accepted
{ "Literal": 42 }
```

```json accepted
42
```

```json accepted
{ "Literal": { "IntegerLiteral": { "value": 42 } } }
```

```json accepted
{ "Literal": { "WholeNumberLiteral": 42 } }
```

```json accepted
{ "Literal": { "attributes": {}, "literal": { "IntegerLiteral": 42 } } }
```

## values-0002: Variable and reference shorthands {node=Value}

```yaml canonical
Variable: x
```

```json canonical
{ "Variable": "x" }
```

```json accepted
"x"
```

```json accepted
{ "Variable": { "attributes": {}, "name": "x" } }
```

## values-0003: Reference shorthand {node=Value}

```yaml canonical
Reference: morphir/SDK:basics#add
```

```json canonical
{ "Reference": "morphir/SDK:basics#add" }
```

```json accepted
"morphir/SDK:basics#add"
```

```json accepted
{ "Reference": { "attributes": {}, "fqname": "morphir/SDK:basics#add" } }
```

## values-0004: Apply {node=Value}

```yaml canonical
Apply:
  function:
    Reference: morphir/SDK:basics#negate
  argument:
    Literal:
      IntegerLiteral: 1
```

```json canonical
{ "Apply": { "function": { "Reference": "morphir/SDK:basics#negate" }, "argument": { "Literal": { "IntegerLiteral": 1 } } } }
```

```json accepted
{ "Apply": { "attributes": {}, "function": { "Reference": "morphir/SDK:basics#negate" }, "argument": { "Literal": { "IntegerLiteral": 1 } } } }
```

## values-0005: If-then-else member names {node=Value}

Decision 0006: the schema's `then` and `else` are canonical; the Rust encoder's `thenBranch` and `elseBranch` are accepted for one release. Bead morphir-ir-v4-stabilize.3.

```yaml canonical
IfThenElse:
  condition:
    Literal:
      BoolLiteral: true
  then:
    Literal:
      IntegerLiteral: 1
  else:
    Literal:
      IntegerLiteral: 2
```

```json canonical
{ "IfThenElse": { "condition": { "Literal": { "BoolLiteral": true } }, "then": { "Literal": { "IntegerLiteral": 1 } }, "else": { "Literal": { "IntegerLiteral": 2 } } } }
```

```json accepted
{ "IfThenElse": { "attributes": {}, "condition": { "Literal": { "BoolLiteral": true } }, "then": { "Literal": { "IntegerLiteral": 1 } }, "else": { "Literal": { "IntegerLiteral": 2 } } } }
```

```json accepted warning=legacy_spelling
{ "IfThenElse": { "condition": { "Literal": { "BoolLiteral": true } }, "thenBranch": { "Literal": { "IntegerLiteral": 1 } }, "elseBranch": { "Literal": { "IntegerLiteral": 2 } } } }
```

## values-0006: Field access member names {node=Value}

Decision 0006: `target` and `name`; the older `subject` and `fieldName` are accepted for one release.

```yaml canonical
Field:
  target:
    Variable: record
  name: field-name
```

```json canonical
{ "Field": { "target": { "Variable": "record" }, "name": "field-name" } }
```

```json accepted
{ "Field": { "attributes": {}, "target": { "Variable": "record" }, "name": "field-name" } }
```

```json accepted warning=legacy_spelling
{ "Field": { "subject": { "Variable": "record" }, "fieldName": "field-name" } }
```

## values-0007: Tuple value {node=Value}

Decision 0009: a Tuple always carries its wrapper; a bare array at value position is a List.

```yaml canonical
Tuple:
  - Variable: x
  - Literal:
      IntegerLiteral: 1
```

```json canonical
{ "Tuple": [{ "Variable": "x" }, { "Literal": { "IntegerLiteral": 1 } }] }
```

```json accepted
{ "Tuple": { "elements": [{ "Variable": "x" }, { "Literal": { "IntegerLiteral": 1 } }] } }
```

```json accepted
{ "Tuple": { "attributes": {}, "elements": [{ "Variable": "x" }, { "Literal": { "IntegerLiteral": 1 } }] } }
```

```json rejected expect=List
[{ "Variable": "x" }, { "Literal": { "IntegerLiteral": 1 } }]
```

## values-0008: Bare array and bare scalars at value position {node=Value}

Decision 0009 closed bead morphir-ir-v4-stabilize.4: a bare array is a List, a bare number is an IntegerLiteral or FloatLiteral by its lexeme, and a bare boolean is a BoolLiteral. Writers keep the wrapped forms.

```yaml canonical
List:
  - Literal:
      IntegerLiteral: 1
  - Literal:
      IntegerLiteral: 2
  - Literal:
      IntegerLiteral: 3
```

```json canonical
{ "List": [{ "Literal": { "IntegerLiteral": 1 } }, { "Literal": { "IntegerLiteral": 2 } }, { "Literal": { "IntegerLiteral": 3 } }] }
```

```json accepted
[1, 2, 3]
```

```json accepted
{ "List": [1, 2, 3] }
```

```json accepted
{ "List": { "items": [1, 2, 3] } }
```

```json accepted
{ "List": { "attributes": {}, "items": [1, 2, 3] } }
```

## values-0009: Hole {node=Value}

Decision 0008: Hole stays a value expression with an optional `expectedType`; the Native and External expressions are removed, and a reader refuses them as unknown nodes. Native and external operations are definition bodies (definitions-0007).

```yaml canonical
Hole:
  reason:
    UnresolvedReference:
      target: my-org/project:module#deleted
```

```json canonical
{ "Hole": { "reason": { "UnresolvedReference": { "target": "my-org/project:module#deleted" } } } }
```

```json accepted
{ "Hole": { "attributes": {}, "reason": { "UnresolvedReference": { "target": "my-org/project:module#deleted" } } } }
```

```json rejected diagnostic=unknown_node
{ "Native": { "fqname": "morphir/SDK:basics#add", "nativeInfo": { "hint": { "Arithmetic": {} } } } }
```

```json rejected diagnostic=unknown_node
{ "External": { "externalName": "console.log", "targetPlatform": "javascript" } }
```

## values-0010: Unit value {node=Value}

```yaml canonical
Unit: {}
```

```json canonical
{ "Unit": {} }
```

```json accepted
{ "Unit": { "attributes": {} } }
```

## values-0011: Bare scalars are literals {node=Value}

Decision 0009. A bare `42` is an IntegerLiteral and a bare `true` a BoolLiteral; `4.0` is a FloatLiteral because its lexeme has a point. A bare string is never a StringLiteral (values-0002).

```yaml canonical
Literal:
  BoolLiteral: true
```

```json canonical
{ "Literal": { "BoolLiteral": true } }
```

```json accepted
true
```

## values-0012: Bare number lexemes {node=Value}

```yaml canonical
Literal:
  FloatLiteral: 4.0
```

```json canonical
{ "Literal": { "FloatLiteral": 4.0 } }
```

```json accepted
4.0
```

## values-0013: Record value {node=Value}

Decision 0004 applies to record values too; the direct field map is accepted for the window of decision 0006.

```yaml canonical
Record:
  fields:
    name:
      Variable: x
    age:
      Literal:
        IntegerLiteral: 25
```

```json canonical
{ "Record": { "fields": { "name": { "Variable": "x" }, "age": { "Literal": { "IntegerLiteral": 25 } } } } }
```

```json accepted
{ "Record": { "attributes": {}, "fields": { "name": { "Variable": "x" }, "age": { "Literal": { "IntegerLiteral": 25 } } } } }
```

```json accepted warning=legacy_spelling
{ "Record": { "name": { "Variable": "x" }, "age": { "Literal": { "IntegerLiteral": 25 } } } }
```

## values-0014: Constructor and field function {node=Value}

```yaml canonical
Constructor: morphir/SDK:maybe#just
```

```json canonical
{ "Constructor": "morphir/SDK:maybe#just" }
```

```json accepted
{ "Constructor": { "attributes": {}, "fqname": "morphir/SDK:maybe#just" } }
```

## values-0015: Field function {node=Value}

```yaml canonical
FieldFunction: name
```

```json canonical
{ "FieldFunction": "name" }
```

```json accepted
{ "FieldFunction": { "attributes": {}, "name": "name" } }
```

## values-0016: Lambda {node=Value}

```yaml canonical
Lambda:
  pattern:
    AsPattern:
      pattern:
        WildcardPattern: {}
      name: x
  body:
    Variable: x
```

```json canonical
{ "Lambda": { "pattern": { "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }, "body": { "Variable": "x" } } }
```

```json accepted
{ "Lambda": { "attributes": {}, "pattern": { "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }, "body": { "Variable": "x" } } }
```

## values-0017: Let definition member names {node=Value}

Decision 0006: `name`, `definition`, and `in`; the spec's older `valueName`, `valueDefinition`, and `inValue` are accepted for one release.

```yaml canonical
LetDefinition:
  name: x
  definition:
    ExpressionBody:
      inputTypes: {}
      outputType: morphir/SDK:basics#int
      body:
        Literal:
          IntegerLiteral: 1
  in:
    Variable: x
```

```json canonical
{ "LetDefinition": { "name": "x", "definition": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Literal": { "IntegerLiteral": 1 } } } }, "in": { "Variable": "x" } } }
```

```json accepted
{ "LetDefinition": { "attributes": {}, "name": "x", "definition": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Literal": { "IntegerLiteral": 1 } } } }, "in": { "Variable": "x" } } }
```

```json accepted warning=legacy_spelling
{ "LetDefinition": { "valueName": "x", "valueDefinition": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Literal": { "IntegerLiteral": 1 } } } }, "inValue": { "Variable": "x" } } }
```

## values-0018: Let recursion {node=Value}

```yaml canonical
LetRecursion:
  definitions:
    f:
      ExpressionBody:
        inputTypes: {}
        outputType: morphir/SDK:basics#int
        body:
          Variable: f
  in:
    Variable: f
```

```json canonical
{ "LetRecursion": { "definitions": { "f": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "f" } } } }, "in": { "Variable": "f" } } }
```

```json accepted
{ "LetRecursion": { "attributes": {}, "definitions": { "f": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "f" } } } }, "in": { "Variable": "f" } } }
```

## values-0019: Destructure {node=Value}

```yaml canonical
Destructure:
  pattern:
    TuplePattern:
      - AsPattern:
          pattern:
            WildcardPattern: {}
          name: a
      - WildcardPattern: {}
  value:
    Variable: pair
  in:
    Variable: a
```

```json canonical
{ "Destructure": { "pattern": { "TuplePattern": [{ "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "a" } }, { "WildcardPattern": {} }] }, "value": { "Variable": "pair" }, "in": { "Variable": "a" } } }
```

```json accepted
{ "Destructure": { "attributes": {}, "pattern": { "TuplePattern": [{ "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "a" } }, { "WildcardPattern": {} }] }, "value": { "Variable": "pair" }, "in": { "Variable": "a" } } }
```

## values-0020: Pattern match {node=Value}

```yaml canonical
PatternMatch:
  value:
    Variable: x
  cases:
    - pattern:
        LiteralPattern:
          IntegerLiteral: 0
      body:
        Literal:
          BoolLiteral: true
    - pattern:
        WildcardPattern: {}
      body:
        Literal:
          BoolLiteral: false
```

```json canonical
{ "PatternMatch": { "value": { "Variable": "x" }, "cases": [{ "pattern": { "LiteralPattern": { "IntegerLiteral": 0 } }, "body": { "Literal": { "BoolLiteral": true } } }, { "pattern": { "WildcardPattern": {} }, "body": { "Literal": { "BoolLiteral": false } } }] } }
```

```json accepted
{ "PatternMatch": { "attributes": {}, "value": { "Variable": "x" }, "cases": [{ "pattern": { "LiteralPattern": { "IntegerLiteral": 0 } }, "body": { "Literal": { "BoolLiteral": true } } }, { "pattern": { "WildcardPattern": {} }, "body": { "Literal": { "BoolLiteral": false } } }] } }
```

## values-0021: Update record {node=Value}

```yaml canonical
UpdateRecord:
  target:
    Variable: record
  fields:
    name:
      Literal:
        StringLiteral: new
```

```json canonical
{ "UpdateRecord": { "target": { "Variable": "record" }, "fields": { "name": { "Literal": { "StringLiteral": "new" } } } } }
```

```json accepted
{ "UpdateRecord": { "attributes": {}, "target": { "Variable": "record" }, "fields": { "name": { "Literal": { "StringLiteral": "new" } } } } }
```

## values-0022: Attributes are kept when compared with them {node=Value compare=attributes}

```yaml canonical
Variable:
  attributes:
    source: { startLine: 3, startColumn: 5, endLine: 3, endColumn: 6 }
  name: x
```

```json canonical
{ "Variable": { "attributes": { "source": { "startLine": 3, "startColumn": 5, "endLine": 3, "endColumn": 6 } }, "name": "x" } }
```
