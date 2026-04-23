# Boolean [Type](../concepts/type.md)

## Overview

The Boolean type represents a fundamental data type with two distinct member values: **true** and **false**. It is used to express binary logic, decision making, and control flow within specifications and executable models.

## [Member Values](../concepts/type.md#member-values)

- **true**: Represents affirmation, presence, or logical truth.
- **false**: Represents negation, absence, or logical falsehood.

## Operations

### NOT [Operation](../concepts/operation.md)

Inverts the value of a Boolean.

#### Test cases

| Input | Output |
| ----- | ------ |
| true  | false  |
| false | true   |

### AND [Operation](../concepts/operation.md)

Returns true if and only if both inputs are true.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| true    | true    | true   |
| true    | false   | false  |
| false   | true    | false  |
| false   | false   | false  |

### OR [Operation](../concepts/operation.md)

Returns true if at least one input is true.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| true    | true    | true   |
| true    | false   | true   |
| false   | true    | true   |
| false   | false   | false  |

### XOR [Operation](../concepts/operation.md)

Returns true if exactly one input is true.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| true    | true    | false  |
| true    | false   | true   |
| false   | true    | true   |
| false   | false   | false  |

### IMPLIES [Operation](../concepts/operation.md)

Returns false only when the antecedent is true and the consequent is false.

#### Test cases

| Input A | Input B | Output |
| ------- | ------- | ------ |
| true    | true    | true   |
| true    | false   | false  |
| false   | true    | true   |
| false   | false   | true   |

### If-Then-Else [Operation](../concepts/operation.md)

Evaluates to the then-value when the condition is `true`, and to the else-value when the condition is `false`. The condition must be a Boolean.

#### Test cases

| Condition | Then | Else | Output |
| --------- | ---- | ---- | ------ |
| true      | 1    | 2    | 1      |
| false     | 1    | 2    | 2      |

## [Type Class Instances](../concepts/type.md#type-class-instances)

Boolean implements [Equality](equality.md): two Boolean values are equal when they are the same member.
