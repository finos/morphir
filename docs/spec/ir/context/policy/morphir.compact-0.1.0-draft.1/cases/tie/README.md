# A tie

A v4 type file with two fields of type P and three of type F. P is chosen so that aliasing it saves exactly what its
entry costs.

**Occurrences in first-use order.** The fields `base`, `bonus`, `rebate`, `refund`, `surcharge`, then `name`.

1. P (`fqNames`) at `base` and `bonus`, O = 31 each. Tentative id `a`: S = 2 × (31 − 13) = 36; E = 1 + 29 + 6 = 36.
   S = E: the rule asks for S > E, so P is spelled out and `a` is not consumed.
2. F (`fqNames`) at `rebate`, `refund` and `surcharge`, O = 101 each. Id `a`: S = 264 > E = 106: aliased as `a`.
3. `order-total` (`names`), once: S = 0 ≤ E = 18, spelled out.

**Loss decision.** Overhead = 118 + 12 + 105 + 0 = 235. Savings 264 > 235, so the envelope is written, 29 bytes
smaller: 555 bytes plain, 526 bytes compacted.

**Ordering ties.** The policy also breaks ties in first-use order, by the ordinal order of the spelling and then by
table. Two outermost positions never start at the same offset of the written form, so draft.1 never reaches those keys,
and no case can show them; they only make the order total by definition.
