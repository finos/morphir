# Collection Multiplicity [Type](../concepts/datatype.md)

## Summary

An attribute type that governs whether duplicate elements are permitted
in a Collection. Two elements are considered duplicates when they
compare equal under the element type's Equality instance. Values:
**unique** (no two elements may be equal; adding a duplicate leaves the
collection unchanged) or **multi** (duplicates permitted; the same
value may appear more than once).

## [Member Values](../concepts/datatype.md#member-values)

- **unique** — no two elements in the collection may be equal. Adding a
  duplicate element leaves the collection unchanged.
- **multi** — duplicate elements are permitted; the same value may appear more
  than once.
