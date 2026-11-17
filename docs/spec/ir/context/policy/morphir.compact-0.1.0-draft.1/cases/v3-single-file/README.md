# v3 single file

A classic v3 `Library` with one module holding the value of `v3-value`. It stays one file.

**Occurrences in first-use order.** Inside `distribution`: `"Library"`, the package path, the empty dependency list,
then `modules`. Then `formatVersion`.

1. `acme/order-management` (`packagePaths`), classic `[["acme"],["order","management"]]`, O = 33, once. Tentative id
   `a`: S = 33 − 13 = 20; E = 1 + 21 + 6 = 28. 20 ≤ 28: spelled out.
2. `pricing` (`modulePaths`), classic `[["pricing"]]`, O = 13, once: S = 0 ≤ E = 14, spelled out.
3. `total` (`names`), the value's name, classic `["total"]`, O = 9, once: S = −4 ≤ E = 12, spelled out.
4. `first` (`names`), classic, twice, O = 9 each: S = −8 ≤ E = 12, spelled out.
5. F (`fqNames`), classic arrays, twice, O = 141 each. Id `a`: S = 256 > E = 106: aliased as `a`.

**Loss decision.** Overhead = 118 + 12 + 105 + 0 = 235. Savings 256 > 235, so the envelope is written, 21 bytes
smaller: 626 bytes plain, 605 bytes compacted.
