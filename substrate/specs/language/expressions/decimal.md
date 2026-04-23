# Decimal [Type](../concepts/type.md)

## Summary

Represents real numbers using a base-10 format with explicit precision
and scale. Used for financial and business calculations requiring exact
decimal representation. Attributes: **total digits** (required, the
number of significant digits — precision) and **fractional digits**
(required, the number of digits after the decimal point — scale).
Implements Number, Fractional, Equality, and Ordering.

### Attributes

- **total digits** (required): The total number of significant digits (precision).
- **fractional digits** (required): The number of digits after the decimal point (scale).

## [Member Values](../concepts/type.md#member-values)

- Any decimal number representable within the specified precision and scale.

## [Type Class Instances](../concepts/type.md#type-class-instances)

- [Number](number.md)
- [Fractional](fractional.md)
- [Equality](equality.md)
- [Ordering](ordering.md)
