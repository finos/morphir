# Collection Iteration Order [Type](../concepts/type.md)

## Overview

An attribute type that governs the sequence in which elements are visited
during iteration of a [Collection](collection.md).

## [Member Values](../concepts/type.md#member-values)

- **none** — no iteration order is guaranteed.
- **insertion** — elements are visited in the order they were added.
- **key** — elements are visited in ascending order defined by a
  [Compare](ordering.md#compare-operation) expression over a key derived from each
  element, equivalent to SQL `ORDER BY`.

## Attributes

### Tie-Breaking

Applies only when the iteration order is **key**. Governs how elements with
equal keys are ordered relative to each other:

- **stable** — elements with equal keys retain their relative insertion order.
- **unstable** — the relative order of elements with equal keys is unspecified.
