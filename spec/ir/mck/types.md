# Types

Type expressions. The bare-array rule closed bead morphir-j442: a bare array is a Tuple, and a parameterized reference always carries the `Reference` wrapper. Every node has a compact spelling and an expanded spelling whose payload starts with `attributes` (decision 0005); the expanded spelling with empty attributes is accepted and never written.

## types-0001: Type variable {node=Type}

```yaml canonical
a
```

```json canonical
"a"
```

```json accepted
{ "Variable": { "attributes": {}, "name": "a" } }
```

## types-0002: Reference without arguments {node=Type}

```yaml canonical
morphir/SDK:basics#int
```

```json canonical
"morphir/SDK:basics#int"
```

```json accepted
{ "Reference": "morphir/SDK:basics#int" }
```

```json accepted
{ "Reference": { "fqname": "morphir/SDK:basics#int" } }
```

```json accepted
{ "Reference": { "fqname": "morphir/SDK:basics#int", "args": [] } }
```

```json accepted
{ "Reference": { "attributes": {}, "fqname": "morphir/SDK:basics#int" } }
```

## types-0003: Reference with one argument {node=Type}

Closes bead morphir-ir-v4-stabilize.2 once the Rust decoder agrees.

```yaml canonical
Reference: ["morphir/SDK:list#list", a]
```

```json canonical
{ "Reference": ["morphir/SDK:list#list", "a"] }
```

```json accepted
{ "Reference": { "fqname": "morphir/SDK:list#list", "args": ["a"] } }
```

```json accepted
{ "Reference": { "attributes": {}, "fqname": "morphir/SDK:list#list", "args": ["a"] } }
```

```yaml rejected expect=Tuple
["morphir/SDK:list#list", a]
```

## types-0004: Tuple type {node=Type}

```yaml canonical
Tuple: ["morphir/SDK:basics#int", "morphir/SDK:string#string"]
```

```json canonical
{ "Tuple": ["morphir/SDK:basics#int", "morphir/SDK:string#string"] }
```

```json accepted
["morphir/SDK:basics#int", "morphir/SDK:string#string"]
```

```json accepted
{ "Tuple": { "elements": ["morphir/SDK:basics#int", "morphir/SDK:string#string"] } }
```

```json accepted
{ "Tuple": { "attributes": {}, "elements": ["morphir/SDK:basics#int", "morphir/SDK:string#string"] } }
```

## types-0005: Record type {node=Type}

Decision 0004: fields live under a `fields` member, so `attributes` can sit beside them. The field map directly under `Record`, which the schema documented until 2026-09-04, is accepted for the one-release window of decision 0006 and reported as `legacy_spelling`. The Rust encoder's `attrs` is the other window spelling a Record payload takes — it is a row of decision 0006's window table, not a decision of its own; this case pins it for type expressions and values-0013 pins it for values.

```yaml canonical
Record:
  fields:
    name: morphir/SDK:string#string
    age: morphir/SDK:basics#int
```

```json canonical
{ "Record": { "fields": { "name": "morphir/SDK:string#string", "age": "morphir/SDK:basics#int" } } }
```

```json accepted
{ "Record": { "attributes": {}, "fields": { "name": "morphir/SDK:string#string", "age": "morphir/SDK:basics#int" } } }
```

```json accepted warning=legacy_spelling
{ "Record": { "attrs": {}, "fields": { "name": "morphir/SDK:string#string", "age": "morphir/SDK:basics#int" } } }
```

```json accepted warning=legacy_spelling
{ "Record": { "name": "morphir/SDK:string#string", "age": "morphir/SDK:basics#int" } }
```

## types-0006: Extensible record type {node=Type}

```yaml canonical
ExtensibleRecord:
  variable: r
  fields:
    email: morphir/SDK:string#string
```

```json canonical
{ "ExtensibleRecord": { "variable": "r", "fields": { "email": "morphir/SDK:string#string" } } }
```

```json accepted
{ "ExtensibleRecord": { "attributes": {}, "variable": "r", "fields": { "email": "morphir/SDK:string#string" } } }
```

## types-0007: Function type {node=Type}

Decision 0007: a Function type declares a `parameterType`. `argumentType` (the pre-decision schema) and `arg`/`result` (the Rust encoder) are accepted for the window of decision 0006. Bead morphir-ir-v4-stabilize.3.

```yaml canonical
Function:
  parameterType: morphir/SDK:basics#int
  returnType: morphir/SDK:string#string
```

```json canonical
{ "Function": { "parameterType": "morphir/SDK:basics#int", "returnType": "morphir/SDK:string#string" } }
```

```json accepted
{ "Function": { "attributes": {}, "parameterType": "morphir/SDK:basics#int", "returnType": "morphir/SDK:string#string" } }
```

```json accepted warning=legacy_spelling
{ "Function": { "argumentType": "morphir/SDK:basics#int", "returnType": "morphir/SDK:string#string" } }
```

```json accepted warning=legacy_spelling
{ "Function": { "arg": "morphir/SDK:basics#int", "result": "morphir/SDK:string#string" } }
```

## types-0008: Unit type {node=Type}

```yaml canonical
Unit: {}
```

```json canonical
{ "Unit": {} }
```

```json accepted
{ "Unit": { "attributes": {} } }
```

## types-0009: Attributes on type expressions {node=Type}

Decision 0005: `attributes` is the optional first member of every expanded payload, and an empty one is never written. `attrs` is the Rust encoder's spelling, accepted for the window of decision 0006.

```yaml canonical
a
```

```json canonical
"a"
```

```json accepted
{ "Variable": { "attributes": {}, "name": "a" } }
```

```json accepted warning=legacy_spelling
{ "Variable": { "attrs": {}, "name": "a" } }
```

## types-0010: Attributes are kept when compared with them {node=Type compare=attributes}

A source location makes the expanded spelling the canonical one.

```yaml canonical
Variable:
  attributes:
    source:
      startLine: 1
      startColumn: 1
      endLine: 1
      endColumn: 2
  name: a
```

```json canonical
{ "Variable": { "attributes": { "source": { "startLine": 1, "startColumn": 1, "endLine": 1, "endColumn": 2 } }, "name": "a" } }
```

## types-0011: Incompleteness is not a type expression {node=Type}

Decision 0008 makes `Hole` a value expression (values-0009). The type-level incompleteness vocabulary — `Hole` with its reason, and `Draft` — is the v4 schema's `IncompleteTypeDefinitionBody`, which belongs to a definition, not to a type expression. A reader that meets either tag where a type belongs refuses it as an unknown node. The spellings themselves are pinned where they are read: definitions-0014 for a `Hole` with a `TypeMismatch` reason, definitions-0015 for `Draft`, and definitions-0016 for a `DeletedDuringRefactor` reason on an incomplete value definition.

```json rejected diagnostic=unknown_node
{ "Hole": { "reason": { "TypeMismatch": { "expected": "morphir/SDK:basics#int", "found": "morphir/SDK:string#string" } } } }
```

```json rejected diagnostic=unknown_node
{ "Draft": {} }
```
