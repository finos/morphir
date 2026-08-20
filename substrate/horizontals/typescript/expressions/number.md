# Number — TypeScript

TypeScript evaluators for [Number](../../../specs/language/expressions/number.md).

## [Addition](../../../specs/language/expressions/number.md#addition-operation)

```ts
(left: number, right: number): number => left + right
```

## [Subtraction](../../../specs/language/expressions/number.md#subtraction-operation)

```ts
(left: number, right: number): number => left - right
```

## [Multiplication](../../../specs/language/expressions/number.md#multiplication-operation)

```ts
(left: number, right: number): number => left * right
```

## [Division](../../../specs/language/expressions/number.md#division-operation)

```ts
(left: number, right: number): number => left / right
```

## [Negation](../../../specs/language/expressions/number.md#negation-operation)

```ts
(value: number): number => -value
```

## [Absolute Value](../../../specs/language/expressions/number.md#absolute-value-operation)

```ts
(value: number): number => Math.abs(value)
```

## [Modulus](../../../specs/language/expressions/number.md#modulus-operation)

```ts
(left: number, right: number): number => left % right
```
