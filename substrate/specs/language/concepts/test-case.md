# Test Case

## Summary

A test case is a documented input/output example for a unit of substrate
logic — an [operation](operation.md), a
[pipeline](../dataflow/pipeline.md), a [select](../dataflow/select.md),
or any other definition whose semantics are observable as a function
from inputs to expected outputs. Test cases are authored directly in
the same markdown document as the definition they exercise and serve
as both human documentation and machine-runnable acceptance criteria.
Two surface forms are provided: a compact [Table Form](#table-form)
for small input/output examples, and a [Scenario Form](#scenario-form)
for cases whose inputs or outputs are themselves large structured
values.

## Overview

Any substrate definition whose meaning can be expressed as a function
from inputs to expected outputs may carry test cases. Conventional
sites include:

- An [operation](operation.md) of a [type class](type-class.md), where
  the test cases must give full coverage of the operation's behavior.
- A [pipeline](../dataflow/pipeline.md), where inputs and outputs are
  whole datasets.
- A [select](../dataflow/select.md), a
  [decision tree](../expressions/decision-tree.md), or any other
  expression-bearing definition.

Test cases are placed directly under the heading of the definition
they exercise. Heading depth is relative: the test cases heading is
one level deeper than its enclosing definition, regardless of where
that definition appears in the surrounding document hierarchy.

Like every other substrate concept, a test cases section identifies
itself by linking to this document. Unlike concepts that have a
per-instance name — an [operation](operation.md) named `NOT`, a
[record](record.md) named `Customer` — a test cases section has no
instance name: it is simply *the* test cases for the enclosing
definition. The heading is therefore a single-link heading whose
text is `Test cases` and whose target is `test-case.md`.

Per the [link reference convention](../README.md#link-references),
authors should define a short alias once at the bottom of the
enclosing document and use that alias at the heading. The
conventional alias is `tc`. For a definition that lives in
`specs/language/expressions/` or `specs/language/dataflow/`:

```markdown
## [Test cases][tc]

…

[tc]: ../concepts/test-case.md
```

Tooling recognizes the section by this link target, not by the
visible heading text.

A definition's `Test cases` section uses **either** the
[Table Form](#table-form) **or** the [Scenario Form](#scenario-form),
not both. The two forms are semantically equivalent; pick whichever
reads better given the size of the inputs and outputs.

### Inputs and Expected Outputs

Both forms describe each test case as a pairing of **inputs** with
**expected outputs**. The vocabulary is borrowed from
behavior-driven development, but substrate is purely functional: there
is no notion of `Given` / `When` / `Then`, no setup, no side effects,
and no temporal ordering. A test case is just a row in the graph of
the function under test — a particular input mapped to its expected
output.

The names of a definition's inputs and outputs are taken from the
definition itself: an operation's [parameters](parameter.md) for its
inputs, a pipeline's named source datasets for its inputs, and so on
for outputs. Test cases must use these names verbatim wherever names
appear (column headers in the table form; sub-subsection headings in
the scenario form).

## Table Form

The table form is a single markdown table whose rows enumerate test
cases. Each row is one test case; the row's cells supply that case's
inputs and expected output. Use this form whenever every input and
every output fits comfortably in a single table cell.

### Structure

The table has one column per input and one column per expected output.
Column headers are the parameter names in backticks, exactly as declared
in the operation's `Inputs` and `Outputs` sections. Column order in the
table is free — binding is by name, not position. Missing columns are
an error; unknown columns are an error.

The runner looks up each column header against the operation's signature to
determine the parameter's type, then uses the type's registered literal parser
to interpret the cell value.

### Example

Under the [Integer Division](../expressions/integer.md#integer-division-required-operation)
operation, which declares inputs `dividend` and `divisor` and output `result`:

```markdown
#### [Test cases][tc]

| `dividend` | `divisor` | `result` |
| ---------- | --------- | -------- |
| 7          | 2         | 3        |
| -7         | 2         | -4       |
| 0          | 3         | 0        |

[tc]: ../concepts/test-case.md
```

## Scenario Form

The scenario form expresses each test case as its own named
subsection — a *scenario* — so that inputs and expected outputs may
themselves be large structured values such as datasets, records, or
nested expressions. This form is required whenever any input or
expected output is too large to fit inside a single table cell, since
markdown does not support tables nested inside table cells.

### Structure

Under the `Test cases` heading, each scenario appears as its own
subsection. Each scenario consists of:

- A **heading** naming the scenario in human-readable terms (e.g.
  `Filters orders above the threshold`,
  `New customer with no prior orders`). Scenario names should describe
  the situation under test, not restate the inputs.
- An **optional but encouraged prose description** immediately under
  the scenario heading, explaining what the scenario demonstrates and
  why it is worth testing. Skip the description only when the scenario
  name fully conveys intent.
- An `Inputs` subsection.
- An `Expected outputs` subsection.

Both `Inputs` and `Expected outputs` follow the same labeling rule,
driven by the arity of the definition's inputs and outputs
respectively:

- **Arity 1 — single unnamed input or output:** the section body
  holds the value directly, with no inner heading. The value may be an
  inline markdown table (for a dataset), a substrate literal, a
  composed expression in either of the
  [expression forms](../expressions/README.md), or any other
  substrate value form.
- **Arity > 1 — multiple named inputs or outputs:** each named input
  or output appears as its own sub-subsection whose heading is the
  input or output name as declared by the definition. Names must
  match the definition's declared names exactly.

### Example — Single Dataset In, Single Dataset Out

Under a hypothetical pipeline `LargeOrders` that takes one input
dataset and produces one output dataset:

```markdown
## [Test cases][tc]

### Filters orders above the threshold

Demonstrates that orders with `amount` strictly greater than the
configured threshold are retained and all others are dropped.

#### Inputs

| order_id | amount |
| -------- | ------ |
| 1        | 50     |
| 2        | 150    |
| 3        | 200    |

#### Expected outputs

| order_id | amount |
| -------- | ------ |
| 2        | 150    |
| 3        | 200    |

[tc]: ../concepts/test-case.md
```

### Example — Multiple Named Inputs

Under a hypothetical pipeline `EnrichOrders` taking two named input
datasets, `orders` and `customers`, and producing one output dataset:

```markdown
## [Test cases][tc]

### Joins each order to its customer

#### Inputs

##### orders

| order_id | customer_id | amount |
| -------- | ----------- | ------ |
| 1        | A           | 50     |
| 2        | B           | 150    |

##### customers

| customer_id | name  |
| ----------- | ----- |
| A           | Alice |
| B           | Bob   |

#### Expected outputs

| order_id | customer_id | name  | amount |
| -------- | ----------- | ----- | ------ |
| 1        | A           | Alice | 50     |
| 2        | B           | Bob   | 150    |

[tc]: ../concepts/test-case.md
```

## Choosing a Form

Use the [Table Form](#table-form) when every input and every output
fits naturally in a single cell — typically scalar values, short
strings, or small literals. Most operations on built-in types fall
into this category.

Use the [Scenario Form](#scenario-form) when at least one input or
output is itself a structured value that does not fit in a cell —
datasets, large records, or deeply nested values. Pipelines and
selects are the typical sites.

A definition's test cases must not mix the two forms. If a single
edge case in an otherwise tabular definition outgrows the table,
convert all of that definition's cases to the scenario form so that
readers and tooling encounter one consistent shape per definition.
