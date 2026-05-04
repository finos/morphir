# Quantity Tier

Determines a discount multiplier based on the number of items purchased.

## Inputs

- `quantity` — number of items in the order

## Definitions

### `is_bulk_order`

Returns [true][bool] when the quantity qualifies for a bulk discount (10 or more).

- [Greater Than or Equal](../../specs/language/expressions/ordering.md#greater-than-or-equal-operation)
  - `quantity`
  - `10`

#### Test cases

| `quantity` | `is_bulk_order` |
| ---------- | --------------- |
| 10         | true            |
| 15         | true            |
| 9          | false           |
| 1          | false           |

### `tier_multiplier`

Returns `0.9` for bulk orders (a 10% discount) and `1` otherwise.

- [If-Then-Else](../../specs/language/expressions/boolean.md#if-then-else-operation)
  - `is_bulk_order`
  - `0.9`
  - `1`

#### Test cases

| `is_bulk_order` | `tier_multiplier` |
| --------------- | ----------------- |
| true            | 0.9               |
| false           | 1                 |

[bool]: ../../specs/language/expressions/boolean.md
