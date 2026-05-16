# Floating-Point [Type](../concepts/datatype.md)

## Summary

Represents real numbers using a fixed-size binary format with a sign,
exponent, and significand (mantissa). Used for scientific and
engineering calculations where approximate values and wide dynamic
range are needed. Attribute: **size in bits** (required; e.g. 32 for
single precision, 64 for double precision). Implements Number,
Fractional, Equality, and Ordering.

### Attributes

- **size in bits** (required): Specifies the bit width of the floating-point representation (e.g., 32 for single precision, 64 for double precision).

## [Member Values](../concepts/datatype.md#member-values)

- Any real number representable within the chosen format, including special values (e.g., infinity, NaN).

## [Type Class Instances](../concepts/datatype.md#type-class-instances)

### [Fractional][frac]

Floating-Point implements [Fractional][frac].

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

Two floating-point values are equal when they represent the same numeric value (NaN is never equal to itself).

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

Floating-point values are ordered by numeric value.

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
