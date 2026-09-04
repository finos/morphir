# Values

Value expressions. Member vocabulary is the schema's; bead morphir-ir-v4-stabilize.1 decides the expanded forms with attributes, so cases that depend on that are pending.

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

## values-0005: If-then-else member names {node=Value}

The Rust encoder writes `thenBranch` and `elseBranch`; those are rejected. Bead morphir-ir-v4-stabilize.3.

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

```json rejected diagnostic=unknown_member
{ "IfThenElse": { "condition": true, "thenBranch": 1, "elseBranch": 2 } }
```

## values-0006: Field access member names {node=Value}

Spec examples wrote `subject` and `fieldName`; the schema says `target` and `name`.

```yaml canonical
Field:
  target:
    Variable: record
  name: field-name
```

```json canonical
{ "Field": { "target": { "Variable": "record" }, "name": "field-name" } }
```

```json rejected diagnostic=unknown_member
{ "Field": { "subject": { "Variable": "record" }, "fieldName": "field-name" } }
```

## values-0007: Tuple and list values {node=Value}

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

## values-0008: Bare array as a value {node=Value status=pending}

The schema lists a bare array as a List shorthand and, in the same file, says bare arrays are not allowed for values. Bead morphir-ir-v4-stabilize.4 decides; the design's reasoning favors rejection.

```json rejected diagnostic=ambiguous_shorthand
[1, 2, 3]
```

## values-0009: Hole, Native, and External {node=Value status=pending}

These v4 value expressions are absent from the schema's `Value`. Bead morphir-ir-v4-stabilize.1 adds them together with the vocabulary decision.

```json rejected diagnostic=unknown_node
{ "Hole": { "reason": { "UnresolvedReference": { "target": "my-org/project:module#deleted" } } } }
```

## values-0010: Unit value {node=Value}

```yaml canonical
Unit: {}
```

```json canonical
{ "Unit": {} }
```
