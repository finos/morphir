# Data Binding

> Status: **Draft**. Introduced to support the workflow described in
> [business-user-solution-authoring.md](../../workflows/business-user-solution-authoring.md).
> The mechanism is general, but the workflow is the first consumer.

## Summary

A **data binding** attaches a concrete, executable data source — a
database table, a file, a query, an API endpoint, a fixture in
markdown or CSV — behind an abstract [dataset](dataset.md) definition.

The abstract dataset is the **contract**: schema, identifier,
constraints, semantics. A binding is **one realization** of that
contract in a particular **environment**. The same dataset definition
can have many bindings; the same binding never spans environments.

Specifications in the knowledge base never name physical systems.
Bindings do. This separation is what lets a single solution run
against production warehouse tables, against masked example data, and
against developer fixtures without any change to the solution itself.

## Why Bindings Are Separate from Datasets

The dataset definition answers *what* the data is. The binding
answers *where it lives, how to read it, and under what credentials*.
Mixing the two would couple every specification to a particular
deployment, defeating the goal of a portable, shareable knowledge
base.

Keeping bindings separate also lets different actors own different
parts: a business user owns the dataset definition and the
specification-environment binding (the worked examples); IT owns the
production binding; neither needs to touch the other's artifact to
do their job.

## Structure

A binding document declares the following.

### Target Dataset

A link to the [dataset](dataset.md) definition the binding realizes.
The binding is only valid if its source can be read in a way that
satisfies the target's schema, identifier, and constraints.

### Environment

A named environment the binding belongs to. Examples: `production`,
`uat`, `dev`, `specification`. The environment is metadata; it has no
built-in semantics beyond identity. Tooling uses it to choose which
binding to activate when the solution is run.

A given (dataset, environment) pair has at most one binding. A given
dataset may have any number of bindings across different environments.

### Source

How the data is physically accessed. The source is one of a small set
of binding kinds:

- **Table** — a table or view in a named database/catalog/schema.
- **Query** — a parameterized query against a named connection.
- **File** — a file at a path in a named filesystem or object store
  (CSV, Parquet, JSON Lines, etc.).
- **API** — an endpoint with a request/response shape.
- **Inline** — data embedded directly in the binding document, in
  markdown tables or CSV. This is the kind used for the
  specification-environment bindings produced by the
  [solution-authoring workflow](../../workflows/business-user-solution-authoring.md).

Each kind has its own required fields (connection name, path, query
text, etc.), but every kind must produce rows that conform to the
target dataset's schema.

### Field Mapping

How fields in the physical source map to fields in the abstract
schema. Defaults to identity (matching by name); explicit mappings
override or supply missing names, type adapters, and unit
conversions. Required when the physical layout differs from the
abstract schema.

### Access and Credentials

A reference — never an inline secret — to whatever credential or
access policy the runtime uses to read the source. Substrate
documents the *reference*; the actual secret lives in whatever secret
store the environment uses. Bindings to sensitive sources are
expected to declare the access requirement explicitly so reviewers
can see what is needed.

### Role

Whether the binding's data is treated as **observed** (actual values
read from the source — the normal case) or as **expected** (values
the solution should produce when run against companion input
bindings). The `specification` environment uses expected role for
output datasets; production and other live environments do not.

This is the mechanism behind the workflow's note that *"in the test
environment output datasets serve as expectations while in other
bindings those are actual results."*

### Acceptance Log

For bindings produced by the solution-authoring workflow, an
append-only section recording user acceptances of expected outputs:
who accepted, when, against which version of the solution, and which
input binding the expected output was derived from. The log lives
inside the binding markdown document itself, the same way revision
history is tracked in regulatory standards documents — the artifact
carries its own provenance.

Bindings that are not the product of an acceptance loop (a typical
production binding, for example) do not need an acceptance log.

### Masking Provenance

For bindings whose data was derived by masking another binding's
data, a reference to:

- the source binding the data was derived from,
- the masking rules applied (per-attribute, with optional
  dataset-level overrides),
- the version of the masking algorithm used.

Masking rules are themselves auditable artifacts: documented and
reviewed before being applied, and the resulting masked data
reviewed by the business user before being committed. The masking
provenance section is what makes that audit trail mechanically
checkable.

## Resolution

When a solution runs, tooling resolves each abstract dataset
reference to a concrete binding by looking up `(dataset, active
environment)`. Missing bindings are an error reported up front, never
silently ignored. The active environment is set by the runner — there
is no implicit default.

Solutions therefore never embed environment names. They reference
abstract datasets only. The binding layer is what makes a single
specification simultaneously:

- a contract IT can implement against production,
- an executable artifact runnable against masked examples,
- a regression test suite (when run against a `specification`
  binding, observed outputs are compared to the expected outputs in
  the binding's output datasets).

## Relationship to Other Concepts

- [dataset.md](dataset.md) — the contract a binding realizes.
- [provenance.md](../concepts/provenance.md) — the broader notion of
  origin tracking; acceptance log and masking provenance are
  specializations.
- [business-user-solution-authoring.md](../../workflows/business-user-solution-authoring.md)
  — the workflow that produces specification-environment bindings as
  one of its primary artifacts.

## Open Questions

- **Binding kinds catalog.** The list above is illustrative, not
  closed. Should the set of binding kinds be open (any plugin may
  define one) or closed (the spec enumerates them)? Probably open
  with a small standard core.
- **Schema drift detection.** When the source's physical schema
  changes, how is the binding flagged as stale? Likely a tooling
  responsibility, but the spec should say what guarantee a binding
  *claims* to provide.
- **Cross-environment lineage.** A `specification` binding is
  derived, by masking, from a `production` binding. Should that
  derivation be a first-class link (so changes propagate) or just
  documented in the masking provenance?
- **Partial bindings.** Is it useful to bind only some fields of a
  dataset (e.g., for restricted-access subsets)? If so, how do
  solutions that reference unbound fields fail — at resolution time
  or at run time?
