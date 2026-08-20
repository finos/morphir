# Integer

## Summary

Represents whole numbers, optionally with fixed precision and
signedness. Used for counting, indexing, and discrete arithmetic.
Attributes: **size in bits** (optional, e.g. 8, 16, 32, 64; arbitrary
precision when unset) and **signed** (Boolean; controls whether
negative values are representable). Integer-specific operations:
**Integer Division** (floor division) and **Remainder**, both with a
non-zero divisor precondition. Implements Number, Equality, Ordering.

### Attributes

- **size in bits** (optional): If set, restricts the integer to a fixed bit width (e.g., 8, 16, 32, 64). If unset, the integer is arbitrary precision.
- **signed** ([Boolean](boolean.md)): If `true`, the integer can represent negative numbers; if `false`, only non-negative numbers.

## [Member Values](../concepts/datatype.md#member-values)

- Any whole number within the representable range determined by `size in bits` and `signed`.

## Integer-Specific Operations

### Integer Division (Required) [Operation](../concepts/operation.md)

Divides one integer by another, discarding any remainder. The result is the greatest integer less than or equal to the exact quotient (floor division).

**Precondition:** Divisor must be non-zero.

#### Inputs
- `dividend`: [Integer][int]
- `divisor`: [Integer][int]

#### Outputs
- `result`: [Integer][int]

#### [Test cases][tc]

| `dividend` | `divisor` | `result` |
| ---------- | --------- | -------- |
| 7          | 2         | 3        |
| -7         | 2         | -4       |
| 7          | -2        | -4       |
| -7         | -2        | 3        |
| 5          | 5         | 1        |
| 0          | 3         | 0        |

### Remainder (Required) [Operation](../concepts/operation.md)

Returns the remainder after integer division.

**Precondition:** Divisor must be non-zero.

#### Inputs
- `dividend`: [Integer][int]
- `divisor`: [Integer][int]

#### Outputs
- `result`: [Integer][int]

#### [Test cases][tc]

| `dividend` | `divisor` | `result` |
| ---------- | --------- | -------- |
| 7          | 2         | 1        |
| -7         | 2         | 1        |
| 7          | -2        | 1        |
| -7         | -2        | 1        |
| 5          | 5         | 0        |
| 0          | 3         | 0        |

## [Type Class Instances](../concepts/datatype.md#type-class-instances)

### [Number][num]

Integer implements [Number][num]. Test cases for arithmetic operations
live under each implementing type's file; the shared abstract operations
are defined in [number.md](number.md).

### [Equality][eq]

Integer implements [Equality][eq]: two integers are equal when they have the same numeric value.

#### [Equal][eq-equal] [Operation][op]

##### [Test cases][tc]

| `left` | `right` | `result` |
| ------ | ------- | -------- |
| 0      | 0       | true     |
| 1      | 1       | true     |
| 1      | 2       | false    |
| -1     | 1       | false    |

#### [Not Equal][eq-not-equal] [Operation][op]

##### [Test cases][tc]

| `left` | `right` | `result` |
| ------ | ------- | -------- |
| 0      | 0       | false    |
| 1      | 1       | false    |
| 1      | 2       | true     |
| -1     | 1       | true     |

### [Ordering][ord]

Integer implements [Ordering][ord]: integers are compared by numeric value.

#### [Compare][ord-compare] [Operation][op]

##### [Test cases][tc]

| `left` | `right` | `result`  |
| ------ | ------- | --------- |
| 1      | 2       | Less      |
| 2      | 2       | Equal     |
| 3      | 2       | Greater   |

#### [Less Than][ord-lt] [Operation][op]

##### [Test cases][tc]

| `left` | `right` | `result` |
| ------ | ------- | -------- |
| 1      | 2       | true     |
| 2      | 2       | false    |
| 3      | 2       | false    |

#### [Greater Than][ord-gt] [Operation][op]

##### [Test cases][tc]

| `left` | `right` | `result` |
| ------ | ------- | -------- |
| 1      | 2       | false    |
| 2      | 2       | false    |
| 3      | 2       | true     |

#### [Less Than or Equal][ord-lte] [Operation][op]

##### [Test cases][tc]

| `left` | `right` | `result` |
| ------ | ------- | -------- |
| 1      | 2       | true     |
| 2      | 2       | true     |
| 3      | 2       | false    |

#### [Greater Than or Equal][ord-gte] [Operation][op]

##### [Test cases][tc]

| `left` | `right` | `result` |
| ------ | ------- | -------- |
| 1      | 2       | false    |
| 2      | 2       | true     |
| 3      | 2       | true     |

[int]: integer.md
[tc]: ../concepts/test-case.md
[eq]: equality.md
[eq-equal]: equality.md#equal-operation
[eq-not-equal]: equality.md#not-equal-operation
[num]: number.md
[op]: ../concepts/operation.md
[ord]: ordering.md
[ord-compare]: ordering.md#compare-operation
[ord-gt]: ordering.md#greater-than-operation
[ord-gte]: ordering.md#greater-than-or-equal-operation
[ord-lt]: ordering.md#less-than-operation
[ord-lte]: ordering.md#less-than-or-equal-operation
