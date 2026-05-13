# Dataset

## [Summary][summary]

A dataset is a logical representation of some tabular data made up of
rows and columns.

## [Structure][struct]

### Schema

Defines a collection of columns with the following details for each:

- The name of the column surrounded by backticks. This is the name
  that will be used to refer to it later.
- The [datatype][dt] of the column.
- Description of the column.

## [Examples][examples]

```markdown
# [Employees][dataset]

## [Schema][schema]

- `first name`: [text][str]
- `middle name`: [text][str]
- `last name`: [text][str]
- `onboarding date`: [date][date]

[dataset]: /substrate/language/dataflow/dataset.md
[schema]: /substrate/language/dataflow/dataset.md#schema
[str]: /substrate/language/expressions/string.md
[date]: /substrate/language/expressions/date.md
[opt]: /substrate/language/concepts/optionality.md
```

[summary]: ../metadata/summary.md
[struct]: ../metadata/structure.md
[dt]: ../concepts/datatype.md
[examples]: ../metadata/examples.md
