# Ordering Relation [Type](../concepts/type.md)

## Summary

The Ordering Relation type represents the outcome of a comparison
between two ordered values. Three member values: **Less** (first is
smaller), **Equal** (same), **Greater** (first is larger). Implements
Equality.

## [Member Values](../concepts/type.md#member-values)

### Less

The first value is smaller than the second.

### Equal

Both values are the same.

### Greater

The first value is larger than the second.

## [Type Class Instances](../concepts/type.md#type-class-instances)

Ordering Relation implements [Equality](equality.md): two Ordering Relation values are equal when they are the same member.
