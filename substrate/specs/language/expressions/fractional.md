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

#### Inputs
- `dividend`: [Type Instance][instance]
- `divisor`: [Type Instance][instance]

#### Outputs
- `result`: [Type Instance][instance]

Test cases for each instance live under the implementing type's
[Type Class Instances](../concepts/datatype.md#type-class-instances) section.

## [Type Class](../concepts/type-class.md) Members

- [Floating-Point](floating-point.md)
- [Decimal](decimal.md)

[instance]: ../concepts/type-class.md#type-instance
[tc]: ../concepts/test-case.md
