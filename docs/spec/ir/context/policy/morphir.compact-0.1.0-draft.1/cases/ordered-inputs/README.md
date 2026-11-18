# Ordered inputs

A v4 tree value file whose function takes four parameters in the order `rate`, `amount`, `discount`, `limit`: G, F,
G, F. Its output has type F and its body returns the input `amount`. The order of `inputTypes` is the parameter
order, so the written file keeps it. Every other object is sorted as JCS sorts it.

**The written form of the plain document.** `def` (inside it `ExpressionBody` before `access`; inside that `body`,
`inputTypes`, `outputType`), then `formatVersion`, then `name`. `inputTypes` keeps `rate`, `amount`, `discount`,
`limit`. Plain JCS would write `amount`, `discount`, `limit`, `rate`, which would change the function.

**Occurrences in first-use order**, by offset in that written form:

1. `amount` (`names`) at `body/Variable`, O = 8, once. Tentative id `a`: S = 8 − 13 = −5; E = 1 + 6 + 6 = 13.
   −5 ≤ 13: spelled out, and `a` is not consumed. The key `amount` of `inputTypes` is a map key, not a position.
2. G (`fqNames`) at `inputTypes/rate` and `inputTypes/discount`, each O = 88. Id `a`: S = 2 × (88 − 13) = 150 >
   E = 1 + 86 + 6 = 93: aliased as `a`.
3. F (`fqNames`) at `inputTypes/amount`, `inputTypes/limit` and `outputType`, each O = 101. Id `b`:
   S = 3 × (101 − 13) = 264 > E = 1 + 99 + 6 = 106: aliased as `b`.
4. `adjust` (`names`) at `name`, O = 8, once. Tentative id `c`: S = −5 ≤ E = 13: spelled out.

G's first use is `inputTypes/rate`, before F's at `inputTypes/amount`, so G takes `a`. Over plain JCS order, F would
come first at `inputTypes/amount` and take `a`.

**Plain size.** `{"def":{"ExpressionBody":{"body":{"Variable":"amount"},"inputTypes":{` is 69 bytes. The four
members are `"rate":` (7) + 88 = 95, `"amount":` (9) + 101 = 110, `"discount":` (11) + 88 = 99 and `"limit":` (8) +
101 = 109, with 3 commas: 416. Then `}` (1), `,"outputType":` (14), F (101), `}` (1), `,"access":"Public"` (18), `}`
(1), `,"formatVersion":4` (18), `,"name":"adjust"` (16) and `}` (1). 69 + 416 + 171 = 656 bytes.

**Loss decision.** Overhead = 118 + 12 + (1 + 86 + 5) + (1 + 99 + 5) + 1 = 328. Savings 150 + 264 = 414 > 328, so
the envelope is written, 86 bytes smaller: 656 bytes plain, 656 − 414 + 328 = 570 bytes compacted.
