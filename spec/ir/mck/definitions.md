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

Decision 0007 names a constructor's slots parameters in the model; the wire spelling, a list of `[name, type]` pairs per constructor, is unchanged.

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

## definitions-0006: Documentation on a definition {node=AccessControlledTypeDefinition}

Decision 0010: `doc` is a flattened member placed first beside the variant. The nested `{ "doc", "value" }` wrapper is accepted for the window of decision 0006. Bead morphir-ir-v4-stabilize.5.

```yaml canonical
Public:
  doc: The user's display name
  TypeAliasDefinition:
    typeParams: []
    typeExp: morphir/SDK:string#string
```

```json canonical
{ "Public": { "doc": "The user's display name", "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } } }
```

```json accepted
{ "access": "Public", "doc": "The user's display name", "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } }
```

```json accepted warning=legacy_spelling
{ "Public": { "doc": "The user's display name", "value": { "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } } } }
```

## definitions-0007: Native and external bodies {node=ValueDefinition}

Decision 0008: `ExternalBody` carries a list of per-target bindings and an optional fallback `body`, so a Gleam-style external with a body encodes faithfully. The single-binding spelling with `externalName` and `targetPlatform` at the top level is accepted for the window of decision 0006 as a one-entry list.

```yaml canonical
ExternalBody:
  inputTypes:
    msg: morphir/SDK:string#string
  outputType: morphir/SDK:basics#unit
  externals:
    - targetPlatform: javascript
      externalName: console.log
```

```json canonical
{ "ExternalBody": { "inputTypes": { "msg": "morphir/SDK:string#string" }, "outputType": "morphir/SDK:basics#unit", "externals": [{ "targetPlatform": "javascript", "externalName": "console.log" }] } }
```

```json accepted warning=legacy_spelling
{ "ExternalBody": { "inputTypes": { "msg": "morphir/SDK:string#string" }, "outputType": "morphir/SDK:basics#unit", "externalName": "console.log", "targetPlatform": "javascript" } }
```

## definitions-0008: External body with two bindings and a fallback {node=ValueDefinition}

```yaml canonical
ExternalBody:
  inputTypes:
    x: morphir/SDK:basics#int
  outputType: morphir/SDK:basics#int
  externals:
    - targetPlatform: erlang
      externalName: math:abs
    - targetPlatform: javascript
      externalName: Math.abs
  body:
    Variable: x
```

```json canonical
{ "ExternalBody": { "inputTypes": { "x": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "externals": [{ "targetPlatform": "erlang", "externalName": "math:abs" }, { "targetPlatform": "javascript", "externalName": "Math.abs" }], "body": { "Variable": "x" } } }
```

## definitions-0009: Native body {node=ValueDefinition}

```yaml canonical
NativeBody:
  inputTypes:
    a: morphir/SDK:basics#int
    b: morphir/SDK:basics#int
  outputType: morphir/SDK:basics#int
  nativeInfo:
    hint:
      Arithmetic: {}
```

```json canonical
{ "NativeBody": { "inputTypes": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "nativeInfo": { "hint": { "Arithmetic": {} } } } }
```

## definitions-0010: Documentation on a value specification {node=ModuleSpecification}

Decision 0010: a value specification's `doc` is first beside its own members; the nested `{ "doc", "value" }` wrapper is accepted for the window.

```yaml canonical
types: {}
values:
  add:
    doc: Adds two integers
    inputs:
      a: morphir/SDK:basics#int
      b: morphir/SDK:basics#int
    output: morphir/SDK:basics#int
```

```json canonical
{ "types": {}, "values": { "add": { "doc": "Adds two integers", "inputs": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "output": "morphir/SDK:basics#int" } } }
```

```json accepted warning=legacy_spelling
{ "types": {}, "values": { "add": { "doc": "Adds two integers", "value": { "inputs": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "output": "morphir/SDK:basics#int" } } } }
```
