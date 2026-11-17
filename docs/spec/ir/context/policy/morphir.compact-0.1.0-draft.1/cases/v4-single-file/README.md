# v4 single file

A v4 `Library` with one module holding the definition of `v4-value`. It stays one file.

**Occurrences in first-use order.** Inside `distribution/Library`, `def` comes before `packageName`, so the package
path is used last. Module, value and input names are map keys.

1. `first` (`names`) at `body/Variable`, O = 7, once: S = −6 ≤ E = 12, spelled out.
2. F (`fqNames`), three times, O = 101. Id `a`: S = 264 > E = 106: aliased as `a`.
3. `acme/order-management` (`packagePaths`) at `packageName`, O = 23, once. Tentative id `b`: S = 23 − 13 = 10;
   E = 1 + 21 + 6 = 28. 10 ≤ 28: spelled out.

**Loss decision.** Overhead = 118 + 12 + 105 + 0 = 235. Savings 264 > 235, so the envelope is written, 29 bytes
smaller: 576 bytes plain, 547 bytes compacted.
