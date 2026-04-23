# Decision Table

A Decision Table is a tabular representation of a conditional: a set of
rules, evaluated top to bottom, where the first rule whose conditions all
match determines the result. It is the tabular counterpart to nested
[If-Then-Else](../expressions/boolean.md#if-then-else-operation) and
complements the decision-tree style of branching with a data-style form
that reads as a single artifact.

Decision Tables are well suited to regulatory material, rate sheets,
classification rules, and any logic whose authoritative reference is
itself a table. The rendered markdown table is the authoritative
specification; no separate machine form is required.

A decision table may be declared anywhere in the specification corpus.
A declaration is identified by a heading whose text links to this concept
page:

```markdown
### Retail Outflow Rate [Decision Table](decision-table.md)
```

## Structure

A decision table declaration has three parts:

- **[Inputs](#inputs)** — the named values the table reads, each with its
  declared [type](type.md).
- **[Outputs](#outputs)** — the named values the table produces, each with
  its declared [type](type.md).
- **[Rules](#rules)** — a markdown table where each row is a rule. Column
  headers name an input or output; headers prefixed with `→` name outputs,
  all other headers name inputs.

### Inputs

A bulleted list declaring each input with its name and type. Input order
is not semantically significant; inputs are addressed by name.

```markdown
#### Inputs

- `counterparty` — [Counterparty](counterparty.md)
- `insured` — [Boolean](../expressions/boolean.md)
- `account_type` — [Account Type](account-type.md)
```

### Outputs

A bulleted list declaring each output with its name and type.

```markdown
#### Outputs

- `outflow_rate` — [Decimal](../expressions/decimal.md)
```

### Rules

A markdown table. The header row names inputs and outputs; `→` marks
output columns. Each subsequent row is a rule.

A row matches when every condition cell matches. A matching row's output
cells determine the result. Rows are evaluated in document order and the
first matching row wins.

## Condition Cells

A condition cell takes one of the following forms:

- **Literal value.** A bare value matches when the input is
  [Equal](../expressions/equality.md#equal-operation) to the value under
  the input type's Equality instance.
- **Comparison.** One of `=`, `≠`, `>`, `≥`, `<`, `≤` followed by a
  literal value. ASCII equivalents `==`, `!=`, `>=`, `<=` are also
  accepted. Comparisons require the input type to implement
  [Ordering](../expressions/ordering.md); `=` and `≠` require only
  [Equality](../expressions/equality.md).
- **Blank (don't care).** An empty cell matches any input value.

The table form is intentionally limited to literals and simple
comparisons so that each rule remains readable as data. Arbitrary
predicates beyond these forms are expressed by introducing a derived
input: define the predicate as a named value upstream of the decision
table and reference that name as an ordinary input column. This keeps
the table readable while preserving full expressiveness.

## Result Cells

A result cell contains a literal value of the output column's declared
type. Expressions, function calls, and references to other values are
not permitted in result cells; computations that depend on a decision's
result are performed downstream by operations that consume the table's
outputs.

## Otherwise Row

A rule whose first cell is the literal word `otherwise` is a catch-all:
it matches any input and must appear as the last row. Its condition
cells beyond the first are ignored; its output cells supply the result
when no earlier rule matched.

## Completeness

A decision table must account for every possible input. Completeness is
satisfied when any of the following holds:

- An `otherwise` row is present.
- Every input column is a [Choice](choice.md) used only with literal
  cells, and the rules collectively cover every combination of variants.

If neither condition holds, an input that matches no rule is a runtime
error detected at evaluation time.

## Evaluation

Given values for every input:

1. Consider each row in document order.
2. For each row, evaluate every condition cell against the corresponding
   input. A row matches when all its condition cells match.
3. On the first matching row, produce each output as the value in the
   corresponding result cell.
4. If no row matches and no `otherwise` row is present, evaluation is
   undefined.

## Invocation

A decision table is invoked from a user module exactly like an
[operation](operation.md): the table's heading link is the parent item
of a nested list, and each child item supplies one of the table's
inputs in the same order they are declared. The result is the table's
output. When a table declares a single output, the invocation yields
that output directly; when it declares multiple outputs, the invocation
yields a record whose fields are the declared output names.

For example, given the table declared below, the retail outflow rate
for a classified deposit row is obtained as:

```markdown
- [Retail Outflow Rate](retail-outflow-rate.md)
  - `row.counterparty`
  - `row.insured`
  - `row.account_type`
  - `row.relationship`
```

This reads the same as any other operation call and is composable with
arithmetic and collection operations — for example, multiplying the
returned rate by an amount, or mapping the table over a collection of
rows.

## Relationship to If-Then-Else

A decision table with two rules and one output is semantically equivalent
to a single [If-Then-Else](../expressions/boolean.md#if-then-else-operation)
applied to the conjunction of the first row's conditions. A table with
N rules is equivalent to a cascade of nested If-Then-Else. Authors choose
the form that best communicates intent: If-Then-Else for one-off
branches; Decision Table when the same condition columns determine
multiple related results and the rules form an authoritative table.

## Example

```markdown
### Retail Outflow Rate [Decision Table](decision-table.md)

#### Inputs

- `counterparty` — [Counterparty](counterparty.md)
- `insured` — [Boolean](../expressions/boolean.md)
- `account_type` — [Account Type](account-type.md)
- `relationship` — [Relationship](relationship.md)

#### Outputs

- `outflow_rate` — [Decimal](../expressions/decimal.md)

#### Rules

| counterparty | insured | account_type      | relationship | → outflow_rate |
| ------------ | ------- | ----------------- | ------------ | -------------- |
| Retail       | true    | Transactional     |              | 0.03           |
| Retail       | true    | Non-Transactional | Established  | 0.03           |
| Retail       | true    | Non-Transactional | None         | 0.10           |
| Retail       | false   |                   |              | 0.40           |
| otherwise    |         |                   |              | 0.40           |
```
