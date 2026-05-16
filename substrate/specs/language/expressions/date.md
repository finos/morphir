# Date [Type](../concepts/datatype.md)

## Summary

The Date type represents a single calendar day in the proleptic
Gregorian calendar. A Date has no time-of-day or time-zone component:
it identifies a day as a year, month, and day of month. Literals use
ISO 8601 form `YYYY-MM-DD` (e.g., `2025-02-26`). Duration between
dates is expressed as an Integer number of days; there is no dedicated
Duration type. Operations: Add Days, Days Between. Implements Equality
and Ordering.

## [Member Values](../concepts/datatype.md#member-values)

Every valid day in the proleptic Gregorian calendar, identified by a year,
a month (1–12), and a day of month within that month's length (accounting
for leap years in February).

## Operations

### Add Days [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md#required)._ Returns the Date obtained
by adding a signed [Integer][int] number of days to the input Date.
Negative values produce an earlier Date.

#### Inputs
- `date`: [Date][date]
- `days`: [Integer][int]

#### Outputs
- `result`: [Date][date]

#### [Test cases][tc]

| `date`       | `days` | `result`     |
| ------------ | ------ | ------------ |
| `2025-01-01` | 0      | `2025-01-01` |
| `2025-01-01` | 1      | `2025-01-02` |
| `2025-01-31` | 1      | `2025-02-01` |
| `2024-02-28` | 1      | `2024-02-29` |
| `2025-02-28` | 1      | `2025-03-01` |
| `2025-01-01` | -1     | `2024-12-31` |

### Days Between [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md#required)._ Returns the signed number
of days from the first Date to the second as an [Integer][int]. The result
is positive when the second Date is later, negative when earlier, and zero
when the two are the same day.

#### Inputs
- `from`: [Date][date]
- `to`: [Date][date]

#### Outputs
- `result`: [Integer][int]

#### [Test cases][tc]

| `from`       | `to`         | `result` |
| ------------ | ------------ | -------- |
| `2025-01-01` | `2025-01-01` | 0        |
| `2025-01-01` | `2025-01-02` | 1        |
| `2025-01-01` | `2025-01-31` | 30       |
| `2025-01-31` | `2025-01-01` | -30      |
| `2024-02-28` | `2024-03-01` | 2        |

## Literals

A Date literal is written, per the [Literals](README.md#literals)
convention, as a markdown link whose text is an ISO 8601 calendar date
of the form `YYYY-MM-DD` and whose target is this section. The link
text must name a valid day in the proleptic Gregorian calendar (see
[Member Values](#member-values)). Authors typically introduce a short
alias `date` at the bottom of the enclosing document and use it
inline:

```markdown
`as-of` [>][gt] [2025-01-01][date]

[date]: date.md#literals
[gt]: ordering-relation.md#greater-than-derived-operation
```

## [Type Class Instances](../concepts/datatype.md#type-class-instances)

### [Equality][eq]

Two dates are equal when they name the same calendar day.

#### [Equal][eq-equal] [Operation][op]

##### [Test cases][tc]

| `left`       | `right`      | `result` |
| ------------ | ------------ | -------- |
| `2025-01-01` | `2025-01-01` | true     |
| `2025-01-01` | `2025-01-02` | false    |

#### [Not Equal][eq-not-equal] [Operation][op]

##### [Test cases][tc]

| `left`       | `right`      | `result` |
| ------------ | ------------ | -------- |
| `2025-01-01` | `2025-01-01` | false    |
| `2025-01-01` | `2025-01-02` | true     |

### [Ordering][ord]

Dates are ordered chronologically: the earlier date precedes the later one.

#### [Compare][ord-compare] [Operation][op]

##### [Test cases][tc]

| `left`       | `right`      | `result` |
| ------------ | ------------ | -------- |
| `2025-01-01` | `2025-01-02` | Less     |
| `2025-01-01` | `2025-01-01` | Equal    |
| `2025-01-02` | `2025-01-01` | Greater  |

[date]: date.md#literals
[eq]: equality.md
[eq-equal]: equality.md#equal-operation
[eq-not-equal]: equality.md#not-equal-operation
[int]: integer.md
[op]: ../concepts/operation.md
[ord]: ordering.md
[ord-compare]: ordering.md#compare-operation
[tc]: ../concepts/test-case.md
