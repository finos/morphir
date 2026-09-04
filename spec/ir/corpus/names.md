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

## names-0006: The SDK package name {node=Path status=pending}

Decision 0001 makes an uppercase segment an initialism, so the legacy array [["morphir"], ["s", "d", "k"]] decodes to morphir/SDK, and names-0004 pins that. Every published v4 example and every spec page writes morphir/sdk, which under the same decision is a different package whose second segment is the word sdk. One of them is wrong. Bead morphir-ir-v4-stabilize.1 owns the answer together with the value vocabulary, because every fixture changes with it.

## names-0007: Legacy array item grammar and the FileStem suffix {node=Name status=pending}

The core schema accepts legacy array items matching ^[a-z0-9]+$ while the document-tree schema requires ^[a-z][a-z0-9]*$, so ["item", "2"] is legal in one and not the other. The core schema's FileStem allows a __[0-9a-f]{8} truncation suffix that the naming corpus omits. Bead morphir-ir-v4-stabilize.13 applies decision 0001's consequences to both schemas; this case becomes active when it does.
