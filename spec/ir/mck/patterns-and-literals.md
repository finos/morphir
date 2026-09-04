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
