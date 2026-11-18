# v4 type file

A v4 tree type file whose record has three fields of type F (see the policy README for F, G, P, N and M).

**Occurrences in first-use order.** The written form of the plain file (here JCS order): `def` (inside it
`TypeAliasDefinition` before `access`, `typeExp` before `typeParams`, the fields `base`, `bonus`, `rebate`), then
`formatVersion`, then `name`.

1. F (`fqNames`) at `base`, `bonus` and `rebate`, each O = 101. Next id `a`, R = 13. S = 3 × (101 − 13) = 264;
   E = 1 + 99 + 6 = 106. 264 > 106: aliased as `a`.
2. `order-total` (`names`) at `name`, O = 13, once. Tentative id `b`: S = 13 − 13 = 0; E = 1 + 11 + 6 = 18. 0 ≤ 18:
   spelled out, and `b` is not consumed.

**Loss decision.** One entry in `fqNames`: overhead = 118 + 12 + (1 + 99 + 5) + (1 − 1) = 235. Savings 264 > 235, so
the envelope is written, 29 bytes smaller than the plain file: 470 bytes plain, 441 bytes compacted.
