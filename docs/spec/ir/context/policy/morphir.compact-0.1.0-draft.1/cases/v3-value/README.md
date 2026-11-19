# v3 value file

A v3 tree value file, the classic counterpart of `v4-value`: one input `first` of type F, an output of type F, and a
body that returns `first`.

**Occurrences in first-use order.** `def` (`access` before `value`, `doc` before `value`; in the value definition
`body`, `inputTypes`, `outputType`), then `formatVersion`, then `name`.

1. `first` (`names`) in `body` (`["Variable",{},["first"]]`) and in the input, classic `["first"]`, O = 9 each.
   Tentative id `a`: S = 2 × (9 − 13) = −8 ≤ E = 12: spelled out.
2. F (`fqNames`) in the input's type and in `outputType`, classic arrays, O = 141 each. Id `a`: S = 2 × 128 = 256 >
   E = 106: aliased as `a`.
3. `total` (`names`) at `name`, a canonical string, O = 7, once: S = −6 ≤ E = 12, spelled out.

**Loss decision.** Overhead = 118 + 12 + 105 + 0 = 235. Savings 256 > 235, so the envelope is written, 21 bytes
smaller: 495 bytes plain, 474 bytes compacted.
