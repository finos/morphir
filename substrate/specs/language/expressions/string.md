# String [Type](../concepts/type.md)

## Overview

The String type represents finite sequences of Unicode code points. It is
used for textual data such as names, identifiers, codes, and free-form
descriptions.

A String value is always fully present; the empty string `""` is a
distinguished member value, not to be confused with an absent
[optional](../concepts/optionality.md) slot.

## [Member Values](../concepts/type.md#member-values)

Every finite sequence of Unicode code points, including the empty
sequence, is a member of String. Individual characters are not a separate
type; operations that address characters do so by position within the
string.

Length and positional operations count Unicode code points. Grapheme-cluster
or byte-level semantics, when needed, are expressed by dedicated operations
rather than by the primitive operations defined here.

## Operations

### Length [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md#required)._ Returns the number of
Unicode code points in the string as an [Integer][int].

#### Test cases

| Input   | Output |
| ------- | ------ |
| `""`    | 0      |
| `"a"`   | 1      |
| `"abc"` | 3      |

### Concatenate [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md#required)._ Returns a new string
containing the code points of the first input followed by the code points
of the second.

#### Test cases

| Input A | Input B | Output   |
| ------- | ------- | -------- |
| `""`    | `""`    | `""`     |
| `"ab"`  | `""`    | `"ab"`   |
| `""`    | `"cd"`  | `"cd"`   |
| `"ab"`  | `"cd"`  | `"abcd"` |

### Is Empty [Operation](../concepts/operation.md)

_[Derived](../concepts/operation.md#derived)._ Returns [Boolean][bool]
`true` when the string contains no code points. Defined as
[Length](#length-operation) equal to zero.

#### Test cases

| Input   | Output |
| ------- | ------ |
| `""`    | true   |
| `"a"`   | false  |
| `"abc"` | false  |

### Contains [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md#required)._ Returns [Boolean][bool]
`true` when the second input appears as a contiguous subsequence of code
points within the first. Every string contains the empty string.

#### Test cases

| Input    | Substring | Output |
| -------- | --------- | ------ |
| `"abcd"` | `"bc"`    | true   |
| `"abcd"` | `"ce"`    | false  |
| `"abcd"` | `""`      | true   |
| `""`     | `""`      | true   |
| `""`     | `"a"`     | false  |

## [Type Class Instances](../concepts/type.md#type-class-instances)

- **[Equality][eq]** — two strings are equal when they contain the same
  sequence of code points.
- **[Ordering][ord]** — strings are compared lexicographically by code
  point. The empty string precedes every non-empty string.

[bool]: boolean.md
[eq]: equality.md
[int]: integer.md
[ord]: ordering.md
