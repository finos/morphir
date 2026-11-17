# v4 manifest

A v4 tree manifest. A manifest names its package once and each dependency once (a reader refuses a repeated or
self-naming dependency), so no package path can repeat in it.

**Occurrences in first-use order.** `dependencies`, `distribution`, `formatVersion`, `package`, `pathBudget`.

1. `morphir/SDK` (`packagePaths`) at `dependencies/0`, O = 13, once. Tentative id `a`: S = 13 − 13 = 0;
   E = 1 + 11 + 6 = 18. 0 ≤ 18: spelled out.
2. `acme/order-management` (`packagePaths`) at `package`, O = 23, once. Tentative id `a`: S = 10 ≤ E = 28: spelled
   out.

**Loss decision.** No candidate is aliased, so the output is the plain document as JCS, 127 bytes, with no envelope,
and the result says that no alias was worth its cost.
