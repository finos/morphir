# Choice

A Choice is a [type](type.md) whose members are partitioned into a fixed
set of named **variants**. Every value of a Choice type is exactly one
variant. A variant may carry zero or more typed fields; the fields of
different variants are independent.

A Choice with zero-field variants only is an enumeration: its values are
effectively named constants. [Boolean](../expressions/boolean.md) and
[Collection Multiplicity](../expressions/collection-multiplicity.md) are
built-in examples. Choices with data-carrying variants express cases like
"a maturity bucket is either _Open_, a day _Range_, or _Beyond_ a
threshold."

A choice type may be declared anywhere in the specification corpus. A
declaration is identified by a heading whose text links to this concept
page:

```markdown
### Maturity Bucket [Choice](choice.md)
```

## Variants

A Choice type declares its variants in a **Variants** section as a
bulleted list. Each entry supplies:

- A **variant name**, unique within the Choice type.
- A short description of the variant's meaning.
- Zero or more **fields**, each nested as a sub-bullet. Each field
  supplies a name, a declared [type](type.md) linked to its definition,
  an [optionality](optionality.md) marking, and a short description.

For example:

```markdown
#### Variants

- **Open** — no contractual maturity.
- **Range** — a contiguous range of days.
  - `from_days` — [Integer](../expressions/integer.md), required.
    Lower bound, inclusive.
  - `to_days` — [Integer](../expressions/integer.md), required.
    Upper bound, inclusive.
- **Beyond** — longer than a threshold.
  - `from_days` — [Integer](../expressions/integer.md), required.
    Lower bound, exclusive.
```

Variant names are unique within a Choice type. Field names are unique
within a variant but may repeat across variants with unrelated meanings.
The order of variant declaration is canonical for presentation; it does
not by itself imply ordering semantics.

## Operations

The following meta-operations are available on every Choice type. They
reference variant and field names declared by the specific Choice type
in scope.

### Construct [Operation](operation.md)

_[Required](operation.md#required)._ Returns a new value of the Choice
type by selecting a named variant and supplying a value for each of that
variant's fields. Required fields must be supplied; optional fields may
be supplied as absent.

#### Test cases

| Choice type | Variant | Field values | Output |
| ---------------- | ------- | ------------------------- | --------------- |
| `Maturity Bucket` | `Open` | — | `Open` |
| `Maturity Bucket` | `Range` | `from_days: 2, to_days: 7` | `Range(2, 7)` |
| `Maturity Bucket` | `Beyond` | `from_days: 365` | `Beyond(365)` |

### Is Variant [Operation](operation.md)

_[Required](operation.md#required)._ Returns [Boolean][bool] `true` when
the value is the named variant, `false` otherwise.

#### Test cases

| Value         | Variant | Output |
| ------------- | ------- | ------ |
| `Open`        | `Open`  | true   |
| `Open`        | `Range` | false  |
| `Range(2, 7)` | `Range` | true   |

### Match [Operation](operation.md)

_[Required](operation.md#required)._ Branches on which variant a value
is. For each variant of the Choice type, Match takes an expression to
evaluate when the value is that variant. The expression may refer to
the variant's fields by name. The result is the value of the expression
for the variant that matched.

Every variant of the Choice type must be covered: Match is exhaustive.
All branch expressions must produce values of the same type; that type
is the type of the Match result.

#### Test cases

For a Choice type `Signed Integer` with variants `Positive` (field
`value`), `Zero` (no fields), and `Negative` (field `value`), Match is
used to compute the absolute value:

| Value          | Positive branch | Zero branch | Negative branch | Output |
| -------------- | --------------- | ----------- | --------------- | ------ |
| `Positive(5)`  | `value`         | `0`         | `value`         | 5      |
| `Zero`         | `value`         | `0`         | `value`         | 0      |
| `Negative(3)`  | `value`         | `0`         | `value`         | 3      |

## Type Class Instances

- **[Equality](../expressions/equality.md)** is implemented automatically
  when every field type across every variant implements Equality. Two
  values are equal when they are the same variant and, for each field,
  the two values are equal under that field's type's Equality. When a
  variant has no fields, comparing two values of that variant is
  equality on variant name alone. This makes pure-enumeration Choices
  (zero-field variants) equal exactly when their variants match, which
  matches [Boolean](../expressions/boolean.md)'s behaviour.

- **[Ordering](../expressions/ordering.md)** is not implemented by
  default. A specific Choice may declare an Ordering instance in its
  own declaration and state the comparison rule — for example, maturity
  buckets ordered by the day ranges their variants represent.

[bool]: ../expressions/boolean.md
