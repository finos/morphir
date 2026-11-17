# Loss boundary: savings equal to the overhead

The `loss` type file with its two fields of type X, a 158-byte FQName chosen so that the savings equal the envelope's
overhead exactly. `loss-boundary-accepted` is the same file with a spelling one byte longer.

X = `acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment-for-orders-shipped-to-customers-outside-the-primary-region`.
`len(X)` = 45 (`acme/order-management:pricing/discount-rules#`) + 113 (the name) = 158, so `O` = 160 with its quotes.

**Occurrences in first-use order.** The fields `base`, `rebate`, then `name`.

1. X (`fqNames`) at `base` and `rebate`, O = 160 each. Id `a`, R = 13: S = 2 × (160 − 13) = 294;
   E = 1 + 158 + 6 = 165. 294 > 165: aliased as `a`.
2. `order-total` (`names`), once: S = 13 − 13 = 0 ≤ E = 18, spelled out.

**Loss decision.** One table, `fqNames`, with one entry: overhead = 118 + 12 + (1 + 158 + 5) + (1 − 1) = 294.
Savings 294 = 294. The rule asks for savings greater than the overhead, so the writer writes the plain document as JCS,
with no envelope, and its result says that no alias was worth its cost.

**Bytes.** The plain JCS file is 158 bytes besides its two values: `{"def":{"TypeAliasDefinition":{"typeExp":{"Record":{"fields":{"base":`
(69), `,"rebate":` (10), `}}},"typeParams":[]}` (20), `,"access":"Public"}` (19), `,"formatVersion":4` (18),
`,"name":"order-total"` (21) and `}` (1). With the two values it is 158 + 2 × 160 = 478 bytes, the expected file.

The envelope it declines would also be 478 bytes: `{"$schema":"` (12), the URL (79), `","context":{` (13),
`"fqNames":{` (11), `"a":"X"` (164), `}` (1), `},"document":` (13), the document with two 13-byte references
(158 + 26 = 184) and `}` (1). Equal size is not smaller, so it is not written.
