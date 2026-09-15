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

Decision 0008: targetPlatform values are unique within externals.

```json rejected diagnostic=duplicate_member
{ "ExternalBody": { "inputTypes": { "x": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "externals": [{ "targetPlatform": "javascript", "externalName": "a" }, { "targetPlatform": "javascript", "externalName": "b" }] } }
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

## definitions-0011: Type alias specification {node=TypeSpecification}

A specification states a type's shape without an access level; `typeParams` comes before `typeExp`, as it does in the matching definition (definitions-0001).

```yaml canonical
TypeAliasSpecification:
  typeParams: [a]
  typeExp:
    Reference: ["morphir/SDK:list#list", a]
```

```json canonical
{ "TypeAliasSpecification": { "typeParams": ["a"], "typeExp": { "Reference": ["morphir/SDK:list#list", "a"] } } }
```

## definitions-0012: Custom type specification {node=TypeSpecification}

The constructor map is the same `[name, type]` pair list the definition uses (definitions-0003); a specification has no `access` member, because the whole specification is the public face of the type.

```yaml canonical
CustomTypeSpecification:
  typeParams: [a]
  constructors:
    just: [[value, a]]
    nothing: []
```

```json canonical
{ "CustomTypeSpecification": { "typeParams": ["a"], "constructors": { "just": [["value", "a"]], "nothing": [] } } }
```

## definitions-0013: Derived type specification {node=TypeSpecification}

A derived type names the type it is built from and the two functions that convert between them. All four members are required, and the two conversions are FQNames, not expressions.

```yaml canonical
DerivedTypeSpecification:
  typeParams: []
  baseType: morphir/SDK:string#string
  fromBaseType: my-org/project:module#from-string
  toBaseType: my-org/project:module#to-string
```

```json canonical
{ "DerivedTypeSpecification": { "typeParams": [], "baseType": "morphir/SDK:string#string", "fromBaseType": "my-org/project:module#from-string", "toBaseType": "my-org/project:module#to-string" } }
```

## definitions-0014: Incomplete type definition, a hole with a type mismatch {node=TypeDefinition}

Decision 0008 puts `Hole` in the value expressions; the v4 schema's `IncompleteTypeDefinitionBody` puts type-level incompleteness in a definition rather than in a type expression (types-0011). An `IncompleteTypeDefinition` carries its `typeParams`, an `incompleteness`, and an optional `partialTypeExp` — what the author had written when the definition stopped being complete. A `Hole`'s `reason` says why; `TypeMismatch` names the expected and the found type as strings.

```yaml canonical
IncompleteTypeDefinition:
  typeParams: [a]
  incompleteness:
    Hole:
      reason:
        TypeMismatch:
          expected: morphir/SDK:basics#int
          found: morphir/SDK:string#string
```

```json canonical
{ "IncompleteTypeDefinition": { "typeParams": ["a"], "incompleteness": { "Hole": { "reason": { "TypeMismatch": { "expected": "morphir/SDK:basics#int", "found": "morphir/SDK:string#string" } } } } } }
```

## definitions-0015: Draft type definition with a partial type expression {node=TypeDefinition}

`Draft` is the second incompleteness: the definition is deliberately unfinished rather than broken, so it takes an empty payload and no reason. The `partialTypeExp` it keeps is an ordinary type expression.

```yaml canonical
IncompleteTypeDefinition:
  typeParams: []
  incompleteness:
    Draft: {}
  partialTypeExp: morphir/SDK:basics#int
```

```json canonical
{ "IncompleteTypeDefinition": { "typeParams": [], "incompleteness": { "Draft": {} }, "partialTypeExp": "morphir/SDK:basics#int" } }
```

## definitions-0016: Incomplete value definition {node=ValueDefinition}

Decision 0008 consequence 2: a hole inside a body and an incomplete body are different things. An `IncompleteBody` is the fourth value definition body; its `outputType` is optional, because an incomplete definition may not have one yet, and its `incompleteness` uses the same vocabulary the type side does. `DeletedDuringRefactor` spells its transaction identifier `tx-id` on the wire.

```yaml canonical
IncompleteBody:
  inputTypes:
    x: morphir/SDK:basics#int
  outputType: morphir/SDK:basics#int
  incompleteness:
    Hole:
      reason:
        DeletedDuringRefactor:
          tx-id: tx-42
```

```json canonical
{ "IncompleteBody": { "inputTypes": { "x": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "incompleteness": { "Hole": { "reason": { "DeletedDuringRefactor": { "tx-id": "tx-42" } } } } } }
```

## definitions-0017: Private access-controlled definition {node=AccessControlledTypeDefinition}

`Private` is the other access level of definitions-0001 and takes the same three spellings. Decision 0010: the nested `{ "doc", "value" }` wrapper is accepted for the window of decision 0006 under `Private` exactly as it is under `Public` (definitions-0006). The fence below carries no `doc`, so it shows only the unwrapping half: the payload under `value` moves up beside the access tag.

```yaml canonical
Private:
  TypeAliasDefinition:
    typeParams: []
    typeExp: morphir/SDK:basics#int
```

```json canonical
{ "Private": { "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:basics#int" } } }
```

```json accepted
{ "access": "Private", "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:basics#int" } }
```

```json accepted warning=legacy_spelling
{ "Private": { "value": { "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:basics#int" } } } }
```

## definitions-0018: Access-controlled value definition, public {node=AccessControlledValueDefinition}

The value twin of definitions-0001 and definitions-0006. `readAccessControlled` is shared with the type side, so the same three access spellings and the same documentation rules apply; the node kind is its own, so the kit states it in its own case. Decision 0010: `doc` is flattened beside the variant, and the nested `{ "doc", "value" }` wrapper is accepted for the window of decision 0006.

```yaml canonical
Public:
  doc: Adds two integers
  ExpressionBody:
    inputTypes:
      a: morphir/SDK:basics#int
      b: morphir/SDK:basics#int
    outputType: morphir/SDK:basics#int
    body:
      Variable: a
```

```json canonical
{ "Public": { "doc": "Adds two integers", "ExpressionBody": { "inputTypes": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "a" } } } }
```

```json accepted
{ "access": "Public", "doc": "Adds two integers", "ExpressionBody": { "inputTypes": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "a" } } }
```

The fence below is the nested wrapper: the definition sits under `value` instead of beside `doc`. A reader normalizes it to the canonical fence above and reports `legacy_spelling`.

```json accepted warning=legacy_spelling
{ "Public": { "doc": "Adds two integers", "value": { "ExpressionBody": { "inputTypes": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "a" } } } } }
```

## definitions-0019: Private access-controlled value definition {node=AccessControlledValueDefinition}

`Private` on the value side, the twin of definitions-0017. The nested `{ "value" }` wrapper is accepted for the window of decision 0006 under `Private` exactly as it is under `Public` (definitions-0018); the fence below carries no `doc`, so it shows only the unwrapping half.

```yaml canonical
Private:
  ExpressionBody:
    inputTypes: {}
    outputType: morphir/SDK:basics#int
    body:
      Variable: x
```

```json canonical
{ "Private": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "x" } } } }
```

```json accepted
{ "access": "Private", "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "x" } } }
```

```json accepted warning=legacy_spelling
{ "Private": { "value": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "x" } } } } }
```
