# Table order

A v3 tree value file that multiplies its input N by itself: `N × N` with `morphir/SDK:basics#multiply` (M), input and
output of type F. It needs aliases in two tables.

**Occurrences in first-use order.** In the value definition, `body` comes first, and the body starts with the
reference to M.

1. M (`fqNames`) in `body`, classic arrays, O = 55, once. Id `a`: S = 55 − 13 = 42; E = 1 + 27 + 6 = 34. 42 > 34:
   aliased as `a`, although it is used once, because its classic form is 28 bytes longer than its spelling.
2. N (`names`) twice in `body` (`["Variable",{},…]`) and once as the input's name, classic arrays, O = 70 each. Id `b`:
   S = 3 × (70 − 13) = 171; E = 1 + 54 + 6 = 61. Aliased as `b`.
3. F (`fqNames`) in the input's type and in `outputType`, classic arrays, O = 141 each. Id `c`: S = 2 × 128 = 256 >
   E = 106: aliased as `c`.
4. `total` (`names`) at `name`, a canonical string, once. Tentative id `d`: S = −6 ≤ E = 12, spelled out.

Ids run `a`, `b`, `c` across the two tables in first-use order. The written form sorts the context's members, so
`fqNames` (holding `a` and `c`) comes before `names` (holding `b`), whatever order the ids were given in.

**Loss decision.** Overhead = 118 + 12 (`fqNames`) + 10 (`names`) + (1 + 27 + 5) + (1 + 99 + 5) + (1 + 54 + 5) +
(3 − 1) = 340. Savings 42 + 171 + 256 = 469 > 340, so the envelope is written, 129 bytes smaller: 803 bytes plain,
674 bytes compacted.
