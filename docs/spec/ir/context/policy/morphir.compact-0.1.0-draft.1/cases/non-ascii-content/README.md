# Non-ASCII content

The `v4-type` record with a doc string, `Montant réduit après la taxe régionale.`: 39 characters, three of them
(`é`, `è`, `é`) two bytes each in UTF-8, so 42 bytes. Morphir names are ASCII, so non-ASCII text can only be content.

**Occurrences in first-use order.** In `def`, `TypeAliasDefinition` comes before `access` and `doc`; the fields
`base`, `bonus`, `rebate`; then `name`. The doc string is not a position.

1. F (`fqNames`), three times, O = 101. Id `a`: S = 264 > E = 106: aliased as `a`.
2. `order-total` (`names`), once: S = 0 ≤ E = 18, spelled out.

**Loss decision.** Overhead = 118 + 12 + 105 + 0 = 235. Savings 264 > 235: the envelope is written, 29 bytes smaller.
The doc string is in both files, so it does not change either decision, but it is in every size: 521 bytes plain and
492 bytes compacted count it as 42 + 2 bytes with its quotes. JCS writes it raw: an escaping writer would spell each
of the three letters as a six-byte `\u` escape, adding 12 bytes and changing the expected bytes.
