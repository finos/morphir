# String — TypeScript

TypeScript evaluators for [String](../../../specs/language/expressions/string.md).

## [Length](../../../specs/language/expressions/string.md#length-operation)

```ts
(value: string): number => value.length
```

## [Concatenate](../../../specs/language/expressions/string.md#concatenate-operation)

```ts
(left: string, right: string): string => left + right
```

## [Is Empty](../../../specs/language/expressions/string.md#is-empty-operation)

Derived: defined as `Length` equal to zero.

```ts
(value: string): boolean => value.length === 0
```

## [Contains](../../../specs/language/expressions/string.md#contains-operation)

```ts
(value: string, substring: string): boolean => value.includes(substring)
```
