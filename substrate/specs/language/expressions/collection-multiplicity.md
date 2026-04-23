# Collection Multiplicity [Type](../concepts/type.md)

## Overview

An attribute type that governs whether duplicate elements are permitted in a
[Collection](collection.md). Two elements are considered duplicates when they
compare [Equal](equality.md#equal-operation) under the element type's
[Equality](equality.md) instance.

## [Member Values](../concepts/type.md#member-values)

- **unique** — no two elements in the collection may be equal. Adding a
  duplicate element leaves the collection unchanged.
- **multi** — duplicate elements are permitted; the same value may appear more
  than once.
