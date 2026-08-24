# Integer — TypeScript

TypeScript evaluators for [Integer](../../../specs/language/expressions/integer.md).

## [Integer Division](../../../specs/language/expressions/integer.md#integer-division-required-operation)

Floor division: the greatest integer ≤ the exact quotient.
Precondition: divisor is non-zero.

```ts
(dividend: number, divisor: number): number => Math.floor(dividend / divisor)
```

## [Remainder](../../../specs/language/expressions/integer.md#remainder-required-operation)

Always non-negative (Euclidean remainder).
Precondition: divisor is non-zero.

```ts
(dividend: number, divisor: number): number =>
    ((dividend % divisor) + Math.abs(divisor)) % Math.abs(divisor)
```
