# Integer

## Overview

Represents whole numbers, optionally with fixed precision and signedness. Used for counting, indexing, and discrete arithmetic.

### Attributes

- **size in bits** (optional): If set, restricts the integer to a fixed bit width (e.g., 8, 16, 32, 64). If unset, the integer is arbitrary precision.
- **signed** ([Boolean](boolean.md)): If `true`, the integer can represent negative numbers; if `false`, only non-negative numbers.

## [Member Values](../concepts/type.md#member-values)

- Any whole number within the representable range determined by `size in bits` and `signed`.

## [Type Class Instances](../concepts/type.md#type-class-instances)

- [Number](number.md)
- [Equality](equality.md)
- [Ordering](ordering.md)

## Integer-Specific Operations

### Integer Division (Required) [Operation](../concepts/operation.md)

Divides one integer by another, discarding any remainder. The result is the greatest integer less than or equal to the exact quotient (floor division).

**Precondition:** Divisor must be non-zero.

#### Test Cases

| Dividend | Divisor | Result |
| -------- | ------- | ------ |
| 7        | 2       | 3      |
| -7       | 2       | -4     |
| 7        | -2      | -4     |
| -7       | -2      | 3      |
| 5        | 5       | 1      |
| 0        | 3       | 0      |

### Remainder (Required) [Operation](../concepts/operation.md)

Returns the remainder after integer division.

**Precondition:** Divisor must be non-zero.

#### Test Cases

| Dividend | Divisor | Result |
| -------- | ------- | ------ |
| 7        | 2       | 1      |
| -7       | 2       | 1      |
| 7        | -2      | 1      |
| -7       | -2      | 1      |
| 5        | 5       | 0      |
| 0        | 3       | 0      |
