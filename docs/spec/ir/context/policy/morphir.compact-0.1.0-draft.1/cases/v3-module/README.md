# v3 module file

A v3 tree module file in the inline style: `values` maps `total` to the `def` payload of `v3-value`.

**Occurrences in first-use order.** `formatVersion`, `path`, then `values` (inside `values/total`, `access` before
`value`, then `doc`, then `body`, `inputTypes`, `outputType`).

1. `pricing` (`modulePaths`) at `path`, a canonical string, O = 9, once. Tentative id `a`: S = −4 ≤ E = 1 + 7 + 6 = 14:
   spelled out.
2. `first` (`names`), classic `["first"]`, twice, O = 9 each: S = −8 ≤ E = 12, spelled out.
3. F (`fqNames`), classic arrays, twice, O = 141 each. Id `a`: S = 256 > E = 106: aliased as `a`.

**Loss decision.** Overhead = 118 + 12 + 105 + 0 = 235. Savings 256 > 235, so the envelope is written, 21 bytes
smaller: 510 bytes plain, 489 bytes compacted.
