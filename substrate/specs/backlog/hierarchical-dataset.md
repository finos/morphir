# Hierarchical Dataset (Working Notes)

> Status: **exploration**. This document captures the problem, the
> motivating examples, and the design space. It is not yet a
> specification. Concrete language constructs will be proposed once
> the requirements are stable.

## Naming

We deliberately avoid the term *generalized dataset*: "generalized"
and "specialized" are **relative** terms — a dataset is only
generalized *with respect to* something more specific. A
**hierarchical dataset** is the right framing because the structure
we want to support is not a two-level generic/specific split but a
**multi-level hierarchy** with one top-level node and gradual
refinement across as many layers as the domain calls for.

## Problem

Many domains — finance especially — do not have a flat set of entity
types. They have **hierarchies of related types** that share a common
core but differ in the attributes that apply to each refinement. A
loan is a loan, but a mortgage, a revolving credit line, and a
syndicated term loan each carry attributes that do not make sense for
the others. Some of those further split into sub-categories with
their own additional attributes.

Multiple views of the same data are simultaneously legitimate and
needed:

- A **top-level view** treats every record as an instance of the
  shared root (e.g., "every row is a loan"). It is the right view
  for portfolio-wide aggregations, regulatory totals, and
  cross-category comparisons.
- A **leaf-level view** treats each record as an instance of its
  most-specific subtype, with exactly the attributes that subtype
  declares. It is the right view for category-specific calculations,
  pricing, and any rule that depends on attributes the parent does
  not have.
- **Intermediate views** are equally legitimate when the hierarchy
  has more than two levels — e.g., "all secured loans" sitting
  between "all loans" and "mortgages".

Some business problems need more than one level at once: a
calculation done at a higher level whose inputs depend on
lower-level attributes.

## How this is handled today (and why it hurts)

The common practice is a single wide table with:

- A **discriminator column** (e.g., `product_type`) identifying the
  subtype of each row.
- Most attribute columns marked **optional**, because no single
  subtype uses all of them.
- The applicability rule — *which columns are meaningful for which
  subtype* — kept outside the schema, in prose documentation, in
  validation code, or in tribal knowledge.

This shape causes several recurring problems:

1. **Schema lies about optionality.** A column required for
   mortgages appears optional in the table because it does not apply
   to credit cards. The schema cannot distinguish "missing because
   not applicable" from "missing because unknown" from "missing
   because the subtype requires it but the producer failed to
   populate it."
2. **Round-tripping loses information.** Going top-down is lossy:
   the receiver cannot tell which optional columns were optional
   *for that subtype* versus genuinely missing.
3. **Manual unioning.** Coarser datasets are typically assembled by
   hand from finer-grained sources, with bespoke mapping logic each
   time. The mapping is not derivable from the schemas.
4. **Branchy business logic.** Calculations on the coarser table are
   full of `if product_type == X then … else if … else …` branches,
   even when the per-subtype rule would be a single straight-line
   expression. The flat structure forces every rule to handle every
   subtype, even the ones it does not care about.

## Motivating example: FR 2052a

The Federal Reserve's [FR 2052a][fr2052a] liquidity reporting form is
a clean public example. It defines roughly **13 tables** (Inflows,
Outflows, Supplemental, etc.), each of which is itself a
hierarchical dataset. A single table mixes many product types — and
sometimes sub-products one level below that, and occasionally a
third level. The instructions document applicability column by
column: which fields are required, optional, or not applicable for
each (sub)product code. That applicability matrix is exactly the
information the schema cannot currently express in a way tools can
act on.

## What we want

We want a way to describe these hierarchies so that:

- Every **node in the hierarchy** is a first-class dataset
  definition with its own honest schema.
- Coarser nodes are **derived** from finer ones (or finer from
  coarser — see the direction-flexibility note below), not authored
  independently. Movement between levels is mechanical.
- The derivation is **invertible**. Given a row at one level and
  knowledge of its position in the hierarchy, the system can project
  to any other level *without losing applicability information*. A
  field that is optional at the parent but required at the child is
  required after projection.
- **Business logic** can be authored at whichever level is natural
  for the rule, and the language handles the lift/lower across
  levels — removing the forced branching at coarser levels.

## Resolved decisions

These were open questions in the previous draft and are now settled
in principle (details still to spec).

### Specialization relationship — extend Choice to a hierarchy

We extend the existing [Choice](../concepts/choice.md) concept from a
flat closed set of variants to a **hierarchy of variants**. A choice
node may itself have child variants, recursively. A hierarchical
dataset is then a dataset whose discriminator is a hierarchical
choice, with each node in the choice carrying the additional
attributes that apply at and below it.

This subsumes what we previously called a "product hierarchy" while
avoiding the domain-specific wording. *Product* reads as
finance/commerce; the construct is general — it applies to any
domain with a taxonomy of related entity types. We will use
**hierarchical choice** in the spec text. (Other candidates we
considered and rejected: *taxonomy* — overloaded with classification
systems; *category hierarchy* — clashes with category theory;
*entity hierarchy* — too vague.)

### Optionality gains a third state: *not applicable*

We add **not applicable** as a third state alongside required and
optional. It fits cleanly under the multiplicity reading of
[optionality](../concepts/optionality.md):

| State           | Multiplicity | Meaning                              |
| --------------- | ------------ | ------------------------------------ |
| Required        | 1..1         | exactly one value, must be present   |
| Optional        | 0..1         | zero or one value, presence allowed  |
| Not applicable  | 0..0         | zero values, presence is a violation |

So *not applicable* is the natural lower bound of the same
multiplicity dimension that already distinguishes required from
optional, not a separate concept bolted on. *Not applicable* is
declared **per node** of the hierarchy: an attribute may be required
at one branch, optional at another, and not applicable at a third.

This is the case that flat schemas cannot express today, and it is
the case that drives invertibility of projection.

### Direction is flexible: declare top-down, bottom-up, or mixed

We do not force authors to declare attributes only as additions on
the way down (specialization) or only as a union of leaves rolled up
(generalization). Both directions are allowed for the same
hierarchy, and **for the same attribute**, as long as the result is
semantically consistent.

Concretely:

- An author may declare an attribute on a parent node and let
  children inherit it (top-down).
- An author may declare an attribute on multiple sibling leaves and
  let it surface on the parent as the union (bottom-up).
- An author may do both for the same attribute, as long as the two
  declarations agree on type, optionality, and applicability at
  every node.

When declarations agree, both forms are accepted. When they
disagree, that is an error. When they agree but are **redundant**
(the same fact stated twice), the language should emit a *warning*
or a clean-up suggestion — not an error — because the redundancy is
harmless and may even be intentional during a refactor.

## Still open

### Generalization (finer → coarser)

The lift to a coarser view should be derivable from the hierarchy:

- Column set = union of columns across descendants (with parent
  declarations taking precedence where names collide — exact
  collision rules TBD).
- Optionality = relaxed where descendants disagree, with
  per-descendant applicability preserved as metadata (so projection
  back is lossless).
- Discriminator = synthesized from the hierarchical choice tag.

### Specialization (coarser → finer)

Projection to a more specific node is the inverse:

- Filter rows by discriminator (any node in the hierarchy, not just
  leaves).
- Drop columns that are *not applicable* at the target node.
- Restore the target node's declared optionality on the remaining
  columns.

The round-trip across any two levels in the hierarchy should be the
identity (modulo row order and column order).

### Authoring business logic

We want two complementary affordances:

- **Per-node rules** that read like the case at that node: no
  branching on discriminator, just the calculation for that node.
  The framework dispatches by the hierarchical choice.
- **Higher-level rules** that operate at a coarser node and only see
  the columns shared at that level, with no obligation to enumerate
  descendants.

The interesting case is a higher-level calculation whose inputs
depend on lower-level attributes. It probably looks like a
higher-level rule that delegates *one* of its inputs to a per-node
rule, which is very different from a giant `case` over the whole
discriminator.

### Relationship to existing concepts

- [Dataset](dataset.md) — the base construct being extended.
- [Choice](../concepts/choice.md) — to be extended from flat to
  hierarchical.
- [Optionality](../concepts/optionality.md) — to be extended with
  the *not applicable* (0..0) state.
- [Record](../concepts/record.md) — record extension semantics may
  carry over for inherited attributes.

We resist introducing new constructs where these existing ones
extend cleanly.

## Related pattern: hierarchical star schemas

A separate but adjacent pattern, worth its own document later: a
**fact table that mixes entity types** with a set of dimension
tables that are each only meaningful for some of the rows. Strictly,
this is a union of per-type star schemas sharing the central fact
table. Modeling it the same way as the hierarchical dataset above —
finer-grained stars unioned into a coarser star, with applicability
of each dimension declared per node — would let analytical tools
both serve the cross-type query and recover the per-type star
without ambiguity.

This document does not yet specify that pattern; it is flagged so we
remember to come back to it.

## Next steps

1. Pick a target syntax sketch for declaring a hierarchical choice
   and the per-node attribute applicability, and run it through the
   FR 2052a tables as a stress test — in particular the tables that
   have a third level of sub-product.
2. Pin down the semantics of the *not applicable* (0..0) state in
   [optionality](../concepts/optionality.md) and how it composes
   across hierarchy levels.
3. Specify the projection semantics in both directions and prove
   (informally, with examples) that the round-trip is
   information-preserving across arbitrary levels.
4. Specify the rule for resolving top-down and bottom-up
   declarations of the same attribute: when do they agree, when do
   they conflict, when is the redundancy worth a warning.
5. Sketch the authoring model for per-node and higher-level rules
   and show, on a worked example, that the branchy-logic problem
   disappears.

[fr2052a]: https://www.federalreserve.gov/apps/reportingforms/Report/Index/FR_2052a
