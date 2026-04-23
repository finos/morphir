# Record

A Record is a composite [type](type.md) with a fixed set of named fields.
Each field has a declared [type](type.md) and an [optionality](optionality.md)
marking. The identity of a record type is its name: two record types with
the same fields but different names are distinct.

A record type may be declared anywhere in the specification corpus —
inside a dedicated module, as a subsection of a larger document, or
alongside the logic that consumes it. A declaration is identified by a
heading whose text links to this concept page, following the same pattern
that [operations](operation.md) use to link to their concept:

```markdown
### Customer [Record](record.md)
```

Field names are unique within a record type.

## Fields

A record type declares its fields in a **Fields** section. Each entry
supplies:

- A **name** by which the field is accessed.
- A declared [type](type.md) linked to its definition.
- An [optionality](optionality.md) marking — _required_ or _optional_.
  Required is the default.
- A short description of the field's meaning.

Fields are listed in declaration order. Declaration order is canonical
for presentation and serialisation but not semantically significant for
access: fields are always addressed by name, never by position.

The fields are typically presented as a table:

| Name    | Type                               | Optionality | Description                  |
| ------- | ---------------------------------- | ----------- | ---------------------------- |
| `name`  | [String](../expressions/string.md) | required    | The customer's display name. |
| `email` | [String](../expressions/string.md) | optional    | Contact email, if supplied.  |

## Operations

The following meta-operations are available on every record type. They
reference field names declared by the specific record type in scope.

### Get Field [Operation](operation.md)

_[Required](operation.md#required)._ Returns the value of the named field
from a record. If the field is declared [optional](optionality.md) and no
value is present, the result is absent; see [Optionality](optionality.md)
for absence semantics.

#### Test cases

| Record                           | Field   | Output |
| -------------------------------- | ------- | ------ |
| `{ name: "Ada", email: "a@x" }`  | `name`  | "Ada"  |
| `{ name: "Ada", email: "a@x" }`  | `email` | "a@x"  |
| `{ name: "Ada", email: absent }` | `email` | absent |

### With Field [Operation](operation.md)

_[Required](operation.md#required)._ Returns a new record of the same
type with the named field replaced by the supplied value. All other
fields retain their current values. The supplied value must match the
field's declared type; its presence or absence must be compatible with
the field's optionality.

#### Test cases

| Record                          | Field   | Value  | Output                           |
| ------------------------------- | ------- | ------ | -------------------------------- |
| `{ name: "Ada", email: "a@x" }` | `name`  | "Bea"  | `{ name: "Bea", email: "a@x" }`  |
| `{ name: "Ada", email: "a@x" }` | `email` | absent | `{ name: "Ada", email: absent }` |

### Construct [Operation](operation.md)

_[Required](operation.md#required)._ Returns a new record of the
specified type given a value for each field. Required fields must be
supplied; optional fields may be supplied as absent.

#### Test cases

| Record type | Field values                 | Output                           |
| ----------- | ---------------------------- | -------------------------------- |
| `Customer`  | `name: "Ada", email: "a@x"`  | `{ name: "Ada", email: "a@x" }`  |
| `Customer`  | `name: "Ada", email: absent` | `{ name: "Ada", email: absent }` |

## Type Class Instances

Record does not itself implement a [type class](type-class.md). A specific
record type may declare type class instances in its own declaration when
useful — for example, an [Equality](../expressions/equality.md) instance
defined field-by-field. Such declarations are made per record type, not
derived automatically, because the treatment of absent fields in equality
and ordering is a design decision of the specific type.
