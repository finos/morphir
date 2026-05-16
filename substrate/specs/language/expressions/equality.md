# Equality [Type Class](../concepts/type-class.md)

## Summary

The Equality type class defines operations for comparing values to
determine if they are equal or not equal. It applies to types where
equality is meaningful. Operations: **Equal** (required) and **Not
Equal** (derived as `NOT (a == b)`). All operations return Boolean.

## Operations

All operations return a [Boolean](boolean.md) value.

### Equal [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md#required)._ Returns true if both values are the same. Must be implemented by any type that instances this type class.

#### Inputs
- `left`: [Type Instance][instance]
- `right`: [Type Instance][instance]

#### Outputs
- `result`: [Boolean](boolean.md)

### Not Equal [Operation](../concepts/operation.md)

_[Derived](../concepts/operation.md#derived)._ Returns true if values are different. Defined as [NOT](boolean.md#not-operation)`(a == b)`; does not need to be separately implemented.

#### Inputs
- `left`: [Type Instance][instance]
- `right`: [Type Instance][instance]

#### Outputs
- `result`: [Boolean](boolean.md)

Test cases for each instance live under the implementing type's
[Type Class Instances](../concepts/datatype.md#type-class-instances) section.

[tc]: ../concepts/test-case.md
[instance]: ../concepts/type-class.md#type-instance
