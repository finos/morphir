# Definitions and specifications

## definitions-0001: Access-controlled definition, three spellings {node=AccessControlledTypeDefinition}

Closed by bead morphir-j442: the flattened form validates beside the tag form and the legacy form. The tag form is canonical.

```yaml canonical
Public:
  TypeAliasDefinition:
    typeParams: []
    typeExp: morphir/SDK:string#string
```

```json canonical
{ "Public": { "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } } }
```

```json accepted
{ "access": "Public", "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } }
```

```json accepted
{ "access": "Public", "value": { "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } } }
```

```json accepted
{ "pub": { "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } } }
```

## definitions-0002: Opaque type specification is an empty object {node=TypeSpecification}

```yaml canonical
OpaqueTypeSpecification: {}
```

```json canonical
{ "OpaqueTypeSpecification": {} }
```

```json accepted
["OpaqueTypeSpecification", []]
```

## definitions-0003: Custom type definition with constructors {node=TypeDefinition}

```yaml canonical
CustomTypeDefinition:
  typeParams: [a]
  access: Public
  constructors:
    just: [[value, a]]
    nothing: []
```

```json canonical
{ "CustomTypeDefinition": { "typeParams": ["a"], "access": "Public", "constructors": { "just": [["value", "a"]], "nothing": [] } } }
```

## definitions-0004: Value specification {node=ValueSpecification}

```yaml canonical
inputs:
  a: morphir/SDK:basics#int
  b: morphir/SDK:basics#int
output: morphir/SDK:basics#int
```

```json canonical
{ "inputs": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "output": "morphir/SDK:basics#int" }
```

```json accepted
{ "inputs": [["a", "morphir/SDK:basics#int"], ["b", "morphir/SDK:basics#int"]], "output": "morphir/SDK:basics#int" }
```

## definitions-0005: Expression body {node=ValueDefinition}

```yaml canonical
ExpressionBody:
  inputTypes:
    x: morphir/SDK:basics#int
  outputType: morphir/SDK:basics#int
  body:
    Variable: x
```

```json canonical
{ "ExpressionBody": { "inputTypes": { "x": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "x" } } }
```

## definitions-0006: Documentation on a definition {node=AccessControlledTypeDefinition status=pending}

The schema accepts `doc` flattened beside `access` and nested as `{doc, value}`. Bead morphir-ir-v4-stabilize.5 picks the canonical spelling; the flattened form is what the CLI writes and both examples use.

```json rejected diagnostic=unknown_member
{ "access": "Public", "documentation": "x", "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } }
```
