# Optionality

A property applied to a _slot_ — a [parameter][param], an [attribute][attr],
a record field, or the result of an [operation][op] — indicating whether
the slot must carry a value or may be absent.

Optionality is a property of the slot itself, not a type constructor. A
slot of type [Integer][int] marked optional still has type [Integer][int];
what varies is whether a value is present. There is no wrapper type, no
`Maybe`, no `Option`. Operations consume and produce values of the declared
type directly.

## Rationale

Generic wrapper types (`Maybe a`, `Option<T>`, `Nullable<T>`) force every
downstream operation to either unwrap the value or be lifted over the
wrapper. Even simple arithmetic acquires plumbing. Substrate instead
attaches optionality to the binding site, so ordinary expressions read
naturally; absence handling surfaces only where it is semantically
relevant.

## States

A slot is in exactly one of two states:

- **Required** — a value must be supplied. Absence is an error detected at
  the point where the slot is bound.
- **Optional** — a value may be supplied. Absence is an acceptable state
  called _absent_.

Required is the default. A slot must be explicitly marked to become
optional.

## Absence

Absence is not a member of any [type][type]. It is a property of the slot:
the slot exists but carries no value. [Equality][eq], [ordering][ord], and
arithmetic are not defined between a value and absence. Two absent slots
are not considered equal to each other by [Equal][eq-equal]; presence must
be checked first.

## Where Optionality Applies

- **[Parameters][param]** of operations. An operation may declare any
  parameter optional.
- **[Attributes][attr]** of types. For example, the maximum cardinality
  attribute of [Collection][col] is optional; when unspecified, the
  collection is unbounded.
- **Fields of records.** Each field carries its own optionality marking.
- **Operation results.** An operation may declare that its result is
  optional, meaning the operation produces either a value of the declared
  type or absence. [Min Or None][min-or-none] is an example.

In each case, optionality is declared alongside the slot's declared type
and carries the semantics defined here.

## Absence Semantics in Operations

An [operation][op] applied to an absent input is undefined and must not be
evaluated. Callers must coalesce an optional value with
[Default](#default-operation) before passing it to an operation whose
parameter is required.

This rule is uniform: operations are not implicitly lifted over absence, do
not silently skip absent inputs, and do not propagate absence to their
result. Any behaviour that depends on absence must be expressed explicitly
in the user module using [Is Present](#is-present-operation) or
[Default](#default-operation).

Operations that _produce_ an optional result declare so explicitly and
describe the conditions under which the result is absent.

## Operations on Optional Slots

Two operations are universally available for reasoning about absence,
regardless of the slot's declared type.

### Is Present [Operation][op]

_[Required][req]._ Returns [Boolean][bool] `true` when the slot carries a
value, `false` when the slot is absent.

#### Test cases

| Slot value | Output |
| ---------- | ------ |
| `42`       | true   |
| absent     | false  |

### Default [Operation][op]

_[Required][req]._ Returns the slot's value when present, or the supplied
fallback value when absent. The fallback must have the slot's declared
type.

#### Test cases

| Slot value | Fallback | Output |
| ---------- | -------- | ------ |
| `42`       | `0`      | 42     |
| absent     | `0`      | 0      |
| `-1`       | `0`      | -1     |

## Interaction with Types and Type Classes

Optionality is orthogonal to [Type][type]. Declared type determines which
[type class][tc] instances and operations apply; optionality determines
whether the slot must be occupied. Marking a slot optional does not change
its type and does not remove or add type class instances.

[attr]: attribute.md
[bool]: ../expressions/boolean.md
[col]: ../expressions/collection.md
[eq]: ../expressions/equality.md
[eq-equal]: ../expressions/equality.md#equal-operation
[int]: ../expressions/integer.md
[min-or-none]: ../expressions/collection.md#min-or-none-operation
[op]: operation.md
[ord]: ../expressions/ordering.md
[param]: parameter.md
[req]: operation.md#required
[tc]: type-class.md
[type]: type.md
