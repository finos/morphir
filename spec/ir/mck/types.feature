@node:Type
Feature: Types
  Type expressions. The bare-array rule closed bead morphir-j442: a bare array is a Tuple, and a parameterized reference always carries the `Reference` wrapper. Every node has a compact spelling and an expanded spelling whose payload starts with `attributes` (decision 0005); the expanded spelling with empty attributes is accepted and never written.

  Scenario Outline: types-0001 Type variable
    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling |
      | YAML   | a        |
      | JSON   | "a"      |

  Scenario: types-0001 Type variable
    Then a reader of JSON accepts { "Variable": { "attributes": {}, "name": "a" } }

  Scenario Outline: types-0002 Reference without arguments
    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                 |
      | YAML   | morphir/SDK:basics#int   |
      | JSON   | "morphir/SDK:basics#int" |

  Scenario Outline: types-0002 Reference without arguments
    Then a reader of <format> accepts <input>

    Examples:
      | format | input                                                                     |
      | JSON   | { "Reference": "morphir/SDK:basics#int" }                                 |
      | JSON   | { "Reference": { "fqname": "morphir/SDK:basics#int" } }                   |
      | JSON   | { "Reference": { "fqname": "morphir/SDK:basics#int", "args": [] } }       |
      | JSON   | { "Reference": { "attributes": {}, "fqname": "morphir/SDK:basics#int" } } |

  Scenario Outline: types-0003 Reference with one argument
    Closes bead morphir-ir-v4-stabilize.2 once the Rust decoder agrees.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                                        |
      | YAML   | Reference: ["morphir/SDK:list#list", a]         |
      | JSON   | { "Reference": ["morphir/SDK:list#list", "a"] } |

  Scenario Outline: types-0003 Reference with one argument
    Then a reader of <format> accepts <input>

    Examples:
      | format | input                                                                                   |
      | JSON   | { "Reference": { "fqname": "morphir/SDK:list#list", "args": ["a"] } }                   |
      | JSON   | { "Reference": { "attributes": {}, "fqname": "morphir/SDK:list#list", "args": ["a"] } } |

  Scenario: types-0003 Reference with one argument
    Then a reader of YAML reads ["morphir/SDK:list#list", a] as a Tuple

  Scenario Outline: types-0004 Tuple type
    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                                                             |
      | YAML   | Tuple: ["morphir/SDK:basics#int", "morphir/SDK:string#string"]       |
      | JSON   | { "Tuple": ["morphir/SDK:basics#int", "morphir/SDK:string#string"] } |

  Scenario Outline: types-0004 Tuple type
    Then a reader of <format> accepts <input>

    Examples:
      | format | input                                                                                                  |
      | JSON   | ["morphir/SDK:basics#int", "morphir/SDK:string#string"]                                                |
      | JSON   | { "Tuple": { "elements": ["morphir/SDK:basics#int", "morphir/SDK:string#string"] } }                   |
      | JSON   | { "Tuple": { "attributes": {}, "elements": ["morphir/SDK:basics#int", "morphir/SDK:string#string"] } } |

  Scenario: types-0005 Record type
    Decision 0004: fields live under a `fields` member, so `attributes` can sit beside them. The field map directly under `Record`, which the schema documented until 2026-09-04, is accepted for the one-release window of decision 0006 and reported as `legacy_spelling`. The Rust encoder's `attrs` is the other window spelling a Record payload takes — it is a row of decision 0006's window table, not a decision of its own; this case pins it for type expressions and values-0013 pins it for values.

    Then its canonical YAML spelling is:
      """yaml
      Record:
        fields:
          name: morphir/SDK:string#string
          age: morphir/SDK:basics#int
      """
    And its canonical JSON spelling is { "Record": { "fields": { "name": "morphir/SDK:string#string", "age": "morphir/SDK:basics#int" } } }
    And a reader of JSON accepts { "Record": { "attributes": {}, "fields": { "name": "morphir/SDK:string#string", "age": "morphir/SDK:basics#int" } } }

  Scenario Outline: types-0005 Record type
    Then a reader of <format> accepts <input> with warning <warning>

    Examples:
      | format | input                                                                                                             | warning         |
      | JSON   | { "Record": { "attrs": {}, "fields": { "name": "morphir/SDK:string#string", "age": "morphir/SDK:basics#int" } } } | legacy_spelling |
      | JSON   | { "Record": { "name": "morphir/SDK:string#string", "age": "morphir/SDK:basics#int" } }                            | legacy_spelling |

  Scenario: types-0006 Extensible record type
    Then its canonical YAML spelling is:
      """yaml
      ExtensibleRecord:
        variable: r
        fields:
          email: morphir/SDK:string#string
      """
    And its canonical JSON spelling is { "ExtensibleRecord": { "variable": "r", "fields": { "email": "morphir/SDK:string#string" } } }
    And a reader of JSON accepts { "ExtensibleRecord": { "attributes": {}, "variable": "r", "fields": { "email": "morphir/SDK:string#string" } } }

  Scenario: types-0007 Function type
    Decision 0007: a Function type declares a `parameterType`. `argumentType` (the pre-decision schema) and `arg`/`result` (the Rust encoder) are accepted for the window of decision 0006. Bead morphir-ir-v4-stabilize.3.

    Then its canonical YAML spelling is:
      """yaml
      Function:
        parameterType: morphir/SDK:basics#int
        returnType: morphir/SDK:string#string
      """
    And its canonical JSON spelling is { "Function": { "parameterType": "morphir/SDK:basics#int", "returnType": "morphir/SDK:string#string" } }
    And a reader of JSON accepts { "Function": { "attributes": {}, "parameterType": "morphir/SDK:basics#int", "returnType": "morphir/SDK:string#string" } }

  Scenario Outline: types-0007 Function type
    Then a reader of <format> accepts <input> with warning <warning>

    Examples:
      | format | input                                                                                                   | warning         |
      | JSON   | { "Function": { "argumentType": "morphir/SDK:basics#int", "returnType": "morphir/SDK:string#string" } } | legacy_spelling |
      | JSON   | { "Function": { "arg": "morphir/SDK:basics#int", "result": "morphir/SDK:string#string" } }              | legacy_spelling |

  Scenario Outline: types-0008 Unit type
    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling       |
      | YAML   | Unit: {}       |
      | JSON   | { "Unit": {} } |

  Scenario: types-0008 Unit type
    Then a reader of JSON accepts { "Unit": { "attributes": {} } }

  Scenario Outline: types-0009 Attributes on type expressions
    Decision 0005: `attributes` is the optional first member of every expanded payload, and an empty one is never written. `attrs` is the Rust encoder's spelling, accepted for the window of decision 0006.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling |
      | YAML   | a        |
      | JSON   | "a"      |

  Scenario: types-0009 Attributes on type expressions
    Then a reader of JSON accepts { "Variable": { "attributes": {}, "name": "a" } }
    And a reader of JSON accepts { "Variable": { "attrs": {}, "name": "a" } } with warning legacy_spelling

  @compare:attributes
  Scenario: types-0010 Attributes are kept when compared with them
    A source location makes the expanded spelling the canonical one.

    Then its canonical YAML spelling is:
      """yaml
      Variable:
        attributes:
          source:
            startLine: 1
            startColumn: 1
            endLine: 1
            endColumn: 2
        name: a
      """
    And its canonical JSON spelling is { "Variable": { "attributes": { "source": { "startLine": 1, "startColumn": 1, "endLine": 1, "endColumn": 2 } }, "name": "a" } }

  Scenario Outline: types-0011 Incompleteness is not a type expression
    Decision 0008 makes `Hole` a value expression (values-0009). The type-level incompleteness vocabulary — `Hole` with its reason, and `Draft` — is the v4 schema's `IncompleteTypeDefinitionBody`, which belongs to a definition, not to a type expression. A reader that meets either tag where a type belongs refuses it as an unknown node. The spellings themselves are pinned where they are read: definitions-0014 for a `Hole` with a `TypeMismatch` reason, definitions-0015 for `Draft`, and definitions-0016 for a `DeletedDuringRefactor` reason on an incomplete value definition.

    Then a reader of <format> rejects <input> with <diagnostic>

    Examples:
      | format | input                                                                                                                        | diagnostic   |
      | JSON   | { "Hole": { "reason": { "TypeMismatch": { "expected": "morphir/SDK:basics#int", "found": "morphir/SDK:string#string" } } } } | unknown_node |
      | JSON   | { "Draft": {} }                                                                                                              | unknown_node |

  Scenario Outline: types-0012 Attribute members are objects and nothing else is an attribute
    `constraints` and `extensions` are objects (v4 schema page, `TypeAttributes`); a member the schema does not name is unknown.

    Then a reader of <format> rejects <input> with <diagnostic>

    Examples:
      | format | input                                                               | diagnostic     |
      | JSON   | { "Variable": { "attributes": { "constraints": 5 }, "name": "a" } } | invalid_type   |
      | JSON   | { "Variable": { "attributes": { "colour": "red" }, "name": "a" } }  | unknown_member |
