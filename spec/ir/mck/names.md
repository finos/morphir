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

```json canonical
"a"
```

```json accepted
["a"]
```

## names-0003: Retired parenthesized encoding is rejected {node=Name}

Decision 0001 retired `value-in-(usd)`. GitHub #793 owns the books fixture that still carries it. A mixed-case segment such as Usd is also invalid: a segment is all lowercase or all uppercase, never mixed.

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

```json canonical
"morphir/SDK"
```

```json accepted
[["morphir"], ["s", "d", "k"]]
```

## names-0005: FQName string and legacy array {node=FQName}

```yaml canonical
morphir/SDK:list#map
```

```json canonical
"morphir/SDK:list#map"
```

```json accepted
[[["morphir"], ["s", "d", "k"]], [["list"]], ["map"]]
```

## names-0006: The SDK package name {node=Path}

Decision 0011: the SDK's canonical package name is `morphir/SDK`, because morphir-elm's `Path.fromString` splits `SDK` into single-letter words that decision 0001 decodes as one initialism. `morphir/sdk` is a different, valid name and is not rejected; distributions-0005 pins the dependency key.

```yaml canonical
morphir/SDK
```

```json canonical
"morphir/SDK"
```

```json accepted
[["morphir"], ["s", "d", "k"]]
```

## names-0007: Legacy array items may be digits {node=Name}

Decision 0012: both schemas use the core legacy word grammar `^[a-z0-9]+$`, so a digits-only word is legal. `["f", "r", "2052", "a"]` decodes as the naming corpus records: the letter run `f r` is one initialism, `2052` breaks the run, and the trailing `a` is a run of one, so a word.

```yaml canonical
item-2
```

```json canonical
"item-2"
```

```json accepted
["item", "2"]
```

## names-0008: A digit word breaks an initialism run {node=Name}

```yaml canonical
FR-2052-a
```

```json canonical
"FR-2052-a"
```

```json accepted
["f", "r", "2052", "a"]
```
