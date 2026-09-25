Feature: Definitions and specifications

  @node:AccessControlledTypeDefinition
  Scenario: definitions-0001 Access-controlled definition, three spellings
    Closed by bead morphir-j442: the flattened form validates beside the tag form and the legacy form. The tag form is canonical.

    Then its canonical YAML spelling is:
      """yaml
      Public:
        TypeAliasDefinition:
          typeParams: []
          typeExp: morphir/SDK:string#string
      """
    And its canonical JSON spelling is { "Public": { "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } } }

  @node:AccessControlledTypeDefinition
  Scenario Outline: definitions-0001 Access-controlled definition, three spellings
    Then a reader of <format> accepts <input>

    Examples:
      | format | input                                                                                                                    |
      | JSON   | { "access": "Public", "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } }              |
      | JSON   | { "access": "Public", "value": { "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } } } |
      | JSON   | { "pub": { "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } } }                       |

  @node:TypeSpecification
  Scenario Outline: definitions-0002 Opaque type specification is an empty object
    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                          |
      | YAML   | OpaqueTypeSpecification: {}       |
      | JSON   | { "OpaqueTypeSpecification": {} } |

  @node:TypeSpecification
  Scenario: definitions-0002 Opaque type specification is an empty object
    Then a reader of JSON accepts ["OpaqueTypeSpecification", []]

  @node:TypeDefinition
  Scenario: definitions-0003 Custom type definition with constructors
    Decision 0007 names a constructor's slots parameters in the model; the wire spelling, a list of `[name, type]` pairs per constructor, is unchanged.

    Then its canonical YAML spelling is:
      """yaml
      CustomTypeDefinition:
        typeParams: [a]
        access: Public
        constructors:
          just: [[value, a]]
          nothing: []
      """
    And its canonical JSON spelling is { "CustomTypeDefinition": { "typeParams": ["a"], "access": "Public", "constructors": { "just": [["value", "a"]], "nothing": [] } } }

  @node:ValueSpecification
  Scenario: definitions-0004 Value specification
    Then its canonical YAML spelling is:
      """yaml
      inputs:
        a: morphir/SDK:basics#int
        b: morphir/SDK:basics#int
      output: morphir/SDK:basics#int
      """
    And its canonical JSON spelling is { "inputs": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "output": "morphir/SDK:basics#int" }
    And a reader of JSON accepts { "inputs": [["a", "morphir/SDK:basics#int"], ["b", "morphir/SDK:basics#int"]], "output": "morphir/SDK:basics#int" }

  @node:ValueDefinition
  Scenario: definitions-0005 Expression body
    Then its canonical YAML spelling is:
      """yaml
      ExpressionBody:
        inputTypes:
          x: morphir/SDK:basics#int
        outputType: morphir/SDK:basics#int
        body:
          Variable: x
      """
    And its canonical JSON spelling is { "ExpressionBody": { "inputTypes": { "x": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "x" } } }

  @node:AccessControlledTypeDefinition
  Scenario: definitions-0006 Documentation on a definition
    Decision 0010: `doc` is a flattened member placed first beside the variant. The nested `{ "doc", "value" }` wrapper is accepted for the window of decision 0006. Bead morphir-ir-v4-stabilize.5.

    Then its canonical YAML spelling is:
      """yaml
      Public:
        doc: The user's display name
        TypeAliasDefinition:
          typeParams: []
          typeExp: morphir/SDK:string#string
      """
    And its canonical JSON spelling is { "Public": { "doc": "The user's display name", "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } } }
    And a reader of JSON accepts { "access": "Public", "doc": "The user's display name", "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } }
    And a reader of JSON accepts { "Public": { "doc": "The user's display name", "value": { "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } } } } with warning legacy_spelling

  @node:ValueDefinition
  Scenario: definitions-0007 Native and external bodies
    Decision 0008: `ExternalBody` carries a list of per-target bindings and an optional fallback `body`, so a Gleam-style external with a body encodes faithfully. The single-binding spelling with `externalName` and `targetPlatform` at the top level is accepted for the window of decision 0006 as a one-entry list.

    Then its canonical YAML spelling is:
      """yaml
      ExternalBody:
        inputTypes:
          msg: morphir/SDK:string#string
        outputType: morphir/SDK:basics#unit
        externals:
          - targetPlatform: javascript
            externalName: console.log
      """
    And its canonical JSON spelling is { "ExternalBody": { "inputTypes": { "msg": "morphir/SDK:string#string" }, "outputType": "morphir/SDK:basics#unit", "externals": [{ "targetPlatform": "javascript", "externalName": "console.log" }] } }
    And a reader of JSON accepts { "ExternalBody": { "inputTypes": { "msg": "morphir/SDK:string#string" }, "outputType": "morphir/SDK:basics#unit", "externalName": "console.log", "targetPlatform": "javascript" } } with warning legacy_spelling

  @node:ValueDefinition
  Scenario: definitions-0008 External body with two bindings and a fallback
    Decision 0008: targetPlatform values are unique within externals.

    Then its canonical YAML spelling is:
      """yaml
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
      """
    And its canonical JSON spelling is { "ExternalBody": { "inputTypes": { "x": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "externals": [{ "targetPlatform": "erlang", "externalName": "math:abs" }, { "targetPlatform": "javascript", "externalName": "Math.abs" }], "body": { "Variable": "x" } } }
    And a reader of JSON rejects { "ExternalBody": { "inputTypes": { "x": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "externals": [{ "targetPlatform": "javascript", "externalName": "a" }, { "targetPlatform": "javascript", "externalName": "b" }] } } with duplicate_member

  @node:ValueDefinition
  Scenario: definitions-0009 Native body
    Then its canonical YAML spelling is:
      """yaml
      NativeBody:
        inputTypes:
          a: morphir/SDK:basics#int
          b: morphir/SDK:basics#int
        outputType: morphir/SDK:basics#int
        nativeInfo:
          hint:
            Arithmetic: {}
      """
    And its canonical JSON spelling is { "NativeBody": { "inputTypes": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "nativeInfo": { "hint": { "Arithmetic": {} } } } }

  @node:ModuleSpecification
  Scenario: definitions-0010 Documentation on a value specification
    Decision 0010: a value specification's `doc` is first beside its own members; the nested `{ "doc", "value" }` wrapper is accepted for the window.

    Then its canonical YAML spelling is:
      """yaml
      types: {}
      values:
        add:
          doc: Adds two integers
          inputs:
            a: morphir/SDK:basics#int
            b: morphir/SDK:basics#int
          output: morphir/SDK:basics#int
      """
    And its canonical JSON spelling is { "types": {}, "values": { "add": { "doc": "Adds two integers", "inputs": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "output": "morphir/SDK:basics#int" } } }
    And a reader of JSON accepts { "types": {}, "values": { "add": { "doc": "Adds two integers", "value": { "inputs": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "output": "morphir/SDK:basics#int" } } } } with warning legacy_spelling

  @node:TypeSpecification
  Scenario: definitions-0011 Type alias specification
    A specification states a type's shape without an access level; `typeParams` comes before `typeExp`, as it does in the matching definition (definitions-0001).

    Then its canonical YAML spelling is:
      """yaml
      TypeAliasSpecification:
        typeParams: [a]
        typeExp:
          Reference: ["morphir/SDK:list#list", a]
      """
    And its canonical JSON spelling is { "TypeAliasSpecification": { "typeParams": ["a"], "typeExp": { "Reference": ["morphir/SDK:list#list", "a"] } } }

  @node:TypeSpecification
  Scenario: definitions-0012 Custom type specification
    The constructor map is the same `[name, type]` pair list the definition uses (definitions-0003); a specification has no `access` member, because the whole specification is the public face of the type.

    Then its canonical YAML spelling is:
      """yaml
      CustomTypeSpecification:
        typeParams: [a]
        constructors:
          just: [[value, a]]
          nothing: []
      """
    And its canonical JSON spelling is { "CustomTypeSpecification": { "typeParams": ["a"], "constructors": { "just": [["value", "a"]], "nothing": [] } } }

  @node:TypeSpecification
  Scenario: definitions-0013 Derived type specification
    A derived type names the type it is built from and the two functions that convert between them. All four members are required, and the two conversions are FQNames, not expressions.

    Then its canonical YAML spelling is:
      """yaml
      DerivedTypeSpecification:
        typeParams: []
        baseType: morphir/SDK:string#string
        fromBaseType: my-org/project:module#from-string
        toBaseType: my-org/project:module#to-string
      """
    And its canonical JSON spelling is { "DerivedTypeSpecification": { "typeParams": [], "baseType": "morphir/SDK:string#string", "fromBaseType": "my-org/project:module#from-string", "toBaseType": "my-org/project:module#to-string" } }

  @node:TypeDefinition
  Scenario: definitions-0014 Incomplete type definition, a hole with a type mismatch
    Decision 0008 puts `Hole` in the value expressions; the v4 schema's `IncompleteTypeDefinitionBody` puts type-level incompleteness in a definition rather than in a type expression (types-0011). An `IncompleteTypeDefinition` carries its `typeParams`, an `incompleteness`, and an optional `partialTypeExp` — what the author had written when the definition stopped being complete. A `Hole`'s `reason` says why; `TypeMismatch` names the expected and the found type as strings.

    Then its canonical YAML spelling is:
      """yaml
      IncompleteTypeDefinition:
        typeParams: [a]
        incompleteness:
          Hole:
            reason:
              TypeMismatch:
                expected: morphir/SDK:basics#int
                found: morphir/SDK:string#string
      """
    And its canonical JSON spelling is { "IncompleteTypeDefinition": { "typeParams": ["a"], "incompleteness": { "Hole": { "reason": { "TypeMismatch": { "expected": "morphir/SDK:basics#int", "found": "morphir/SDK:string#string" } } } } } }

  @node:TypeDefinition
  Scenario: definitions-0015 Draft type definition with a partial type expression
    `Draft` is the second incompleteness: the definition is deliberately unfinished rather than broken, so it takes an empty payload and no reason. The `partialTypeExp` it keeps is an ordinary type expression.

    Then its canonical YAML spelling is:
      """yaml
      IncompleteTypeDefinition:
        typeParams: []
        incompleteness:
          Draft: {}
        partialTypeExp: morphir/SDK:basics#int
      """
    And its canonical JSON spelling is { "IncompleteTypeDefinition": { "typeParams": [], "incompleteness": { "Draft": {} }, "partialTypeExp": "morphir/SDK:basics#int" } }

  @node:ValueDefinition
  Scenario: definitions-0016 Incomplete value definition
    Decision 0008 consequence 2: a hole inside a body and an incomplete body are different things. An `IncompleteBody` is the fourth value definition body; its `outputType` is optional, because an incomplete definition may not have one yet, and its `incompleteness` uses the same vocabulary the type side does. `DeletedDuringRefactor` spells its transaction identifier `tx-id` on the wire.

    Then its canonical YAML spelling is:
      """yaml
      IncompleteBody:
        inputTypes:
          x: morphir/SDK:basics#int
        outputType: morphir/SDK:basics#int
        incompleteness:
          Hole:
            reason:
              DeletedDuringRefactor:
                tx-id: tx-42
      """
    And its canonical JSON spelling is { "IncompleteBody": { "inputTypes": { "x": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "incompleteness": { "Hole": { "reason": { "DeletedDuringRefactor": { "tx-id": "tx-42" } } } } } }

  @node:AccessControlledTypeDefinition
  Scenario: definitions-0017 Private access-controlled definition
    `Private` is the other access level of definitions-0001 and takes the same three spellings. Decision 0010: the nested `{ "doc", "value" }` wrapper is accepted for the window of decision 0006 under `Private` exactly as it is under `Public` (definitions-0006). The fence below carries no `doc`, so it shows only the unwrapping half: the payload under `value` moves up beside the access tag.

    Then its canonical YAML spelling is:
      """yaml
      Private:
        TypeAliasDefinition:
          typeParams: []
          typeExp: morphir/SDK:basics#int
      """
    And its canonical JSON spelling is { "Private": { "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:basics#int" } } }
    And a reader of JSON accepts { "access": "Private", "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:basics#int" } }
    And a reader of JSON accepts { "Private": { "value": { "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:basics#int" } } } } with warning legacy_spelling

  @node:AccessControlledValueDefinition
  Scenario: definitions-0018 Access-controlled value definition, public
    The value twin of definitions-0001 and definitions-0006. `readAccessControlled` is shared with the type side, so the same three access spellings and the same documentation rules apply; the node kind is its own, so the kit states it in its own case. Decision 0010: `doc` is flattened beside the variant, and the nested `{ "doc", "value" }` wrapper is accepted for the window of decision 0006.

    The fence below is the nested wrapper: the definition sits under `value` instead of beside `doc`. A reader normalizes it to the canonical fence above and reports `legacy_spelling`.

    Then its canonical YAML spelling is:
      """yaml
      Public:
        doc: Adds two integers
        ExpressionBody:
          inputTypes:
            a: morphir/SDK:basics#int
            b: morphir/SDK:basics#int
          outputType: morphir/SDK:basics#int
          body:
            Variable: a
      """
    And its canonical JSON spelling is { "Public": { "doc": "Adds two integers", "ExpressionBody": { "inputTypes": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "a" } } } }
    And a reader of JSON accepts { "access": "Public", "doc": "Adds two integers", "ExpressionBody": { "inputTypes": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "a" } } }
    And a reader of JSON accepts { "Public": { "doc": "Adds two integers", "value": { "ExpressionBody": { "inputTypes": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" }, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "a" } } } } } with warning legacy_spelling

  @node:AccessControlledValueDefinition
  Scenario: definitions-0019 Private access-controlled value definition
    `Private` on the value side, the twin of definitions-0017. The nested `{ "value" }` wrapper is accepted for the window of decision 0006 under `Private` exactly as it is under `Public` (definitions-0018); the fence below carries no `doc`, so it shows only the unwrapping half.

    Then its canonical YAML spelling is:
      """yaml
      Private:
        ExpressionBody:
          inputTypes: {}
          outputType: morphir/SDK:basics#int
          body:
            Variable: x
      """
    And its canonical JSON spelling is { "Private": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "x" } } } }
    And a reader of JSON accepts { "access": "Private", "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "x" } } }
    And a reader of JSON accepts { "Private": { "value": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "x" } } } } } with warning legacy_spelling

  @node:TypeSpecification
  Scenario: definitions-0020 Annotations on a type specification
    A specification may carry `annotations`, written first and only when non-empty. Each is either the compact string `pkg:mod#local` or `pkg:mod#local:free text` (the separator is the first colon after `#`), or the structured object `{ "name", "arguments" }` whose arguments are positional values or named `{ "name", "value" }` pairs. `arguments` is omitted when empty. Definitions never carry annotations (definitions-0023).

    Then its canonical YAML spelling is:
      """yaml
      TypeAliasSpecification:
        annotations:
          - my-org/project:annotations#deprecated:Use user-v2 instead
          - name: my-org/project:annotations#since
            arguments:
              - Literal:
                  StringLiteral: 1.2.0
              - name: reason
                value:
                  Literal:
                    StringLiteral: renamed
          - name: my-org/project:annotations#internal
        typeParams: []
        typeExp: morphir/SDK:string#string
      """
    And its canonical JSON spelling is { "TypeAliasSpecification": { "annotations": ["my-org/project:annotations#deprecated:Use user-v2 instead", { "name": "my-org/project:annotations#since", "arguments": [{ "Literal": { "StringLiteral": "1.2.0" } }, { "name": "reason", "value": { "Literal": { "StringLiteral": "renamed" } } }] }, { "name": "my-org/project:annotations#internal" }], "typeParams": [], "typeExp": "morphir/SDK:string#string" } }
    And a reader of JSON accepts { "TypeAliasSpecification": { "annotations": ["my-org/project:annotations#deprecated:Use user-v2 instead", { "name": "my-org/project:annotations#since", "arguments": [{ "Literal": { "StringLiteral": "1.2.0" } }, { "name": "reason", "value": { "Literal": { "StringLiteral": "renamed" } } }] }, { "name": "my-org/project:annotations#internal", "arguments": [] }], "typeParams": [], "typeExp": "morphir/SDK:string#string" } }

  @node:ValueSpecification
  Scenario: definitions-0021 Annotations on a value specification
    Then its canonical YAML spelling is:
      """yaml
      annotations: ["my-org/project:annotations#pure"]
      inputs:
        x: morphir/SDK:basics#int
      output: morphir/SDK:basics#int
      """
    And its canonical JSON spelling is { "annotations": ["my-org/project:annotations#pure"], "inputs": { "x": "morphir/SDK:basics#int" }, "output": "morphir/SDK:basics#int" }

  @node:ModuleSpecification
  Scenario: definitions-0022 Annotations on a module specification
    `annotations` comes first; `doc` stays last (decision 0010).

    Then its canonical YAML spelling is:
      """yaml
      annotations: ["my-org/project:annotations#stable"]
      types: {}
      values: {}
      doc: The domain module
      """
    And its canonical JSON spelling is { "annotations": ["my-org/project:annotations#stable"], "types": {}, "values": {}, "doc": "The domain module" }

  @node:TypeDefinition
  Scenario: definitions-0023 A definition carries no annotations
    Annotations belong to specifications, the public face; inside a definition the member is unknown.

    Then a reader of JSON rejects { "TypeAliasDefinition": { "annotations": [], "typeParams": [], "typeExp": "morphir/SDK:string#string" } } with unknown_member

  @node:TypeDefinition
  Scenario: definitions-0024 A hole incompleteness keeps a partial body
    A `Hole` says why under `reason` and may keep what the author had as `partialBody`, a type expression; the member is written only when present (definitions-0014 has none).

    Then its canonical YAML spelling is:
      """yaml
      IncompleteTypeDefinition:
        typeParams: []
        incompleteness:
          Hole:
            reason:
              UnresolvedReference:
                target: my-org/project:module#missing
            partialBody: morphir/SDK:basics#int
      """
    And its canonical JSON spelling is { "IncompleteTypeDefinition": { "typeParams": [], "incompleteness": { "Hole": { "reason": { "UnresolvedReference": { "target": "my-org/project:module#missing" } }, "partialBody": "morphir/SDK:basics#int" } } } }

  @node:ValueDefinition
  Scenario: definitions-0025 An incomplete body keeps a partial value
    The value twin of definitions-0024: `partialBody` on an `IncompleteBody` is a value expression, written after `incompleteness` and only when present.

    Then its canonical YAML spelling is:
      """yaml
      IncompleteBody:
        inputTypes: {}
        outputType: morphir/SDK:basics#int
        incompleteness:
          Draft: {}
        partialBody:
          Literal:
            IntegerLiteral: 1
      """
    And its canonical JSON spelling is { "IncompleteBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "incompleteness": { "Draft": {} }, "partialBody": { "Literal": { "IntegerLiteral": 1 } } } }

  @node:TypeDefinition
  Scenario Outline: definitions-0026 Draft is an incompleteness, not a hole reason
    A hole's reason is `UnresolvedReference`, `DeletedDuringRefactor` or `TypeMismatch` (definitions-0014, 0016). `Draft` is the other incompleteness kind (definitions-0015) and names no reason; a reason must be a wrapper object.

    Then a reader of <format> rejects <input> with <diagnostic>

    Examples:
      | format | input                                                                                                             | diagnostic   |
      | JSON   | { "IncompleteTypeDefinition": { "typeParams": [], "incompleteness": { "Hole": { "reason": { "Draft": {} } } } } } | unknown_node |
      | JSON   | { "IncompleteTypeDefinition": { "typeParams": [], "incompleteness": { "Hole": { "reason": "Draft" } } } }         | invalid_type |

  @node:ValueDefinition
  Scenario: definitions-0027 An input type is a bare type
    Each entry of `inputTypes` is a type expression and nothing else; there is no per-parameter attributes member.

    Then a reader of JSON rejects { "ExpressionBody": { "inputTypes": { "x": { "typeAttributes": {}, "type": "morphir/SDK:basics#int" } }, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "x" } } } with unknown_node

  @node:AccessControlledTypeDefinition
  Scenario: definitions-0028 Documentation is one string
    `doc` is a string wherever a node carries it (decision 0010). An array of lines is accepted only in a module manifest file (document-tree page), never here.

    Then a reader of JSON rejects { "Public": { "doc": ["line one", "line two"], "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:string#string" } } } with invalid_type

  @node:ValueSpecification
  Scenario Outline: definitions-0029 A value specification without inputs writes none
    `inputs` is omitted when empty and accepted when written empty.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                               |
      | YAML   | output: morphir/SDK:basics#int         |
      | JSON   | { "output": "morphir/SDK:basics#int" } |

  @node:ValueSpecification
  Scenario: definitions-0029 A value specification without inputs writes none
    Then a reader of JSON accepts { "inputs": {}, "output": "morphir/SDK:basics#int" }

  @node:ValueDefinition
  Scenario: definitions-0030 A platform-specific native hint names its platform
    `PlatformSpecific` requires `platform`; a reader does not invent one.

    Then a reader of JSON rejects { "NativeBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "nativeInfo": { "hint": { "PlatformSpecific": {} } } } } with missing_member

  @node:AccessControlledTypeDefinition
  Scenario Outline: definitions-0031 priv is not an access spelling
    The access spellings are `Public`, `public`, `pub`, `Private` and `private` (definitions-0001, 0017). `priv` is none of them.

    Then a reader of <format> rejects <input> with <diagnostic>

    Examples:
      | format | input                                                                                                  | diagnostic     |
      | JSON   | { "priv": { "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:basics#int" } } }       | invalid_access |
      | JSON   | { "access": "priv", "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:basics#int" } } | invalid_access |
