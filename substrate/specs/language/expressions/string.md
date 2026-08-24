# String [Type](../concepts/datatype.md)

## Summary

The String type represents finite sequences of Unicode code points,
used for textual data such as names, identifiers, codes, and free-form
descriptions. A String value is always fully present; the empty string
`""` is a distinguished member value, not to be confused with an
absent optional slot. Length and positional operations count Unicode
code points (not graphemes or bytes). Operations: **Length**,
**Concatenate**, **Is Empty**, **Contains**. Implements Equality
(same code-point sequence) and Ordering (lexicographic by code point;
empty string precedes every non-empty string).

## [Member Values](../concepts/datatype.md#member-values)

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

#### Inputs
- `value`: [String][str]

#### Outputs
- `result`: [Integer][int]

#### [Test cases][tc]

| `value` | `result` |
| ------- | -------- |
| `""`    | 0        |
| `"a"`   | 1        |
| `"abc"` | 3        |

### Concatenate [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md#required)._ Returns a new string
containing the code points of the first input followed by the code points
of the second.

#### Inputs
- `left`: [String][str]
- `right`: [String][str]

#### Outputs
- `result`: [String][str]

#### [Test cases][tc]

| `left`  | `right` | `result` |
| ------- | ------- | -------- |
| `""`    | `""`    | `""`     |
| `"ab"`  | `""`    | `"ab"`   |
| `""`    | `"cd"`  | `"cd"`   |
| `"ab"`  | `"cd"`  | `"abcd"` |

### Is Empty [Operation](../concepts/operation.md)

_[Derived](../concepts/operation.md#derived)._ Returns [Boolean][bool]
`true` when the string contains no code points. Defined as
[Length](#length-operation) equal to zero.

#### Inputs
- `value`: [String][str]

#### Outputs
- `result`: [Boolean][bool]

#### [Test cases][tc]

| `value` | `result` |
| ------- | -------- |
| `""`    | true     |
| `"a"`   | false    |
| `"abc"` | false    |

### Contains [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md#required)._ Returns [Boolean][bool]
`true` when the second input appears as a contiguous subsequence of code
points within the first. Every string contains the empty string.

#### Inputs
- `value`: [String][str]
- `substring`: [String][str]

#### Outputs
- `result`: [Boolean][bool]

#### [Test cases][tc]

| `value`  | `substring` | `result` |
| -------- | ----------- | -------- |
| `"abcd"` | `"bc"`      | true     |
| `"abcd"` | `"ce"`      | false    |
| `"abcd"` | `""`        | true     |
| `""`     | `""`        | true     |
| `""`     | `"a"`       | false    |

## Literals

A String literal is written, per the [Literals](README.md#literals)
convention, as a markdown link whose text is the string value enclosed
in double quotes and whose target is this section. The quotes
delimit the literal so that leading or trailing whitespace and the
empty string `""` are unambiguous. Authors typically introduce a short
alias `str` at the bottom of the enclosing document and use it inline:

```markdown
`name` [==][eq] ["Alice"][str]

[eq]: equality.md#equal-operation
[str]: string.md#literals
```

A backslash inside the quotes introduces an escape sequence; at
minimum, `\"` denotes a literal double quote and `\\` denotes a
literal backslash. The empty string is written `""`.

## [Type Class Instances](../concepts/datatype.md#type-class-instances)

### [Equality][eq]

Two strings are equal when they contain the same sequence of code points.

#### [Equal][eq-equal] [Operation][op]

##### [Test cases][tc]

| `left`  | `right` | `result` |
| ------- | ------- | -------- |
| `""`    | `""`    | true     |
| `"abc"` | `"abc"` | true     |
| `"abc"` | `"ABC"` | false    |
| `"a"`   | `""`    | false    |

#### [Not Equal][eq-not-equal] [Operation][op]

##### [Test cases][tc]

| `left`  | `right` | `result` |
| ------- | ------- | -------- |
| `""`    | `""`    | false    |
| `"abc"` | `"abc"` | false    |
| `"abc"` | `"ABC"` | true     |
| `"a"`   | `""`    | true     |

### [Ordering][ord]

Strings are compared lexicographically by code point. The empty string precedes every non-empty string.

#### [Compare][ord-compare] [Operation][op]

##### [Test cases][tc]

| `left`  | `right` | `result`  |
| ------- | ------- | --------- |
| `"a"`   | `"b"`   | Less      |
| `"a"`   | `"a"`   | Equal     |
| `"b"`   | `"a"`   | Greater   |
| `""`    | `"a"`   | Less      |

[bool]: boolean.md
[eq]: equality.md
[eq-equal]: equality.md#equal-operation
[eq-not-equal]: equality.md#not-equal-operation
[int]: integer.md
[op]: ../concepts/operation.md
[ord]: ordering.md
[ord-compare]: ordering.md#compare-operation
[str]: string.md#literals
[tc]: ../concepts/test-case.md
