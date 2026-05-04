# Promo Discount

Applies a promotional code discount when a valid code is present.

## Inputs

- `has_promo_code` — [Boolean][bool] indicating whether a promo code was entered
- `promo_percentage` — fractional discount from the promo code (e.g., `0.15` for 15%)

## Definitions

### `promo_multiplier`

The fraction of the price to charge after the promotional discount. Returns `1 - promo_percentage` when a code is present, `1` otherwise.

- [If-Then-Else](../../specs/language/expressions/boolean.md#if-then-else-operation)
  - `has_promo_code`
    - [Subtract](../../specs/language/expressions/number.md#subtraction-operation)
    - `1`
    - `promo_percentage`
  - `1`

#### Test cases

| `has_promo_code` | `promo_percentage` | `promo_multiplier`  |
| ---------------- | ------------------ | ------------------- |
| true             | 0.15               | 0.85                |
| true             | 0.5                | 0.5                 |
| false            | 0.15               | 1                   |
| false            | 0                  | 1                   |

[bool]: ../../specs/language/expressions/boolean.md
