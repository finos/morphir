# Broken Example

An intentionally malformed document for testing CLI error reporting.

## Inputs

- `price` — a price value
- `rate` — a rate value

## Definitions

### `computed_tax`

Computes tax with a [broken link to nowhere](../specs/language/expressions/nonexistent.md#fake-operation).

- [Multiply](../specs/language/expressions/nonexistent.md#fake-operation)
  - `price`
  - `rate`

#### Test cases

| `price` | `rate` | `computed_tax` |
| ------- | ------ | -------------- |
| 100     | 0.1    | 999            |

### `always_true`

Returns [true][bool] unconditionally but the test table expects the wrong result.

- [Equal](../specs/language/expressions/equality.md#equal-operation)
  - `price`
  - `price`

#### Test cases

| `price` | `always_true` |
| ------- | ------------- |
| 42      | false         |

[bool]: ../specs/language/expressions/boolean.md
