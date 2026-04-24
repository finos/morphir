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

#### Test cases

| Date         | Days | Output       |
| ------------ | ---- | ------------ |
| `2025-01-01` | 0    | `2025-01-01` |
| `2025-01-01` | 1    | `2025-01-02` |
| `2025-01-31` | 1    | `2025-02-01` |
| `2024-02-28` | 1    | `2024-02-29` |
| `2025-02-28` | 1    | `2025-03-01` |
| `2025-01-01` | -1   | `2024-12-31` |

### Days Between [Operation](../concepts/operation.md)

_[Required](../concepts/operation.md#required)._ Returns the signed number
of days from the first Date to the second as an [Integer][int]. The result
is positive when the second Date is later, negative when earlier, and zero
when the two are the same day.

#### Test cases

| From         | To           | Output |
| ------------ | ------------ | ------ |
| `2025-01-01` | `2025-01-01` | 0      |
| `2025-01-01` | `2025-01-02` | 1      |
| `2025-01-01` | `2025-01-31` | 30     |
| `2025-01-31` | `2025-01-01` | -30    |
| `2024-02-28` | `2024-03-01` | 2      |

## [Type Class Instances](../concepts/datatype.md#type-class-instances)

- **[Equality][eq]** — two dates are equal when they name the same
  calendar day.
- **[Ordering][ord]** — dates are ordered chronologically: the earlier
  date precedes the later one.

[eq]: equality.md
[int]: integer.md
[ord]: ordering.md
