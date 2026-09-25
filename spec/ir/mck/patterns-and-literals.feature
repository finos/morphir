Feature: Patterns and literals

  @node:Literal
  Scenario Outline: patterns-and-literals-0001 Integer literal renamed
    `WholeNumberLiteral` is accepted on input and never written.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                 |
      | YAML   | IntegerLiteral: 42       |
      | JSON   | { "IntegerLiteral": 42 } |

  @node:Literal
  Scenario Outline: patterns-and-literals-0001 Integer literal renamed
    Then a reader of <format> accepts <input>

    Examples:
      | format | input                                 |
      | JSON   | { "WholeNumberLiteral": 42 }          |
      | JSON   | { "IntegerLiteral": { "value": 42 } } |

  @node:Literal
  Scenario Outline: patterns-and-literals-0002 Decimal literal keeps its text
    A decimal is carried as a string so no binding coerces it to a float.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                      |
      | YAML   | DecimalLiteral: "10.50"       |
      | JSON   | { "DecimalLiteral": "10.50" } |

  @node:Pattern
  Scenario: patterns-and-literals-0003 Tuple pattern
    Then its canonical YAML spelling is:
      """yaml
      TuplePattern:
        - WildcardPattern: {}
        - AsPattern:
            pattern:
              WildcardPattern: {}
            name: x
      """
    And its canonical JSON spelling is { "TuplePattern": [{ "WildcardPattern": {} }, { "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }] }

  @node:Pattern
  Scenario Outline: patterns-and-literals-0003 Tuple pattern
    Then a reader of <format> accepts <input>

    Examples:
      | format | input                                                                                                                                                                                         |
      | JSON   | [{ "WildcardPattern": {} }, { "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }]                                                                                           |
      | JSON   | { "TuplePattern": { "patterns": [{ "WildcardPattern": {} }, { "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }] } }                                                       |
      | JSON   | { "TuplePattern": { "attributes": {}, "patterns": [{ "WildcardPattern": {} }, { "AsPattern": { "attributes": {}, "pattern": { "WildcardPattern": { "attributes": {} } }, "name": "x" } }] } } |

  @node:Pattern
  Scenario: patterns-and-literals-0004 Literal pattern shorthand
    Then its canonical YAML spelling is:
      """yaml
      LiteralPattern:
        IntegerLiteral: 42
      """
    And its canonical JSON spelling is { "LiteralPattern": { "IntegerLiteral": 42 } }

  @node:Pattern
  Scenario Outline: patterns-and-literals-0004 Literal pattern shorthand
    Then a reader of <format> accepts <input>

    Examples:
      | format | input                                                                           |
      | JSON   | { "LiteralPattern": 42 }                                                        |
      | JSON   | { "LiteralPattern": { "attributes": {}, "literal": { "IntegerLiteral": 42 } } } |

  @node:Literal
  Scenario: patterns-and-literals-0005 Document literal
    Decision 0013: the seventh literal carries a schema-less JSON-like tree verbatim, typed as `morphir/SDK:document#document`. Its payload is the document itself, so there is no `{ "value": .. }` spelling: `{ "DocumentLiteral": { "value": 1 } }` is the one-member document `{"value": 1}`. Number lexemes are preserved; a backend that reads `9007199254740993` through a 64-bit float fails this case visibly.

    Then its canonical YAML spelling is:
      """yaml
      DocumentLiteral:
        name: Alice
        age: 30
        tags: [admin, user]
        metadata: null
      """
    And its canonical JSON spelling is { "DocumentLiteral": { "name": "Alice", "age": 30, "tags": ["admin", "user"], "metadata": null } }

  @node:Literal
  Scenario: patterns-and-literals-0006 Document literal keeps large integers
    Then its canonical YAML spelling is:
      """yaml
      DocumentLiteral:
        id: 9007199254740993
        ratio: 0.10
      """
    And its canonical JSON spelling is { "DocumentLiteral": { "id": 9007199254740993, "ratio": 0.10 } }

  @node:Pattern
  Scenario: patterns-and-literals-0007 A document cannot be pattern matched
    Decision 0013: no `LiteralPattern` on a document.

    Then a reader of JSON rejects { "LiteralPattern": { "DocumentLiteral": { "name": "Alice" } } } with invalid_literal

  @node:Pattern
  Scenario Outline: patterns-and-literals-0008 Nullary patterns
    Wildcard, empty-list and unit patterns take an empty payload, or `attributes` alone.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                  |
      | YAML   | WildcardPattern: {}       |
      | JSON   | { "WildcardPattern": {} } |

  @node:Pattern
  Scenario: patterns-and-literals-0008 Nullary patterns
    Then a reader of JSON accepts { "WildcardPattern": { "attributes": {} } }

  @node:Pattern
  Scenario Outline: patterns-and-literals-0009 Empty list and unit patterns
    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                   |
      | YAML   | EmptyListPattern: {}       |
      | JSON   | { "EmptyListPattern": {} } |

  @node:Pattern
  Scenario: patterns-and-literals-0009 Empty list and unit patterns
    Then a reader of JSON accepts { "EmptyListPattern": { "attributes": {} } }

  @node:Pattern
  Scenario: patterns-and-literals-0010 Constructor pattern
    Then its canonical YAML spelling is:
      """yaml
      ConstructorPattern:
        fqname: morphir/SDK:maybe#just
        patterns:
          - AsPattern:
              pattern:
                WildcardPattern: {}
              name: x
      """
    And its canonical JSON spelling is { "ConstructorPattern": { "fqname": "morphir/SDK:maybe#just", "patterns": [{ "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }] } }
    And a reader of JSON accepts { "ConstructorPattern": { "attributes": {}, "fqname": "morphir/SDK:maybe#just", "patterns": [{ "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }] } }

  @node:Pattern
  Scenario: patterns-and-literals-0011 Head-tail and unit patterns
    Then its canonical YAML spelling is:
      """yaml
      HeadTailPattern:
        head:
          AsPattern:
            pattern:
              WildcardPattern: {}
            name: x
        tail:
          UnitPattern: {}
      """
    And its canonical JSON spelling is { "HeadTailPattern": { "head": { "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }, "tail": { "UnitPattern": {} } } }
    And a reader of JSON accepts { "HeadTailPattern": { "attributes": {}, "head": { "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }, "tail": { "UnitPattern": { "attributes": {} } } } }

  @node:Pattern @compare:attributes
  Scenario: patterns-and-literals-0012 Attributes are kept when compared with them
    Then its canonical YAML spelling is:
      """yaml
      AsPattern:
        attributes:
          source:
            startLine: 2
            startColumn: 1
            endLine: 2
            endColumn: 2
        pattern:
          WildcardPattern: {}
        name: x
      """
    And its canonical JSON spelling is { "AsPattern": { "attributes": { "source": { "startLine": 2, "startColumn": 1, "endLine": 2, "endColumn": 2 } }, "pattern": { "WildcardPattern": {} }, "name": "x" } }

  @node:Literal
  Scenario Outline: patterns-and-literals-0013 Character literal
    A `CharLiteral` carries one character as a string, because JSON has no character type. One character means one code point, so an astral character is a single `CharLiteral` and a two-character string is not a character at all.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling               |
      | YAML   | CharLiteral: a         |
      | JSON   | { "CharLiteral": "a" } |

  @node:Literal
  Scenario: patterns-and-literals-0013 Character literal
    Then a reader of JSON accepts { "CharLiteral": { "value": "a" } }
    And a reader of JSON rejects { "CharLiteral": "ab" } with invalid_literal

  @node:Literal
  Scenario Outline: patterns-and-literals-0014 A date-looking plain scalar is a string
    YAML 1.2 core has no implicit timestamps, and the YAML profile forbids implicit coercions, so a plain `2026-01-15` where a literal is expected is a `StringLiteral` and nothing else. YAML profile page, "Scalar resolution".

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                          |
      | YAML   | StringLiteral: 2026-01-15         |
      | JSON   | { "StringLiteral": "2026-01-15" } |

  @node:Literal
  Scenario Outline: patterns-and-literals-0015 Octal and hexadecimal integers are not accepted
    An IR integer literal carries its decimal lexeme. YAML 1.2 core resolves `0o17` and `0xF` to integers, but neither is a JSON lexeme, so the profile refuses them with `invalid_literal` and asks for decimal instead of inventing a spelling. YAML profile page, "Scalar resolution".

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                 |
      | YAML   | IntegerLiteral: 15       |
      | JSON   | { "IntegerLiteral": 15 } |

  @node:Literal
  Scenario Outline: patterns-and-literals-0015 Octal and hexadecimal integers are not accepted
    Then a reader of <format> rejects <input> with <diagnostic>

    Examples:
      | format | input                | diagnostic      |
      | YAML   | IntegerLiteral: 0o17 | invalid_literal |
      | YAML   | IntegerLiteral: 0xF  | invalid_literal |

  @node:Literal
  Scenario Outline: patterns-and-literals-0016 A decimal literal is a decimal lexeme
    A `DecimalLiteral` is a genuine decimal, not text. Its payload is a string because JSON numbers are floats, but the string must spell a decimal: `[+-]?(digits(.digits?)?|.digits)([eE][+-]?digits)?`, no whitespace, no `_`, no hex, no `NaN` or `Infinity`. The lexeme is kept as written (patterns-and-literals-0002), so trailing zeros survive: `-0.00` is not `0`. Anything else is `invalid_literal`. v4 schema page, "Literals".

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                      |
      | YAML   | DecimalLiteral: "-0.00"       |
      | JSON   | { "DecimalLiteral": "-0.00" } |

  @node:Literal
  Scenario Outline: patterns-and-literals-0016 A decimal literal is a decimal lexeme
    Then a reader of <format> rejects <input> with <diagnostic>

    Examples:
      | format | input                         | diagnostic      |
      | JSON   | { "DecimalLiteral": "ten" }   | invalid_literal |
      | JSON   | { "DecimalLiteral": "" }      | invalid_literal |
      | JSON   | { "DecimalLiteral": "1_000" } | invalid_literal |
      | JSON   | { "DecimalLiteral": "NaN" }   | invalid_literal |
      | JSON   | { "DecimalLiteral": 10.5 }    | invalid_literal |

  @node:Literal
  Scenario Outline: patterns-and-literals-0017 A decimal lexeme may carry an exponent
    The grammar admits an exponent; the lexeme stays as written, so a reader does not expand `1e-7` to `0.0000001`. In YAML the lexeme is quoted, because a plain `1e-7` would resolve to a float.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                     |
      | YAML   | DecimalLiteral: "1e-7"       |
      | JSON   | { "DecimalLiteral": "1e-7" } |

  @node:Literal
  Scenario Outline: patterns-and-literals-0018 A decimal lexeme may omit the integer part
    `.5` is a decimal lexeme, and so is `12.`; neither is rewritten.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                   |
      | YAML   | DecimalLiteral: ".5"       |
      | JSON   | { "DecimalLiteral": ".5" } |

  @node:Literal
  Scenario Outline: patterns-and-literals-0019 An integer literal has arbitrary precision
    An `IntegerLiteral` carries a whole-number lexeme of any size; a binding that reads it through a 64-bit integer fails this case visibly. The lexeme is written back unchanged.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                                   |
      | YAML   | IntegerLiteral: 18446744073709551616       |
      | JSON   | { "IntegerLiteral": 18446744073709551616 } |

  @node:Literal
  Scenario Outline: patterns-and-literals-0020 A negative integer literal below the 64-bit range
    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                                   |
      | YAML   | IntegerLiteral: -9223372036854775809       |
      | JSON   | { "IntegerLiteral": -9223372036854775809 } |
