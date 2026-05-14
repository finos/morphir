# Pipeline

## [Summary][summary]

A pipeline is a reusable sequence of [operations][op] over [datasets][dataset].
It has exactly one input dataset and one output dataset; each step
consumes the previous step's output and produces the next step's input.

A pipeline references datasets by schema, not by identity. Binding a
pipeline to specific datasets is the job of a data flow graph,
specified separately.

## [Structure][struct]

### Input

The [schema][schema] of the dataset that enters the first step. Optional. 
May be inferred from the operations.

### Output

The [schema][schema] of the dataset produced by the last step. Optional. 
May be inferred from the operations.

### Steps

An ordered list of operations. Each step receives the previous step's
output (or the pipeline's input, for the first step) and produces the
next step's input (or the pipeline's output, for the last step).

The only step operation defined for now is:

- **Select** — applies a per-row transformation, producing a dataset
  with the declared output schema.

[dataset]: dataset.md
[op]: ../concepts/operation.md
[schema]: dataset.md#schema
[struct]: ../metadata/structure.md
[summary]: ../metadata/summary.md
