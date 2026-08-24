# Boolean [Type](../concepts/datatype.md)

## Summary

The Boolean type represents a fundamental data type with two distinct member values: **true** and **false**. It is used to express binary logic, decision making, and control flow within specifications and executable models. Operations: NOT, AND, OR, XOR, IMPLIES. Implements Equality. Conditional branching on a Boolean is expressed with a [Decision Tree](decision-tree.md).

## [Member Values](../concepts/datatype.md#member-values)

- **true**: Represents affirmation, presence, or logical truth.
- **false**: Represents negation, absence, or logical falsehood.

## Operations

### NOT [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md#required)._ Inverts the value of a Boolean.

#### Inputs
- `value`: [Boolean][bool]

#### Outputs
- `result`: [Boolean][bool]

#### [Test cases][tc]

| `value` | `result` |
| ------- | -------- |
| true    | false    |
| false   | true     |

### AND [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md#required)._ Returns true if and only if both inputs are true.

#### Inputs
- `left`: [Boolean][bool]
- `right`: [Boolean][bool]

#### Outputs
- `result`: [Boolean][bool]

#### [Test cases][tc]

| `left` | `right` | `result` |
| ------ | ------- | -------- |
| true   | true    | true     |
| true   | false   | false    |
| false  | true    | false    |
| false  | false   | false    |

### OR [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md#required)._ Returns true if at least one input is true.

#### Inputs
- `left`: [Boolean][bool]
- `right`: [Boolean][bool]

#### Outputs
- `result`: [Boolean][bool]

#### [Test cases][tc]

| `left` | `right` | `result` |
| ------ | ------- | -------- |
| true   | true    | true     |
| true   | false   | true     |
| false  | true    | true     |
| false  | false   | false    |

### XOR [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md#required)._ Returns true if exactly one input is true.

#### Inputs
- `left`: [Boolean][bool]
- `right`: [Boolean][bool]

#### Outputs
- `result`: [Boolean][bool]

#### [Test cases][tc]

| `left` | `right` | `result` |
| ------ | ------- | -------- |
| true   | true    | false    |
| true   | false   | true     |
| false  | true    | true     |
| false  | false   | false    |

### IMPLIES [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md#required)._ Returns false only when the antecedent is true and the consequent is false.

#### Inputs
- `left`: [Boolean][bool]
- `right`: [Boolean][bool]

#### Outputs
- `result`: [Boolean][bool]

#### [Test cases][tc]

| `left` | `right` | `result` |
| ------ | ------- | -------- |
| true   | true    | true     |
| true   | false   | false    |
| false  | true    | true     |
| false  | false   | true     |

## Literals

A Boolean literal is written, per the [Literals](README.md#literals)
convention, as a markdown link whose text is one of the two member
values `true` or `false` and whose target is this section. Authors
typically introduce a short alias `bool` at the bottom of the
enclosing document and use it inline:

```markdown
`flag` [==][eq] [true][bool]

[bool]: boolean.md#literals
[eq]: equality.md#equal-operation
```

The link text must match the spelling of a [Member Value](#member-values)
exactly — `true` or `false`, lowercase — so that the literal is
unambiguous.

## [Type Class Instances](../concepts/datatype.md#type-class-instances)

### [Equality][eq]

Boolean implements [Equality][eq]: two Boolean values are equal when they are the same member.

#### [Equal][eq-equal] [Operation][op]

##### [Test cases][tc]

| `left` | `right` | `result` |
| ------ | ------- | -------- |
| true   | true    | true     |
| true   | false   | false    |
| false  | true    | false    |
| false  | false   | true     |

#### [Not Equal][eq-not-equal] [Operation][op]

Derived from [NOT](#not-operation)([Equal][eq-equal]).

##### [Test cases][tc]

| `left` | `right` | `result` |
| ------ | ------- | -------- |
| true   | true    | false    |
| true   | false   | true     |
| false  | true    | true     |
| false  | false   | false    |

[bool]: boolean.md#literals
[tc]: ../concepts/test-case.md
[eq]: equality.md
[eq-equal]: equality.md#equal-operation
[eq-not-equal]: equality.md#not-equal-operation
[op]: ../concepts/operation.md
