@node:Value
Feature: Values
  Value expressions. At value position a bare string is a Variable or a Reference, a bare boolean or number is a literal, and a bare array is a List (decision 0009); a Tuple always carries its wrapper. Every node has an expanded spelling whose payload starts with `attributes` (decision 0005).

  @spelling
  Scenario: values-0001 Integer literal spelling
    Then its canonical Ion spelling is 42
    And its canonical YAML spelling is:
      """yaml
      Literal:
        IntegerLiteral: 42
      """
    And its canonical JSON spelling is { "Literal": { "IntegerLiteral": 42 } }

  @semantic
  Scenario: values-0025 Integer literal reader shorthands
    Given a Value whose canonical form is:
      """ion
      42
      """
    Then a reader of JSON accepts { "Literal": 42 }
    And a reader of JSON accepts 42
    And a reader of JSON accepts { "Literal": { "IntegerLiteral": { "value": 42 } } }
    And a reader of JSON accepts { "Literal": { "WholeNumberLiteral": 42 } }
    And a reader of JSON accepts { "Literal": { "attributes": {}, "literal": { "IntegerLiteral": 42 } } }

  @spelling
  Scenario Outline: values-0002 Variable spelling
    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling            |
      | Ion    | x                   |
      | YAML   | Variable: x         |
      | JSON   | { "Variable": "x" } |

  @semantic
  Scenario: values-0026 Variable reader shorthands
    Given a Value whose canonical form is:
      """ion
      x
      """
    Then a reader of JSON accepts "x"
    And a reader of JSON accepts { "Variable": { "attributes": {}, "name": "x" } }

  Scenario: values-0004 Apply
    Then its canonical YAML spelling is:
      """yaml
      Apply:
        function:
          Reference: morphir/SDK:basics#negate
        argument:
          Literal:
            IntegerLiteral: 1
      """
    And its canonical JSON spelling is { "Apply": { "function": { "Reference": "morphir/SDK:basics#negate" }, "argument": { "Literal": { "IntegerLiteral": 1 } } } }
    And a reader of JSON accepts { "Apply": { "attributes": {}, "function": { "Reference": "morphir/SDK:basics#negate" }, "argument": { "Literal": { "IntegerLiteral": 1 } } } }

  Scenario: values-0005 If-then-else member names
    Decision 0006: the schema's `then` and `else` are canonical; the Rust encoder's `thenBranch` and `elseBranch` are accepted for one release. Bead morphir-ir-v4-stabilize.3.

    Then its canonical YAML spelling is:
      """yaml
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
      """
    And its canonical JSON spelling is { "IfThenElse": { "condition": { "Literal": { "BoolLiteral": true } }, "then": { "Literal": { "IntegerLiteral": 1 } }, "else": { "Literal": { "IntegerLiteral": 2 } } } }
    And a reader of JSON accepts { "IfThenElse": { "attributes": {}, "condition": { "Literal": { "BoolLiteral": true } }, "then": { "Literal": { "IntegerLiteral": 1 } }, "else": { "Literal": { "IntegerLiteral": 2 } } } }
    And a reader of JSON accepts { "IfThenElse": { "condition": { "Literal": { "BoolLiteral": true } }, "thenBranch": { "Literal": { "IntegerLiteral": 1 } }, "elseBranch": { "Literal": { "IntegerLiteral": 2 } } } } with warning legacy_spelling

  Scenario: values-0006 Field access member names
    Decision 0006: `target` and `name`; the older `subject` and `fieldName` are accepted for one release.

    Then its canonical YAML spelling is:
      """yaml
      Field:
        target:
          Variable: record
        name: field-name
      """
    And its canonical JSON spelling is { "Field": { "target": { "Variable": "record" }, "name": "field-name" } }
    And a reader of JSON accepts { "Field": { "attributes": {}, "target": { "Variable": "record" }, "name": "field-name" } }
    And a reader of JSON accepts { "Field": { "subject": { "Variable": "record" }, "fieldName": "field-name" } } with warning legacy_spelling

  @spelling
  Scenario: values-0007 Tuple spelling
    Decision 0009: a Tuple always carries its wrapper; a bare array at value position is a List.

    Then its canonical Ion spelling is:
      """ion
      (
        tuple
        x
        1
      )
      """
    And its canonical YAML spelling is:
      """yaml
      Tuple:
        - Variable: x
        - Literal:
            IntegerLiteral: 1
      """
    And its canonical JSON spelling is { "Tuple": [{ "Variable": "x" }, { "Literal": { "IntegerLiteral": 1 } }] }

  @semantic
  Scenario: values-0029 Tuple reader forms
    Given a Value whose canonical form is:
      """ion
      (
        tuple
        x
        1
      )
      """
    Then a reader of JSON accepts { "Tuple": { "elements": [{ "Variable": "x" }, { "Literal": { "IntegerLiteral": 1 } }] } }
    And a reader of JSON accepts { "Tuple": { "attributes": {}, "elements": [{ "Variable": "x" }, { "Literal": { "IntegerLiteral": 1 } }] } }

  @semantic
  Scenario: values-0030 Bare array reads as a List
    Then a reader of JSON reads [{ "Variable": "x" }, { "Literal": { "IntegerLiteral": 1 } }] as a List

  @spelling
  Scenario: values-0008 List spelling
    Decision 0009 closed bead morphir-ir-v4-stabilize.4: a bare array is a List, a bare number is an IntegerLiteral or FloatLiteral by its lexeme, and a bare boolean is a BoolLiteral. Writers keep the wrapped forms.

    Then its canonical Ion spelling is:
      """ion
      (
        list
        1
        2
        3
      )
      """
    And its canonical YAML spelling is:
      """yaml
      List:
        - Literal:
            IntegerLiteral: 1
        - Literal:
            IntegerLiteral: 2
        - Literal:
            IntegerLiteral: 3
      """
    And its canonical JSON spelling is { "List": [{ "Literal": { "IntegerLiteral": 1 } }, { "Literal": { "IntegerLiteral": 2 } }, { "Literal": { "IntegerLiteral": 3 } }] }

  @semantic
  Scenario: values-0031 List reader forms
    Given a Value whose canonical form is:
      """ion
      (
        list
        1
        2
        3
      )
      """
    Then a reader of JSON accepts [1, 2, 3]
    And a reader of JSON accepts { "List": [1, 2, 3] }
    And a reader of JSON accepts { "List": { "items": [1, 2, 3] } }
    And a reader of JSON accepts { "List": { "attributes": {}, "items": [1, 2, 3] } }

  Scenario: values-0009 Hole
    Decision 0008: Hole stays a value expression with an optional `expectedType`; the Native and External expressions are removed, and a reader refuses them as unknown nodes. Native and external operations are definition bodies (definitions-0007).

    Then its canonical YAML spelling is:
      """yaml
      Hole:
        reason:
          UnresolvedReference:
            target: my-org/project:module#deleted
      """
    And its canonical JSON spelling is { "Hole": { "reason": { "UnresolvedReference": { "target": "my-org/project:module#deleted" } } } }
    And a reader of JSON accepts { "Hole": { "attributes": {}, "reason": { "UnresolvedReference": { "target": "my-org/project:module#deleted" } } } }

  Scenario Outline: values-0009 Hole
    Then a reader of <format> rejects <input> with <diagnostic>

    Examples:
      | format | input                                                                                                | diagnostic   |
      | JSON   | { "Native": { "fqname": "morphir/SDK:basics#add", "nativeInfo": { "hint": { "Arithmetic": {} } } } } | unknown_node |
      | JSON   | { "External": { "externalName": "console.log", "targetPlatform": "javascript" } }                    | unknown_node |

  @spelling
  Scenario: values-0010 Unit value spelling
    Then its canonical Ion spelling is:
      """ion
      (
      )
      """
    And its canonical YAML spelling is Unit: {}
    And its canonical JSON spelling is { "Unit": {} }

  @semantic
  Scenario: values-0027 Unit value reader
    Given a Value whose canonical form is:
      """ion
      (
      )
      """
    Then a reader of JSON accepts { "Unit": { "attributes": {} } }

  @spelling
  Scenario: values-0011 Boolean literal spelling
    Then its canonical Ion spelling is true
    And its canonical YAML spelling is:
      """yaml
      Literal:
        BoolLiteral: true
      """
    And its canonical JSON spelling is { "Literal": { "BoolLiteral": true } }

  @semantic
  Scenario: values-0028 Bare booleans are literals
    Decision 0009. A bare `42` is an IntegerLiteral and a bare `true` a BoolLiteral; `4.0` is a FloatLiteral because its lexeme has a point. A bare string is never a StringLiteral (values-0002).

    Given a Value whose canonical form is:
      """ion
      true
      """
    Then a reader of JSON accepts true

  Scenario: values-0012 Bare number lexemes
    Then its canonical YAML spelling is:
      """yaml
      Literal:
        FloatLiteral: 4.0
      """
    And its canonical JSON spelling is { "Literal": { "FloatLiteral": 4.0 } }
    And a reader of JSON accepts 4.0

  Scenario: values-0013 Record value
    Decision 0004 applies to record values too; the direct field map is accepted for the window of decision 0006, and so is the Rust encoder's `attrs` spelling of `attributes`, a row of decision 0006's window table, which this case pins for values as types-0005 pins it for type expressions.

    Then its canonical YAML spelling is:
      """yaml
      Record:
        fields:
          name:
            Variable: x
          age:
            Literal:
              IntegerLiteral: 25
      """
    And its canonical JSON spelling is { "Record": { "fields": { "name": { "Variable": "x" }, "age": { "Literal": { "IntegerLiteral": 25 } } } } }
    And a reader of JSON accepts { "Record": { "attributes": {}, "fields": { "name": { "Variable": "x" }, "age": { "Literal": { "IntegerLiteral": 25 } } } } }

  Scenario Outline: values-0013 Record value
    Then a reader of <format> accepts <input> with warning <warning>

    Examples:
      | format | input                                                                                                                    | warning         |
      | JSON   | { "Record": { "attrs": {}, "fields": { "name": { "Variable": "x" }, "age": { "Literal": { "IntegerLiteral": 25 } } } } } | legacy_spelling |
      | JSON   | { "Record": { "name": { "Variable": "x" }, "age": { "Literal": { "IntegerLiteral": 25 } } } }                            | legacy_spelling |

  @spelling
  Scenario: values-0014 Constructor spelling
    Then its canonical Ion spelling is:
      """ion
      (
        constructor
        'morphir/SDK:maybe#just'
      )
      """
    And its canonical YAML spelling is Constructor: morphir/SDK:maybe#just
    And its canonical JSON spelling is { "Constructor": "morphir/SDK:maybe#just" }

  @semantic
  Scenario: values-0032 Constructor reader form
    Given a Value whose canonical form is:
      """ion
      (
        constructor
        'morphir/SDK:maybe#just'
      )
      """
    Then a reader of JSON accepts { "Constructor": { "attributes": {}, "fqname": "morphir/SDK:maybe#just" } }

  @spelling
  Scenario: values-0015 Field function spelling
    Then its canonical Ion spelling is:
      """ion
      (
        fieldFunction
        name
      )
      """
    And its canonical YAML spelling is FieldFunction: name
    And its canonical JSON spelling is { "FieldFunction": "name" }

  @semantic
  Scenario: values-0033 Field function reader form
    Given a Value whose canonical form is:
      """ion
      (
        fieldFunction
        name
      )
      """
    Then a reader of JSON accepts { "FieldFunction": { "attributes": {}, "name": "name" } }

  Scenario: values-0016 Lambda
    Then its canonical YAML spelling is:
      """yaml
      Lambda:
        pattern:
          AsPattern:
            pattern:
              WildcardPattern: {}
            name: x
        body:
          Variable: x
      """
    And its canonical JSON spelling is { "Lambda": { "pattern": { "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }, "body": { "Variable": "x" } } }
    And a reader of JSON accepts { "Lambda": { "attributes": {}, "pattern": { "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }, "body": { "Variable": "x" } } }

  Scenario: values-0017 Let definition member names
    Decision 0006: `name`, `definition`, and `in`; the spec's older `valueName`, `valueDefinition`, and `inValue` are accepted for one release.

    Then its canonical YAML spelling is:
      """yaml
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
      """
    And its canonical JSON spelling is { "LetDefinition": { "name": "x", "definition": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Literal": { "IntegerLiteral": 1 } } } }, "in": { "Variable": "x" } } }
    And a reader of JSON accepts { "LetDefinition": { "attributes": {}, "name": "x", "definition": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Literal": { "IntegerLiteral": 1 } } } }, "in": { "Variable": "x" } } }
    And a reader of JSON accepts { "LetDefinition": { "valueName": "x", "valueDefinition": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Literal": { "IntegerLiteral": 1 } } } }, "inValue": { "Variable": "x" } } } with warning legacy_spelling

  Scenario: values-0018 Let recursion
    Then its canonical YAML spelling is:
      """yaml
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
      """
    And its canonical JSON spelling is { "LetRecursion": { "definitions": { "f": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "f" } } } }, "in": { "Variable": "f" } } }
    And a reader of JSON accepts { "LetRecursion": { "attributes": {}, "definitions": { "f": { "ExpressionBody": { "inputTypes": {}, "outputType": "morphir/SDK:basics#int", "body": { "Variable": "f" } } } }, "in": { "Variable": "f" } } }

  Scenario: values-0019 Destructure
    Then its canonical YAML spelling is:
      """yaml
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
      """
    And its canonical JSON spelling is { "Destructure": { "pattern": { "TuplePattern": [{ "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "a" } }, { "WildcardPattern": {} }] }, "value": { "Variable": "pair" }, "in": { "Variable": "a" } } }
    And a reader of JSON accepts { "Destructure": { "attributes": {}, "pattern": { "TuplePattern": [{ "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "a" } }, { "WildcardPattern": {} }] }, "value": { "Variable": "pair" }, "in": { "Variable": "a" } } }

  Scenario: values-0020 Pattern match
    Then its canonical YAML spelling is:
      """yaml
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
      """
    And its canonical JSON spelling is { "PatternMatch": { "value": { "Variable": "x" }, "cases": [{ "pattern": { "LiteralPattern": { "IntegerLiteral": 0 } }, "body": { "Literal": { "BoolLiteral": true } } }, { "pattern": { "WildcardPattern": {} }, "body": { "Literal": { "BoolLiteral": false } } }] } }
    And a reader of JSON accepts { "PatternMatch": { "attributes": {}, "value": { "Variable": "x" }, "cases": [{ "pattern": { "LiteralPattern": { "IntegerLiteral": 0 } }, "body": { "Literal": { "BoolLiteral": true } } }, { "pattern": { "WildcardPattern": {} }, "body": { "Literal": { "BoolLiteral": false } } }] } }

  Scenario: values-0021 Update record
    Then its canonical YAML spelling is:
      """yaml
      UpdateRecord:
        target:
          Variable: record
        fields:
          name:
            Literal:
              StringLiteral: new
      """
    And its canonical JSON spelling is { "UpdateRecord": { "target": { "Variable": "record" }, "fields": { "name": { "Literal": { "StringLiteral": "new" } } } } }
    And a reader of JSON accepts { "UpdateRecord": { "attributes": {}, "target": { "Variable": "record" }, "fields": { "name": { "Literal": { "StringLiteral": "new" } } } } }

  @compare:attributes
  Scenario: values-0022 Attributes are kept when compared with them
    Then its canonical YAML spelling is:
      """yaml
      Variable:
        attributes:
          source:
            startLine: 3
            startColumn: 5
            endLine: 3
            endColumn: 6
        name: x
      """
    And its canonical JSON spelling is { "Variable": { "attributes": { "source": { "startLine": 3, "startColumn": 5, "endLine": 3, "endColumn": 6 } }, "name": "x" } }

  @spelling
  Scenario: values-0023 Reference spelling in three profiles
    Derived from values-0003. The Ion text follows the canonical writer's
    multiline S-expression layout.

    Then its canonical Ion spelling is:
      """ion
      (
        ref
        'morphir/SDK:basics#add'
      )
      """
    And its canonical YAML spelling is Reference: morphir/SDK:basics#add
    And its canonical JSON spelling is { "Reference": "morphir/SDK:basics#add" }

  @semantic
  Scenario: values-0024 Reference meaning across profiles
    Derived from values-0003. The expected meaning belongs to the kit's
    independently parsed Ion reference.

    Given a Value whose canonical form is:
      """ion
      (
        ref
        'morphir/SDK:basics#add'
      )
      """
    Then a reader of JSON accepts "morphir/SDK:basics#add"
    And a reader of JSON accepts { "Reference": { "attributes": {}, "fqname": "morphir/SDK:basics#add" } }
    And a reader of YAML accepts Reference: morphir/SDK:basics#add
