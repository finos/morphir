# Compaction that would be a loss

A v4 type file with two fields of type F.

**Occurrences in first-use order.** The fields `base`, `rebate`, then `name`.

1. F (`fqNames`) at `base` and `rebate`, O = 101 each. Id `a`: S = 2 × 88 = 176 > E = 106: worth its entry, so it is
   aliased.
2. `order-total` (`names`), once: S = 0 ≤ E = 18, spelled out.

**Loss decision.** Overhead = 118 + 12 + 105 + 0 = 235. Savings 176 ≤ 235: the envelope would make the file
59 bytes larger. The writer writes the plain document as JCS, 360 bytes, with no envelope, and its result says that no
alias was worth its cost.
