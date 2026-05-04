# Temperature Converter

Converts temperatures between Celsius and Fahrenheit scales.

## Inputs

- `celsius` — temperature in degrees Celsius
- `fahrenheit` — temperature in degrees Fahrenheit

## Definitions

### `celsius_to_fahrenheit`

Converts a Celsius value to Fahrenheit using the formula _C × 9 / 5 + 32_.

- [Add](../specs/language/expressions/number.md#addition-operation)
  - [Multiply](../specs/language/expressions/number.md#multiplication-operation)
    - `celsius`
    - `1.8`
  - `32`

#### Test cases

| `celsius` | `celsius_to_fahrenheit` |
| --------- | ----------------------- |
| 0         | 32                      |
| 100       | 212                     |
| -40       | -40                     |
| 37        | 98.6                    |

### `fahrenheit_to_celsius`

Converts a Fahrenheit value to Celsius using the formula _(F − 32) / 1.8_.

- [Divide](../specs/language/expressions/number.md#division-operation)
  - [Subtract](../specs/language/expressions/number.md#subtraction-operation)
    - `fahrenheit`
    - `32`
  - `1.8`

#### Test cases

| `fahrenheit` | `fahrenheit_to_celsius` |
| ------------ | ----------------------- |
| 32           | 0                       |
| 212          | 100                     |
| -40          | -40                     |
| 98.6         | 37                      |

### `is_boiling`

Returns [true][bool] when the Celsius temperature is at or above the boiling point of water.

- [Greater Than or Equal](../specs/language/expressions/ordering.md#greater-than-or-equal-operation)
  - `celsius`
  - `100`

#### Test cases

| `celsius` | `is_boiling` |
| --------- | ------------ |
| 100       | true         |
| 101       | true         |
| 99        | false        |
| 0         | false        |

### `is_freezing`

Returns [true][bool] when the Celsius temperature is at or below freezing.

- [Less Than or Equal](../specs/language/expressions/ordering.md#less-than-or-equal-operation)
  - `celsius`
  - `0`

#### Test cases

| `celsius` | `is_freezing` |
| --------- | ------------- |
| 0         | true          |
| -10       | true          |
| 1         | false         |
| 100       | false         |

[bool]: ../specs/language/expressions/boolean.md
