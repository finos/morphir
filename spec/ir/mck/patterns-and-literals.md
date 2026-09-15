# Patterns and literals

## patterns-and-literals-0001: Integer literal renamed {node=Literal}

`WholeNumberLiteral` is accepted on input and never written.

```yaml canonical
IntegerLiteral: 42
```

```json canonical
{ "IntegerLiteral": 42 }
```

```json accepted
{ "WholeNumberLiteral": 42 }
```

```json accepted
{ "IntegerLiteral": { "value": 42 } }
```

## patterns-and-literals-0002: Decimal literal keeps its text {node=Literal}

A decimal is carried as a string so no binding coerces it to a float.

```yaml canonical
DecimalLiteral: "10.50"
```

```json canonical
{ "DecimalLiteral": "10.50" }
```

## patterns-and-literals-0003: Tuple pattern {node=Pattern}

```yaml canonical
TuplePattern:
  - WildcardPattern: {}
  - AsPattern:
      pattern:
        WildcardPattern: {}
      name: x
```

```json canonical
{ "TuplePattern": [{ "WildcardPattern": {} }, { "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }] }
```

```json accepted
[{ "WildcardPattern": {} }, { "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }]
```

```json accepted
{ "TuplePattern": { "patterns": [{ "WildcardPattern": {} }, { "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }] } }
```

```json accepted
{ "TuplePattern": { "attributes": {}, "patterns": [{ "WildcardPattern": {} }, { "AsPattern": { "attributes": {}, "pattern": { "WildcardPattern": { "attributes": {} } }, "name": "x" } }] } }
```

## patterns-and-literals-0004: Literal pattern shorthand {node=Pattern}

```yaml canonical
LiteralPattern:
  IntegerLiteral: 42
```

```json canonical
{ "LiteralPattern": { "IntegerLiteral": 42 } }
```

```json accepted
{ "LiteralPattern": 42 }
```

```json accepted
{ "LiteralPattern": { "attributes": {}, "literal": { "IntegerLiteral": 42 } } }
```

## patterns-and-literals-0005: Document literal {node=Literal}

Decision 0013: the seventh literal carries a schema-less JSON-like tree verbatim, typed as `morphir/SDK:document#document`. Its payload is the document itself, so there is no `{ "value": .. }` spelling: `{ "DocumentLiteral": { "value": 1 } }` is the one-member document `{"value": 1}`. Number lexemes are preserved; a backend that reads `9007199254740993` through a 64-bit float fails this case visibly.

```yaml canonical
DocumentLiteral:
  name: Alice
  age: 30
  tags: [admin, user]
  metadata: null
```

```json canonical
{ "DocumentLiteral": { "name": "Alice", "age": 30, "tags": ["admin", "user"], "metadata": null } }
```

## patterns-and-literals-0006: Document literal keeps large integers {node=Literal}

```yaml canonical
DocumentLiteral:
  id: 9007199254740993
  ratio: 0.10
```

```json canonical
{ "DocumentLiteral": { "id": 9007199254740993, "ratio": 0.10 } }
```

## patterns-and-literals-0007: A document cannot be pattern matched {node=Pattern}

Decision 0013: no `LiteralPattern` on a document.

```json rejected diagnostic=invalid_literal
{ "LiteralPattern": { "DocumentLiteral": { "name": "Alice" } } }
```

## patterns-and-literals-0008: Nullary patterns {node=Pattern}

Wildcard, empty-list and unit patterns take an empty payload, or `attributes` alone.

```yaml canonical
WildcardPattern: {}
```

```json canonical
{ "WildcardPattern": {} }
```

```json accepted
{ "WildcardPattern": { "attributes": {} } }
```

## patterns-and-literals-0009: Empty list and unit patterns {node=Pattern}

```yaml canonical
EmptyListPattern: {}
```

```json canonical
{ "EmptyListPattern": {} }
```

```json accepted
{ "EmptyListPattern": { "attributes": {} } }
```

## patterns-and-literals-0010: Constructor pattern {node=Pattern}

```yaml canonical
ConstructorPattern:
  fqname: morphir/SDK:maybe#just
  patterns:
    - AsPattern:
        pattern:
          WildcardPattern: {}
        name: x
```

```json canonical
{ "ConstructorPattern": { "fqname": "morphir/SDK:maybe#just", "patterns": [{ "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }] } }
```

```json accepted
{ "ConstructorPattern": { "attributes": {}, "fqname": "morphir/SDK:maybe#just", "patterns": [{ "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }] } }
```

## patterns-and-literals-0011: Head-tail and unit patterns {node=Pattern}

```yaml canonical
HeadTailPattern:
  head:
    AsPattern:
      pattern:
        WildcardPattern: {}
      name: x
  tail:
    UnitPattern: {}
```

```json canonical
{ "HeadTailPattern": { "head": { "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }, "tail": { "UnitPattern": {} } } }
```

```json accepted
{ "HeadTailPattern": { "attributes": {}, "head": { "AsPattern": { "pattern": { "WildcardPattern": {} }, "name": "x" } }, "tail": { "UnitPattern": { "attributes": {} } } } }
```

## patterns-and-literals-0012: Attributes are kept when compared with them {node=Pattern compare=attributes}

```yaml canonical
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
```

```json canonical
{ "AsPattern": { "attributes": { "source": { "startLine": 2, "startColumn": 1, "endLine": 2, "endColumn": 2 } }, "pattern": { "WildcardPattern": {} }, "name": "x" } }
```

## patterns-and-literals-0013: Character literal {node=Literal}

A `CharLiteral` carries one character as a string, because JSON has no character type. One character means one code point, so an astral character is a single `CharLiteral` and a two-character string is not a character at all.

```yaml canonical
CharLiteral: a
```

```json canonical
{ "CharLiteral": "a" }
```

```json accepted
{ "CharLiteral": { "value": "a" } }
```

```json rejected diagnostic=invalid_literal
{ "CharLiteral": "ab" }
```

## patterns-and-literals-0014: A date-looking plain scalar is a string {node=Literal}

YAML 1.2 core has no implicit timestamps, and the YAML profile forbids implicit coercions, so a plain `2026-01-15` where a literal is expected is a `StringLiteral` and nothing else. Spec S4 scalar resolution.

```yaml canonical
StringLiteral: 2026-01-15
```

```json canonical
{ "StringLiteral": "2026-01-15" }
```

## patterns-and-literals-0015: Octal and hexadecimal integers are not accepted {node=Literal}

An IR integer literal carries its decimal lexeme. YAML 1.2 core resolves `0o17` and `0xF` to integers, but neither is a JSON lexeme, so the profile refuses them with `invalid_literal` and asks for decimal instead of inventing a spelling. Spec S4 scalar resolution.

```yaml canonical
IntegerLiteral: 15
```

```json canonical
{ "IntegerLiteral": 15 }
```

```yaml rejected diagnostic=invalid_literal
IntegerLiteral: 0o17
```

```yaml rejected diagnostic=invalid_literal
IntegerLiteral: 0xF
```
