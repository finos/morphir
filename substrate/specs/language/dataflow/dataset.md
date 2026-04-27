# Dataset

## [Summary][summary]

A dataset is a logical representation of some tabular data made up of 
rows and columns.

## [Structure][struct]

### Schema

Defines the columns of the dataset by listing out each column with name, 
[type][dt] and an optional description.

### Identifier

Names the fields whose values uniquely identify a row. The identifier
is declared as a list of one or more field names drawn from the
[Schema](#schema). A single field is a simple key; two or more fields
form a composite key.

The listed order is canonical for presentation but not semantically
significant: the identifier is a set of fields, and two rows are
considered to have the same key when their values agree on every
listed field.

Fields used in the identifier:

- Must be declared in the schema.
- May be [required or optional](../concepts/optionality.md). When a
  field is optional, two rows that are both absent in that field are
  treated as equal on that field. Absence is matched by absence, not
  by any sentinel value.
- Must have a type that supports equality.

A dataset declaration with no Identifier section has no declared
primary key.

### Constraints

[summary]: ../metadata/summary.md
[struct]: ../metadata/structure.md
[dt]: ../concepts/datatype.md