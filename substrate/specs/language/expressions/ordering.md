# Ordering [Type Class](../concepts/type-class.md)

## Overview

The Ordering [type class](../concepts/type-class.md) defines operations for comparing values to determine their relative order. It extends [Equality][eq]: any [type](../concepts/type.md) with an ordering also supports equality comparison.

## Operations

Relational operations return a [Boolean][bool] value.

### Compare [Operation](../concepts/operation.md)

_[Required][req]._ Returns an [Ordering Relation][or] representing the relationship between the first and second value. All other ordering operations are derived from this.

#### Test cases

| Input A | Input B | Output                |
| ------- | ------- | --------------------- |
| 1       | 2       | [Less][or-less]       |
| 2       | 2       | [Equal][or-equal]     |
| 3       | 2       | [Greater][or-greater] |

### Less Than [Operation](../concepts/operation.md)

_[Derived][der]._ Returns true when `compare(a, b)` is [Less][or-less].

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| 1       | 2       | true   |
| 2       | 2       | false  |
| 3       | 2       | false  |

### Greater Than [Operation](../concepts/operation.md)

_[Derived][der]._ Returns true when `compare(a, b)` is [Greater][or-greater].

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| 1       | 2       | false  |
| 2       | 2       | false  |
| 3       | 2       | true   |

### Less Than or Equal [Operation](../concepts/operation.md)

_[Derived][der]._ Returns true when `compare(a, b)` is not [Greater][or-greater].

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| 1       | 2       | true   |
| 2       | 2       | true   |
| 3       | 2       | false  |

### Greater Than or Equal [Operation](../concepts/operation.md)

_[Derived][der]._ Returns true when `compare(a, b)` is not [Less][or-less].

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| 1       | 2       | false  |
| 2       | 2       | true   |
| 3       | 2       | true   |

[bool]: boolean.md
[der]: ../concepts/operation.md#derived
[eq]: equality.md
[or]: ordering-relation.md
[or-equal]: ordering-relation.md#equal
[or-greater]: ordering-relation.md#greater
[or-less]: ordering-relation.md#less
[req]: ../concepts/operation.md#required
