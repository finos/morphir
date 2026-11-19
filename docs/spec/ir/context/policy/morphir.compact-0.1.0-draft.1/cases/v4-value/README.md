# v4 value file

A v4 tree value file with two inputs and an output of type F; the body returns the input `first`.

**Occurrences in first-use order.** `def` (inside it `ExpressionBody` before `access`; inside that `body`,
`inputTypes`, `outputType`), then `formatVersion`, then `name`.

1. `first` (`names`) at `body/Variable`, O = 7, once. Tentative id `a`: S = 7 − 13 = −6; E = 1 + 5 + 6 = 12. −6 ≤ 12:
   spelled out, and `a` is not consumed. The key `first` of `inputTypes` is a map key, not a position.
2. F (`fqNames`) at `inputTypes/first`, `inputTypes/second` and `outputType`, each O = 101. Id `a`:
   S = 3 × 88 = 264 > E = 106: aliased as `a`.
3. `total` (`names`) at `name`, O = 7, once. Tentative id `b`: S = −6 ≤ E = 12: spelled out.

**Loss decision.** Overhead = 118 + 12 + 105 + 0 = 235. Savings 264 > 235, so the envelope is written, 29 bytes
smaller: 458 bytes plain, 429 bytes compacted.
