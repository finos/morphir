# Alias allocation order

A v4 type file whose record alternates F and G over six fields. The input lists the fields as `rebate`, `base`,
`bonus`, `extra`, `fee`, `gain`, so F comes first in the input; first use is measured in the written form, which
sorts the fields as `base`, `bonus`, `extra`, `fee`, `gain`, `rebate`.

**Occurrences in first-use order.**

1. G (`fqNames`) at `base`, `extra` and `gain`, O = 88 each. Id `a`: S = 3 × (88 − 13) = 225; E = 1 + 86 + 6 = 93.
   225 > 93: aliased as `a`.
2. F (`fqNames`) at `bonus`, `fee` and `rebate`, O = 101 each. Id `b`: S = 3 × 88 = 264 > E = 106: aliased as `b`.
3. `order-total` (`names`), once. Tentative id `c`: S = 0 ≤ E = 18, spelled out.

**Loss decision.** Two entries in `fqNames`: overhead = 118 + 12 + (1 + 86 + 5) + (1 + 99 + 5) + (2 − 1) = 328.
Savings 225 + 264 = 489 > 328, so the envelope is written, 161 bytes smaller: 758 bytes plain, 597 bytes compacted.
Allocating by input order would have named F `a`; the bytes would differ.
