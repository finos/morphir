# Ordering — TypeScript

TypeScript evaluators for [Ordering](../../../specs/language/expressions/ordering.md).

## [Compare](../../../specs/language/expressions/ordering.md#compare-operation)

Returns `"Less"`, `"Equal"`, or `"Greater"`.

```ts
(left: number, right: number): string =>
    left < right ? "Less" : left > right ? "Greater" : "Equal"
```

## [Less Than](../../../specs/language/expressions/ordering.md#less-than-operation)

```ts
(left: number, right: number): boolean => left < right
```

## [Greater Than](../../../specs/language/expressions/ordering.md#greater-than-operation)

```ts
(left: number, right: number): boolean => left > right
```

## [Less Than or Equal](../../../specs/language/expressions/ordering.md#less-than-or-equal-operation)

```ts
(left: number, right: number): boolean => left <= right
```

## [Greater Than or Equal](../../../specs/language/expressions/ordering.md#greater-than-or-equal-operation)

```ts
(left: number, right: number): boolean => left >= right
```
