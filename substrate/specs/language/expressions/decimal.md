# Decimal [Type](../concepts/datatype.md)

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

## [Member Values](../concepts/datatype.md#member-values)

- Any decimal number representable within the specified precision and scale.

## [Type Class Instances](../concepts/datatype.md#type-class-instances)

### [Fractional][frac]

Decimal implements [Fractional][frac].

#### Division (Required) [Operation][op]

##### [Test cases][tc]

| `dividend` | `divisor` | `result` |
| ---------- | --------- | -------- |
| 7.0        | 2.0       | 3.5      |
| -7.0       | 2.0       | -3.5     |
| 7.0        | -2.0      | -3.5     |
| -7.0       | -2.0      | 3.5      |
| 0.0        | 3.0       | 0.0      |

### [Equality][eq]

Two decimal values are equal when they represent the same numeric value.

#### [Equal][eq-equal] [Operation][op]

##### [Test cases][tc]

| `left` | `right` | `result` |
| ------ | ------- | -------- |
| 1.0    | 1.0     | true     |
| 1.5    | 1.5     | true     |
| 1.0    | 2.0     | false    |

#### [Not Equal][eq-not-equal] [Operation][op]

##### [Test cases][tc]

| `left` | `right` | `result` |
| ------ | ------- | -------- |
| 1.0    | 1.0     | false    |
| 1.5    | 1.5     | false    |
| 1.0    | 2.0     | true     |

### [Ordering][ord]

Decimal values are ordered by numeric value.

#### [Compare][ord-compare] [Operation][op]

##### [Test cases][tc]

| `left` | `right` | `result` |
| ------ | ------- | -------- |
| 1.0    | 2.0     | Less     |
| 2.0    | 2.0     | Equal    |
| 3.0    | 2.0     | Greater  |

[eq]: equality.md
[eq-equal]: equality.md#equal-operation
[eq-not-equal]: equality.md#not-equal-operation
[frac]: fractional.md
[op]: ../concepts/operation.md
[ord]: ordering.md
[ord-compare]: ordering.md#compare-operation
[tc]: ../concepts/test-case.md
