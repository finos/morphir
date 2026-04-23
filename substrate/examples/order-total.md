# Order Total

Calculates the total amount due for a customer order, including a percentage discount and sales tax.

## Inputs

- `unit_price` — price per individual item
- `quantity` — number of items ordered
- `discount_rate` — fractional discount rate (e.g., `0.05` for 5%)
- `tax_rate` — fractional sales tax rate (e.g., `0.1` for 10%)

## Definitions

### `subtotal`

Gross cost before discount or tax.

- [Multiply][mul]
  - `unit_price`
  - `quantity`

#### Test cases

| `unit_price` | `quantity` | `subtotal` |
| ------------ | ---------- | ---------- |
| 10           | 3          | 30         |
| 25           | 2          | 50         |
| 5            | 1          | 5          |
| 0            | 5          | 0          |

### `discount_amount`

Amount deducted from the subtotal.

- `subtotal` [\*][mul] `discount_rate`

#### Test cases

| `subtotal` | `discount_rate` | `discount_amount` |
| ---------- | --------------- | ----------------- |
| 30         | 0.1             | 3                 |
| 50         | 0               | 0                 |
| 5          | 0.5             | 2.5               |
| 20         | 1               | 20                |

### `discounted_subtotal`

Cost after applying the discount.

- [Subtract](../specs/language/expressions/number.md#subtraction-operation)
  - `subtotal`
  - `discount_amount`

#### Test cases

| `subtotal` | `discount_amount` | `discounted_subtotal` |
| ---------- | ----------------- | --------------------- |
| 30         | 3                 | 27                    |
| 50         | 0                 | 50                    |
| 5          | 2.5               | 2.5                   |
| 20         | 20                | 0                     |

### `tax_amount`

Sales tax charged on the discounted subtotal.

- [Multiply][mul]
  - `discounted_subtotal`
  - `tax_rate`

#### Test cases

| `discounted_subtotal` | `tax_rate` | `tax_amount` |
| --------------------- | ---------- | ------------ |
| 27                    | 0.2        | 5.4          |
| 50                    | 0.1        | 5            |
| 2.5                   | 0.05       | 0.125        |
| 0                     | 0.2        | 0            |

### `total`

Final amount due.

- [Add](../specs/language/expressions/number.md#addition-operation)
  - `discounted_subtotal`
  - `tax_amount`

#### Test cases

| `discounted_subtotal` | `tax_amount` | `total` |
| --------------------- | ------------ | ------- |
| 27                    | 5.4          | 32.4    |
| 50                    | 5            | 55      |
| 2.5                   | 0.125        | 2.625   |
| 0                     | 0            | 0       |

## Validations

### `is_valid_quantity`

Returns [true][bool] when `quantity` is at least `1`.

- [Greater Than or Equal](../specs/language/expressions/ordering.md#greater-than-or-equal-operation)
  - `quantity`
  - `1`

#### Test cases

| `quantity` | `is_valid_quantity` |
| ---------- | ------------------- |
| 3          | true                |
| 1          | true                |
| 0          | false               |
| -1         | false               |

### `is_valid_discount`

Returns [true][bool] when `discount_rate` does not exceed `1`.

- [Less Than or Equal](../specs/language/expressions/ordering.md#less-than-or-equal-operation)
  - `discount_rate`
  - `1`

#### Test cases

| `discount_rate` | `is_valid_discount` |
| --------------- | ------------------- |
| 0               | true                |
| 0.5             | true                |
| 1               | true                |
| 1.5             | false               |

### `clamped_discount_rate`

Returns `discount_rate` when `is_valid_discount` is [true][bool], otherwise `0`.

- [If-Then-Else](../specs/language/expressions/boolean.md#if-then-else-operation)
  - `is_valid_discount`
  - `discount_rate`
  - `0`

#### Test cases

| `is_valid_discount` | `discount_rate` | `clamped_discount_rate` |
| ------------------- | --------------- | ----------------------- |
| true                | 0.1             | 0.1                     |
| true                | 0.5             | 0.5                     |
| false               | 1.5             | 0                       |
| false               | 2               | 0                       |

[bool]: ../specs/language/expressions/boolean.md
[mul]: ../specs/language/expressions/number.md#multiplication-operation
