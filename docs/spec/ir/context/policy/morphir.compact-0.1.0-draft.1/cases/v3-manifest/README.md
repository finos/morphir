# v3 manifest

A v3 tree manifest (`"formatVersion": "3.1.0"`). Its envelope members are canonical strings, so it is measured as
`v4-manifest` is.

**Occurrences in first-use order.** `dependencies`, `distribution`, `formatVersion`, `package`, `pathBudget`.

1. `morphir/SDK` (`packagePaths`), O = 13, once: S = 0 ≤ E = 18, spelled out.
2. `acme/order-management` (`packagePaths`), O = 23, once: S = 10 ≤ E = 28, spelled out.

**Loss decision.** No candidate is aliased, so the output is the plain document in the written form, 133 bytes,
with no envelope.
