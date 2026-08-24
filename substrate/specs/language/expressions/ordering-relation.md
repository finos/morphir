# Ordering Relation [Type](../concepts/datatype.md)

## Summary

The Ordering Relation type represents the outcome of a comparison
between two ordered values. Three member values: **Less** (first is
smaller), **Equal** (same), **Greater** (first is larger). Implements
Equality.

## [Member Values](../concepts/datatype.md#member-values)

### Less

The first value is smaller than the second.

### Equal

Both values are the same.

### Greater

The first value is larger than the second.

## [Type Class Instances](../concepts/datatype.md#type-class-instances)

### [Equality][eq]

Ordering Relation implements [Equality][eq]: two Ordering Relation values are equal when they are the same member.

#### [Equal][eq-equal] [Operation][op]

##### [Test cases][tc]

| `left`   | `right`  | `result` |
| -------- | -------- | -------- |
| Less     | Less     | true     |
| Equal    | Equal    | true     |
| Greater  | Greater  | true     |
| Less     | Greater  | false    |

#### [Not Equal][eq-not-equal] [Operation][op]

##### [Test cases][tc]

| `left`   | `right`  | `result` |
| -------- | -------- | -------- |
| Less     | Less     | false    |
| Equal    | Equal    | false    |
| Greater  | Greater  | false    |
| Less     | Greater  | true     |

[eq]: equality.md
[eq-equal]: equality.md#equal-operation
[eq-not-equal]: equality.md#not-equal-operation
[op]: ../concepts/operation.md
[tc]: ../concepts/test-case.md
