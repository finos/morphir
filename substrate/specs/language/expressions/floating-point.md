# Floating-Point [Type](../concepts/type.md)

## Overview

Represents real numbers using a fixed-size binary format with a sign, exponent, and significand (mantissa). Used for scientific and engineering calculations where approximate values and wide dynamic range are needed.

### Attributes

- **size in bits** (required): Specifies the bit width of the floating-point representation (e.g., 32 for single precision, 64 for double precision).

## [Member Values](../concepts/type.md#member-values)

- Any real number representable within the chosen format, including special values (e.g., infinity, NaN).

## [Type Class Instances](../concepts/type.md#type-class-instances)

- [Number](number.md)
- [Fractional](fractional.md)
- [Equality](equality.md)
- [Ordering](ordering.md)
