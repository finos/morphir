# Types

Type expressions. The bare-array rule closed bead morphir-j442: a bare array is a Tuple, and a parameterized reference always carries the `Reference` wrapper.

## types-0001: Type variable {node=Type}

```yaml canonical
a
```

```json canonical
"a"
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

## types-0005: Record type {node=Type status=pending}

The schema's RecordType definition writes fields directly under Record, while the published complete example, the document-tree specification page, and the Rust CLI output write them under a fields member. Both validate today because the schema does not check definition bodies. Bead morphir-ir-v4-stabilize.1 decides the canonical spelling; until then this case is pending and both spellings appear below as illustrations only.

```yaml
Record:
  name: morphir/SDK:string#string
  age: morphir/SDK:basics#int
```

```json
{ "Record": { "fields": { "name": "morphir/SDK:string#string", "age": "morphir/SDK:basics#int" } } }
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

## types-0007: Function type {node=Type}

The Rust encoder writes `arg` and `result` today; those are rejected. Bead morphir-ir-v4-stabilize.3.

```yaml canonical
Function:
  argumentType: morphir/SDK:basics#int
  returnType: morphir/SDK:string#string
```

```json canonical
{ "Function": { "argumentType": "morphir/SDK:basics#int", "returnType": "morphir/SDK:string#string" } }
```

```json rejected diagnostic=unknown_member
{ "Function": { "arg": "morphir/SDK:basics#int", "result": "morphir/SDK:string#string" } }
```

## types-0008: Unit type {node=Type}

```yaml canonical
Unit: {}
```

```json canonical
{ "Unit": {} }
```

## types-0009: Attributes on type expressions {node=Type status=pending}

Only `Literal` carries `attributes` in the schema today, while the spec's own examples write `attributes: {}` on every node. Bead morphir-ir-v4-stabilize.1 decides the expanded form for every node.

```json rejected diagnostic=unknown_member
{ "Variable": { "attributes": {}, "name": "a" } }
```
