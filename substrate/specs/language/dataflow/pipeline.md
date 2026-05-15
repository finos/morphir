# Pipeline

## [Summary][summary]

A pipeline is a reusable sequence of [operations][op] over [datasets][dataset].
It has exactly one input dataset and one output dataset; each step
consumes the previous step's output and produces the next step's input.

A pipeline references datasets by schema, not by identity. Binding a
pipeline to specific datasets is the job of a data flow graph,
specified separately.

## [Structure][struct]

A pipeline is written as a markdown document with three required
sections — [Input](#input), [Steps](#steps), and [Output](#output) —
and an optional [Test cases](#test-cases) section.

### Input

The [schema][schema] of the dataset that enters the first step. Written
as a list of column entries in the same shape as a
[dataset schema][schema]: each entry gives the column name in
backticks, its [datatype][dt], and an optional description.

The input schema is **required**. The columns it declares are the
variables in scope for any expression evaluated by the first step.

### Output

The [schema][schema] of the dataset produced by the last step. Written
in the same shape as the [Input](#input) schema.

The output schema is **required**. It must match — column-for-column,
in order, by name and datatype — the output schema of the last step.

### Steps

An ordered list of step operations. Each step receives the previous
step's output (or the pipeline's input, for the first step) and
produces the next step's input (or the pipeline's output, for the last
step).

The body of this section is a **numbered markdown list**. Each
top-level item is one step. The item's inline payload is a markdown
link to the step operation's specification; the item's nested children
are the parameters of that operation, in the shape defined by the
operation's own spec.

```markdown
## Steps

1. [<step operation>][...]
   - <step parameters>
2. [<step operation>][...]
   - <step parameters>
```

Step recognition is based on the link target, not the link text:
authors may write `[Select]`, `[project]`, or any other phrasing as
long as the link points to the anchor of the intended step operation.

A pipeline must contain at least one step.

The step operations currently defined are:

- [Select](select.md) — applies a per-row transformation, producing a
  dataset whose schema is the ordered list of output columns declared
  by the Select.

### [Test cases][tc]

A pipeline document may optionally include a `Test cases` section
following the conventions of the [Test Case][tc] concept. The section
is **optional**: pipelines without test cases are well-formed.

As with every other named construct in substrate — concepts,
expressions, step operations, decision-tree keywords — the section is
identified by linking its heading to the
[Test Case specification][tc], not by the visible heading text. An
interpreter recognizes a `## [Test cases][tc]` heading as the test
cases section because of the link target, not because of the string
`"Test cases"`. Authors may choose any visible heading text (`Test
cases`, `Tests`, `Examples to verify`, …) provided the heading is a
markdown link whose target is the
[Test Case specification][tc]. The same rule applies wherever a `Test
cases` section appears in any other substrate document.

Because a pipeline's input and output are whole datasets, test cases
use the [Scenario Form][tc-scenario]. A pipeline has exactly one
unnamed input dataset and one unnamed output dataset, so each
scenario's `Inputs` and `Expected outputs` subsections take the
arity-1 shape: their body holds the dataset directly as an inline
markdown table, with no inner heading.

Each scenario's input dataset must match the pipeline's
[Input](#input) schema, and its expected output dataset must match the
pipeline's [Output](#output) schema, in both cases column-for-column,
in order, by name and datatype. An interpreter executes a scenario by
evaluating the pipeline against the scenario's input dataset and
comparing the produced dataset to the scenario's expected output
dataset; the row-order semantics of [Evaluation](#evaluation) apply.

## Evaluation

Given an input dataset matching the declared [Input](#input) schema,
the pipeline produces an output dataset as follows:

1. The steps in [Steps](#steps) are evaluated in document order.
2. The first step receives the pipeline's input dataset. Each
   subsequent step receives the dataset produced by the previous
   step. The dataset produced by the last step is the pipeline's
   output.
3. Each step's evaluation is defined by its own specification (e.g.
   [Select's Evaluation](select.md#evaluation)).

A pipeline is **well-formed** when, in addition to the constraints
above:

- For every step after the first, the step's declared input schema
  (as defined by its operation) is compatible with the previous
  step's output schema. For Select, this means every variable
  referenced by any output column expression names a column of the
  previous step's output schema.
- The first step's expressions reference only columns of the
  pipeline's [Input](#input) schema.
- The last step's output schema matches the pipeline's
  [Output](#output) schema column-for-column, in order, by name and
  datatype.

An interpreter may reject an ill-formed pipeline without evaluating
it.

## [Examples][examples]

A single-step pipeline that derives two columns from an `Employees`
input dataset:

````markdown
# Onboarding Tiering

## Input

- `first name`: [text][str-t]
- `last name`: [text][str-t]
- `amount`: [number][num-t]

## Steps

1. [Select][select]
   - `full name` : [text][str-t]
     - [concat][cat]
       - [first name][var]
       - [last name][var]
   - `discount tier` : [text][str-t]
     - [if][if] [amount][var] [>][gt] [1000][num]
       - [then][then] ["tier-2"][str]
     - [else][else] ["tier-1"][str]

## Output

- `full name`: [text][str-t]
- `discount tier`: [text][str-t]

## [Test cases][tc]

### Tiers a mix of above- and below-threshold rows

#### Inputs

| `first name` | `last name`  | `amount` |
| ------------ | ------------ | -------- |
| `"Ada"`      | `"Lovelace"` | 1500     |
| `"Alan"`     | `"Turing"`   | 500      |

#### Expected outputs

| `full name`     | `discount tier` |
| --------------- | --------------- |
| `"AdaLovelace"` | `"tier-2"`      |
| `"AlanTuring"`  | `"tier-1"`      |

[cat]: /substrate/language/expressions/string.md#concatenate-operation
[else]: /substrate/language/expressions/decision-tree.md#else
[gt]: /substrate/language/expressions/ordering-relation.md#greater-than-derived-operation
[if]: /substrate/language/expressions/decision-tree.md#if
[num]: /substrate/language/expressions/number.md#literals
[num-t]: /substrate/language/expressions/number.md
[select]: /substrate/language/dataflow/select.md
[str]: /substrate/language/expressions/string.md#literals
[str-t]: /substrate/language/expressions/string.md
[tc]: /substrate/language/concepts/test-case.md
[then]: /substrate/language/expressions/decision-tree.md#then
[var]: /substrate/language/expressions/README.md#variables
````

A two-step pipeline composes Selects: the second step sees the first
step's output columns as its input columns. For example, a second
Select could reference `full name` (a column produced by the first
step) but not any column of the original pipeline input that was
dropped by the first step.

[dataset]: dataset.md
[dt]: ../concepts/datatype.md
[examples]: ../metadata/examples.md
[op]: ../concepts/operation.md
[schema]: dataset.md#schema
[struct]: ../metadata/structure.md
[summary]: ../metadata/summary.md
[tc]: ../concepts/test-case.md
[tc-scenario]: ../concepts/test-case.md#scenario-form
