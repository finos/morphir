# Select [Step](pipeline.md#steps)

## [Summary][summary]

A Select is a pipeline step that applies a per-row transformation to
its input [dataset][dataset], producing a new dataset whose schema is
the ordered list of output columns declared by the Select. Each output
column is defined by an [expression][expr] evaluated independently for
every input row.

Select is a pure, row-at-a-time operation: it does not add, remove, or
reorder rows, and the expression of one output column cannot reference
another output column of the same Select (see [Scope](#scope)).

## [Structure][struct]

A Select is written as a list item in the enclosing pipeline's
[Steps](pipeline.md#steps) list, whose inline payload is a markdown
link to this page. Its nested children are the **output column
definitions**, in the order in which they appear in the produced
dataset's schema.

### Output Column

Each output column is one nested list item directly under the Select.
The item's inline payload names the column and declares its type; the
column's defining expression appears as the item's single nested
child.

```markdown
- `<column name>` : [<datatype>][...]
  - <expression>
```

The components are:

- **`<column name>`** — the name of the new column, written between
  backticks, exactly as in a [dataset schema][schema].
- **`[<datatype>][...]`** — a markdown link to the column's
  [datatype][dt], following the same convention as a dataset
  schema entry.
- **`<expression>`** — any expression form defined in the
  [expressions overview][expr]: a literal, a variable, an
  [infix][infix] or [nested-list][nested] application, or a
  [decision tree][dtree]. The expression must evaluate to a value of
  the declared datatype.

The output schema of the Select is the ordered list of declared
columns. A Select must declare at least one output column.

### Scope

Inside an output column's defining expression, every variable leaf
(written `[name][var]`) refers to a column of the Select's **input**
schema — the schema of the dataset produced by the previous step (or
the pipeline's input, when the Select is the first step).

Newly declared output columns of the same Select are **not** in scope:
an output column expression cannot reference sibling output columns,
regardless of their position in the list. This rule makes every output
column independently evaluable and removes any need for dependency
analysis between sibling columns.

Authors who need sequential, let-style bindings should compose
multiple Select steps: the columns produced by an earlier Select are
in scope as input columns of any later step.

A variable whose name does not match any input column makes the Select
ill-formed.

## Evaluation

Given an input dataset matching the Select's input schema, the Select
produces an output dataset as follows:

1. The output schema is the ordered list of declared output columns,
   each with its declared name and datatype.
2. For each row of the input dataset, in input order, a corresponding
   output row is produced. The value of each output column in that
   row is the result of evaluating the column's defining expression
   with the input row's columns bound as variables (per
   [Scope](#scope)).
3. The number of output rows equals the number of input rows; row
   order is preserved.

Output columns may be evaluated in any order, or in parallel, because
they cannot reference one another.

## [Test cases][tc]

Given an input dataset with schema:

- `first name`: [text][str]
- `last name`: [text][str]
- `amount`: [number][num-type]

and rows:

| `first name` | `last name` | `amount` |
| ------------ | ----------- | -------- |
| `"Ada"`      | `"Lovelace"`| `1500`   |
| `"Alan"`     | `"Turing"`  | `500`    |

the Select:

```markdown
- [Select][select]
  - `full name` : [text][str]
    - [concat][cat]
      - [first name][var]
      - [last name][var]
  - `discount tier` : [text][str]
    - [if][if] [amount][var] [>][gt] [1000][num]
      - [then][then] ["tier-2"][str]
    - [else][else] ["tier-1"][str]

[cat]: ../expressions/string.md#concatenate-operation
[else]: ../expressions/decision-tree.md#else
[gt]: ../expressions/ordering-relation.md#greater-than-derived-operation
[if]: ../expressions/decision-tree.md#if
[num]: ../expressions/number.md#literals
[select]: select.md
[str]: ../expressions/string.md#literals
[then]: ../expressions/decision-tree.md#then
[var]: ../expressions/README.md#variables
```

produces an output dataset with schema:

- `full name`: [text][str]
- `discount tier`: [text][str]

and rows:

| `full name`    | `discount tier` |
| -------------- | --------------- |
| `"AdaLovelace"`| `"tier-2"`      |
| `"AlanTuring"` | `"tier-1"`      |

[dataset]: dataset.md
[dt]: ../concepts/datatype.md
[dtree]: ../expressions/decision-tree.md
[expr]: ../expressions/README.md
[infix]: ../expressions/README.md#infix-form
[nested]: ../expressions/README.md#nested-list-form
[num-type]: ../expressions/number.md
[schema]: dataset.md#schema
[str]: ../expressions/string.md
[struct]: ../metadata/structure.md
[summary]: ../metadata/summary.md
[tc]: ../concepts/test-case.md
