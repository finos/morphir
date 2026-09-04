# Names

Canonical name strings and the legacy word arrays. The generated corpus at `docs/spec/ir/fixtures/naming-conformance.json` covers the full grammar; these cases pin the encodings the IR profiles use.

## names-0001: Initialism as uppercase segment {node=Name}

Decision 0001. A run of two or more single-letter legacy words decodes to one initialism.

```yaml canonical
value-in-USD
```

```json canonical
"value-in-USD"
```

```json accepted
["value", "in", "u", "s", "d"]
```

## names-0002: Single-letter type variable is a word {node=Name}

Decision 0001, consequence 4. A run of one stays a word, so a type variable canonicalizes as `a`, never `(a)` or `A`.

```yaml canonical
a
```

```json accepted
["a"]
```

## names-0003: Retired parenthesized encoding is rejected {node=Name status=pending}

Decision 0001 retired `value-in-(usd)`. GitHub #793 owns the books fixture that still carries it.

```json rejected diagnostic=invalid_name
"value-in-(usd)"
```

```json rejected diagnostic=invalid_name
"value-in-Usd"
```

## names-0004: Path string and legacy array {node=Path}

```yaml canonical
morphir/SDK
```

```json accepted
[["morphir"], ["s", "d", "k"]]
```

## names-0005: FQName string and legacy array {node=FQName}

```yaml canonical
morphir/SDK:list#map
```

```json accepted
[[["morphir"], ["s", "d", "k"]], [["list"]], ["map"]]
```
