# Date — TypeScript

TypeScript evaluators for [Date](../../../specs/language/expressions/date.md).

## [Add Days](../../../specs/language/expressions/date.md#add-days-operation)

`date` is an ISO 8601 string (`YYYY-MM-DD`); `days` is a signed integer.
Result is an ISO 8601 string. Uses UTC to avoid daylight-saving shifts.

```ts
(date: string, days: number): string => {
    const d = new Date(date + "T00:00:00Z");
    d.setUTCDate(d.getUTCDate() + days);
    return d.toISOString().slice(0, 10);
}
```

## [Days Between](../../../specs/language/expressions/date.md#days-between-operation)

Returns the signed number of days from `from` to `to`.

```ts
(from: string, to: string): number =>
    Math.round(
        (new Date(to + "T00:00:00Z").getTime() -
         new Date(from + "T00:00:00Z").getTime()) / 86_400_000
    )
```
