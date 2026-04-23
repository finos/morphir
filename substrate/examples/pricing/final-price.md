# Final Price

Combines the base price with the tier and promo multipliers to produce a final price.

## Inputs

- `base_price` — unit price before any discounts
- `quantity` — number of items ordered
- `tier_multiplier` — discount multiplier from the [Quantity Tier](quantity-tier.md)
- `promo_multiplier` — discount multiplier from the [Promo Discount](promo-discount.md)

## Definitions

### `line_total`

Gross cost before any discounts.

- [Multiply](../../specs/language/expressions/number.md#multiplication-operation)
  - `base_price`
  - `quantity`

#### Test cases

| `base_price` | `quantity` | `line_total` |
| ------------ | ---------- | ------------ |
| 10           | 5          | 50           |
| 25           | 2          | 50           |
| 100          | 1          | 100          |

### `discounted_total`

Price after applying both the tier and promotional multipliers.

- [Multiply](../../specs/language/expressions/number.md#multiplication-operation)
  - [Multiply](../../specs/language/expressions/number.md#multiplication-operation)
    - `line_total`
    - `tier_multiplier`
  - `promo_multiplier`

#### Test cases

| `line_total` | `tier_multiplier` | `promo_multiplier`  | `discounted_total`  |
| ------------ | ----------------- | ------------------- | ------------------- |
| 100          | 0.9               | 0.85                | 76.5                |
| 50           | 1                 | 1                   | 50                  |
| 50           | 0.9               | 1                   | 45                  |
| 50           | 1                 | 0.5                 | 25                  |

### `has_discount`

Returns [true][bool] when any discount was applied.

- [Not Equal](../../specs/language/expressions/equality.md#not-equal-operation)
  - `discounted_total`
  - `line_total`

#### Test cases

| `discounted_total`  | `line_total` | `has_discount` |
| ------------------- | ------------ | -------------- |
| 76.5                | 100          | true           |
| 50                  | 50           | false          |
| 45                  | 50           | true           |

[bool]: ../../specs/language/expressions/boolean.md
