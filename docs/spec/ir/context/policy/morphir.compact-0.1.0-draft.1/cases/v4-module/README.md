# v4 module file

A v4 tree module file in the inline style: `values` maps `total` to `{"access": "Public", "value": …}`, the
access-controlled form `morphir-ir-v4-document-tree-files.json` requires for an inline entry, holding the definition
of `v4-value`.

**Occurrences in first-use order.** `formatVersion`, `path`, then `values` (inside `values/total`, `access` before
`value`; inside the definition `body`, `inputTypes`, `outputType`).

1. `pricing` (`modulePaths`) at `path`, O = 9, once. Tentative id `a`: S = 9 − 13 = −4; E = 1 + 7 + 6 = 14. −4 ≤ 14:
   spelled out.
2. `first` (`names`) at `body/Variable`, O = 7, once: S = −6 ≤ E = 12, spelled out. The keys `total` and `first` are
   map keys.
3. F (`fqNames`), three times, O = 101. Id `a`: S = 264 > E = 106: aliased as `a`.

**Loss decision.** Overhead = 118 + 12 + 105 + 0 = 235. Savings 264 > 235, so the envelope is written, 29 bytes
smaller: 483 bytes plain, 454 bytes compacted.
