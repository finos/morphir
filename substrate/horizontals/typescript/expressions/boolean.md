# Boolean — TypeScript

TypeScript evaluators for [Boolean](../../../specs/language/expressions/boolean.md).

## [NOT](../../../specs/language/expressions/boolean.md#not-operation)

```ts
(value: boolean): boolean => !value
```

## [AND](../../../specs/language/expressions/boolean.md#and-operation)

```ts
(left: boolean, right: boolean): boolean => left && right
```

## [OR](../../../specs/language/expressions/boolean.md#or-operation)

```ts
(left: boolean, right: boolean): boolean => left || right
```

## [XOR](../../../specs/language/expressions/boolean.md#xor-operation)

```ts
(left: boolean, right: boolean): boolean => left !== right
```

## [IMPLIES](../../../specs/language/expressions/boolean.md#implies-operation)

```ts
(left: boolean, right: boolean): boolean => !left || right
```
