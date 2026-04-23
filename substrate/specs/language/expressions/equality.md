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

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| true    | true    | true   |
| true    | false   | false  |
| false   | true    | false  |
| false   | false   | true   |

### Not Equal [Operation](../concepts/operation.md)

_[Derived](../concepts/operation.md#derived)._ Returns true if values are different. Defined as [NOT](boolean.md#not-operation)`(a == b)`; does not need to be separately implemented.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| true    | true    | false  |
| true    | false   | true   |
| false   | true    | true   |
| false   | false   | false  |
