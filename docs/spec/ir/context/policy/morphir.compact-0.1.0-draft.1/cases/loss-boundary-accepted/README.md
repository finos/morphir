# Loss boundary: savings one byte above the overhead

The `loss-boundary-declined` file with X replaced by Y, whose name says `domestic` where X says `primary`: one byte
longer, so the savings exceed the overhead by exactly one byte.

Y = `acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment-for-orders-shipped-to-customers-outside-the-domestic-region`.
`len(Y)` = 45 + 114 = 159, so `O` = 161 with its quotes.

**Occurrences in first-use order.** The fields `base`, `rebate`, then `name`.

1. Y (`fqNames`) at `base` and `rebate`, O = 161 each. Id `a`, R = 13: S = 2 × (161 − 13) = 296;
   E = 1 + 159 + 6 = 166. 296 > 166: aliased as `a`.
2. `order-total` (`names`), once: S = 13 − 13 = 0 ≤ E = 18, spelled out.

**Loss decision.** One table, `fqNames`, with one entry: overhead = 118 + 12 + (1 + 159 + 5) + (1 − 1) = 295.
Savings 296 > 295, so the envelope is written, one byte smaller than the plain file.

**Bytes.** The plain JCS file is 158 + 2 × 161 = 480 bytes (the 158 bytes besides the values are counted in
`loss-boundary-declined`). The compacted file is `{"$schema":"` (12), the URL (79), `","context":{` (13),
`"fqNames":{` (11), `"a":"Y"` (165), `}` (1), `},"document":` (13), the document with two 13-byte references
(158 + 26 = 184) and `}` (1): 479 bytes, the expected file. 480 − 296 + 295 = 479 gives the same number.
