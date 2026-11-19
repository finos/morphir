# v3 type file

A v3 tree type file whose classic record has two fields of type F. Its `name` member is a canonical string; the
payload under `def` is classic v3 JSON.

**Occurrences in first-use order.** `def` (`access` before `value`, then `doc` before `value`; in each field object
`name` comes before `tpe`), then `formatVersion`, then `name`.

1. `base` (`names`) at the first field's `name`, classic `["base"]`, O = 8, once. Tentative id `a`: S = 8 − 13 = −5;
   E = 1 + 4 + 6 = 11. Spelled out.
2. F (`fqNames`) in the first field's `Reference` slot, as classic arrays, O = 141, and again in the second field.
   Id `a`: S = 2 × (141 − 13) = 256 > E = 106: aliased as `a`. It expands back to classic arrays.
3. `bonus` (`names`), classic `["bonus"]`, O = 9, once: S = −4 ≤ E = 12, spelled out.
4. `order-total` (`names`) at `name`, a canonical string, O = 13, once: S = 0 ≤ E = 18, spelled out.

**Loss decision.** Overhead = 118 + 12 + 105 + 0 = 235. Savings 256 > 235, so the envelope is written, 21 bytes
smaller: 515 bytes plain, 494 bytes compacted. Two uses suffice here because a classic FQName costs 141 bytes against
the 101 of its v4 string.
