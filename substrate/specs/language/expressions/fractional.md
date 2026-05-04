# Fractional

## Summary

A type class for types supporting division and related operations with
non-integer results. Extends Number. Operations: **Division**
(required; precondition: divisor must be non-zero). Members:
Floating-Point, Decimal.

### Extended [Type Classes](../concepts/type-class.md)

- [Number](number.md)

## Operations

### Division (Required) [Operation](../concepts/operation.md)

Divides one value by another, producing a fractional result. The result may be infinite or undefined (e.g., division by zero).

**Precondition:** Divisor must be non-zero.

#### Test Cases

| Dividend | Divisor | Result |
| -------- | ------- | ------ |
| 7.0      | 2.0     | 3.5    |
| -7.0     | 2.0     | -3.5   |
| 7.0      | -2.0    | -3.5   |
| -7.0     | -2.0    | 3.5    |
| 5.0      | 5.0     | 1.0    |
| 0.0      | 3.0     | 0.0    |

## [Type Class](../concepts/type-class.md) Members

- [Floating-Point](floating-point.md)
- [Decimal](decimal.md)
