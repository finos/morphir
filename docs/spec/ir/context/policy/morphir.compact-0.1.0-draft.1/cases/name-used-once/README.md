# A name used once

The `v4-type` record with a fourth field, `loyalty`, of type G, used once.

**Occurrences in first-use order.** The fields `base`, `bonus`, `loyalty`, `rebate`, then `name`.

1. F (`fqNames`) at `base`, `bonus` and `rebate`, O = 101 each. Id `a`: S = 264 > E = 106: aliased as `a`.
2. G (`fqNames`) at `loyalty`, O = 88, once. Tentative id `b`: S = 88 − 13 = 75; E = 1 + 86 + 6 = 93. 75 ≤ 93: spelled
   out in place, and the table has no entry for it.
3. `order-total` (`names`), once: S = 0 ≤ E = 18, spelled out.

**Loss decision.** Overhead = 118 + 12 + 105 + 0 = 235. Savings 264 > 235, so the envelope is written, 29 bytes
smaller: 569 bytes plain, 540 bytes compacted.

A spelling used once is worth an alias only when O − (12 + len(id)) > len(id) + len(s) + 6, that is, when its
occurrence is more than 20 bytes longer than the spelling for a one-letter id. A canonical string is 2 bytes longer, so
it never is. A classic v3 FQName can be: see `table-order`.
