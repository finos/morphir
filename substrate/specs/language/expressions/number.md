# Number [Type Class](../concepts/type-class.md)

## Summary

The Number type class defines arithmetic operations for numeric types.
It extends Equality and Ordering: numeric values can be compared for
equality and relative order. Operations: **Addition**, **Subtraction**,
**Multiplication**, **Division** (precondition: non-zero divisor),
**Negation**, **Absolute Value**, **Modulus** (precondition: non-zero
divisor).

## Literals

A Number literal is written, per the [Literals](README.md#literals)
convention, as a markdown link whose text is the numeric value and
whose target is this section. The link text is the value as it would
be written on paper:

- whole numbers — `0`, `1`, `-42`, `1500`;
- fractional values written with a decimal point — `3.14`, `-0.5`,
  `1500.00`;
- scientific notation when convenient — `1.5e3`, `-2.5e-4`.

A leading `-` denotes a negative value; a leading `+` is permitted but
not required. Authors typically introduce a short alias `num` at the
bottom of the enclosing document and use it inline:

```markdown
`amount` [>][gt] [1500][num]

[gt]: ordering-relation.md#greater-than-derived-operation
[num]: number.md#literals
```

This single section covers literals of every type that implements
Number — [Integer](integer.md), [Decimal](decimal.md), and
[Floating-Point](floating-point.md). The concrete type of a Number
literal is determined by the surrounding context (the operation it
appears under, the field it is bound to, …); the literal itself only
fixes its value.

## Operations

### Addition [Operation](../concepts/operation.md)

Returns the sum of two numbers.

#### Inputs
- `left`: [Type Instance][instance]
- `right`: [Type Instance][instance]

#### Outputs
- `result`: [Type Instance][instance]

### Subtraction [Operation](../concepts/operation.md)

Returns the difference of two numbers.

#### Inputs
- `left`: [Type Instance][instance]
- `right`: [Type Instance][instance]

#### Outputs
- `result`: [Type Instance][instance]

### Multiplication [Operation](../concepts/operation.md)

Returns the product of two numbers.

#### Inputs
- `left`: [Type Instance][instance]
- `right`: [Type Instance][instance]

#### Outputs
- `result`: [Type Instance][instance]

### Division [Operation](../concepts/operation.md)

Returns the quotient of two numbers. Precondition: divisor must not be zero; the result is undefined otherwise.

#### Inputs
- `left`: [Type Instance][instance]
- `right`: [Type Instance][instance]

#### Outputs
- `result`: [Type Instance][instance]

### Negation [Operation](../concepts/operation.md)

Returns the additive inverse of a number such that `a + negate(a) == 0`.

#### Inputs
- `value`: [Type Instance][instance]

#### Outputs
- `result`: [Type Instance][instance]

### Absolute Value [Operation](../concepts/operation.md)

Returns the non-negative magnitude of a number. Equal to the number itself when non-negative, and its [negation](#negation-operation) otherwise.

#### Inputs
- `value`: [Type Instance][instance]

#### Outputs
- `result`: [Type Instance][instance]

### Modulus [Operation](../concepts/operation.md)

Returns the remainder after dividing the first number by the second. Precondition: divisor must not be zero.

#### Inputs
- `left`: [Type Instance][instance]
- `right`: [Type Instance][instance]

#### Outputs
- `result`: [Type Instance][instance]

Test cases for each instance live under the implementing type's
[Type Class Instances](../concepts/datatype.md#type-class-instances) section.

[instance]: ../concepts/type-class.md#type-instance
[tc]: ../concepts/test-case.md
