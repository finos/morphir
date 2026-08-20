# Catalog & Catalog Type

> **Status:** backlog / design sketch. Companion to
> [`hierarchical-dataset.md`](./hierarchical-dataset.md). Worked out
> against the FR 2052a / LCR example under
> `examples/fr2052a-lcr/structured/output/`.

## Core concepts

- **Catalog** — runtime: a type *plus* its population of identified
  instances. Roughly analogous to a NoSQL collection or a SQL
  table-with-data. Each row has its own identity.
- **Catalog type** — static: the shape (fields + constraints) of the
  rows in a catalog. Comes from the *domain model*, not the generic
  data-type universe.
- **Catalog hierarchy** — catalog types form a tree. Internal nodes
  group descendants; leaves carry the actual record shape.

For FR 2052a the hierarchy is three levels deep:

```
FR2052aRecord                       ← root
├── Inflows                         ← section
│   ├── I.A                         ← table
│   │   ├── I.A.1  (fields: …)     ← leaf / product
│   │   ├── I.A.2  (fields: …)
│   │   └── …
│   ├── I.O, I.S, I.U
├── Outflows  → O.D, O.O, O.S, O.W
└── Supplemental → S.B, S.DC, S.FX, S.I, S.L
```

13 tables, ~100 products, one root.

## Type structure at internal nodes

An internal node is **semantically a union of its descendant leaves.**
That gives two derived rules:

1. **Field membership at a union node** is computed structurally:
   - **Mandatory** iff the field is present in *every* member.
   - **Optional** iff present in *some but not all* members.
   - **Absent** iff present in no members.

2. The hierarchy node itself is the natural **discriminant** for tagged
   dispatch (e.g. the PID — `I.S.4` — tells you which leaf a row
   inhabits).

Important: "optional because the schema doesn't define it on this
member" must stay distinct from "optional because the value can be
null." Two different absence semantics; the spec needs to pin this down
(see open questions).

## Selecting sub-catalogs (catalog-type expressions)

A rule rarely operates on a whole top-level catalog. It picks a subset
of the hierarchy:

- A single leaf:                      `I.S.4`
- A sibling-set under one parent:     `I.S.{1, 2, 3, 5, 6}`
- A wildcard minus exceptions:        `I.S.* \ {4}`
- (Hypothetical) cross-parent union:  `I.A.1 | S.B.{3, 4}`

The result is itself a catalog type (a union), with field membership
computed by the rule above. In TypeScript this is `Extract<…>`; in
substrate it wants a first-class **catalog-type selector syntax** that
tracks the regulator's own way of citing PIDs.

## Rules as partial functions over catalog-type unions

The unifying construct is:

```
rule : SelectedCatalogType ⇀ Result
rule row
  | guard₁(row), guard₂(row), …
  = expr(row)
```

Two things this does at once:

- **Filter** (runtime): only rows satisfying every guard contribute.
  Rows outside the selected catalog type don't even reach the function
  — the type system has already excluded them.
- **Refinement** (static): each guard narrows the row's type inside the
  body. After `row.collateralClass ∈ HQLA`, the field has the narrower
  `HQLAClass` type; downstream Level-1/2A/2B dispatch needs no second
  runtime check.

This is the central typing innovation: a guard is both a value-level
predicate and a type-level refinement. The substrate spec needs to
define exactly which guard *forms* are admitted as refinements
(membership in a finite enum is the obvious safe one; arbitrary boolean
expressions are not).

## Two-tier architecture for cross-catalog computations

Empirical finding from FR 2052a Appendix VI: across ~150 rule
templates, **no template's domain spans more than one table.** When a
regulatory concept needs to draw from multiple tables, §VI splits it
into *sibling templates* (same title, different table) and combines
their outputs in the formula layer (§IV).

Concrete example: templates **(105)** and **(106)** are both titled
"Retail Cash Inflow Amount (§.33(c))" but target `I.U.{5,6}` and
`I.S.{1,2,5,6,7,8}` respectively. They must be separate templates
because the field constraints diverge (`Counterparty = "Retail or
Small Business"` is meaningful on I.U; `Sub-Product` and
`Collateral Class` constraints belong to I.S).

This factors cleanly into a two-tier construct:

| Tier         | Operates on                                   | Type signature                       |
|--------------|-----------------------------------------------|--------------------------------------|
| **Template** | A sub-catalog-type (single-table union)       | `CatalogType ⇀ Money` (per row)      |
| **Calc**     | Money-valued outputs of one or more templates | `Money × Money × … → Money`          |

A template is partial-function-over-catalog-type, as above. A calc is
plain arithmetic — no catalog-type complexity at the value level. The
thorny "union spans heterogeneous tables" case the type system might
theoretically need to support **doesn't occur** in real regulatory
specs. The regulator already factored it out.

This is a meaningful constraint for substrate: keep the catalog-type
union machinery *within a single root-to-leaf hierarchy branch*, and
let cross-branch composition live entirely at the value/arithmetic
layer. That keeps the type system tractable.

## How this maps to LCR specifically

| LCR concept                                                       | Substrate construct                                                       |
|-------------------------------------------------------------------|---------------------------------------------------------------------------|
| The 13 FR 2052a tables                                            | Internal nodes (depth 2) in one catalog type hierarchy                    |
| Individual PIDs (products)                                        | Leaf catalog types                                                        |
| Appendix VI rule template                                         | Template = partial function over a sub-catalog-type                       |
| Appendix IV LCR formula                                           | Calc = arithmetic over template outputs                                   |
| Field-value constraints (`*`, `#`, `NULL`, specific value)        | Guards in the template's partial-function clause                          |
| HQLA Level 1/2A/2B partitioning                                   | Refinement-typed dispatch on `Collateral Class` after an `∈ HQLA` guard   |
| Appendix III asset-category codes                                 | Enum hierarchy *inside* a field's type (independent of catalog hierarchy) |
| Multi-table regulatory concept (e.g. "Retail Cash Inflow" §.33(c))| Multiple sibling templates feeding one calc                               |

## Open questions

1. **Tagging.** Is the catalog-hierarchy node ID (PID) the discriminant
   value carried on every row? Probably yes, but say so.
2. **Field-absence semantics.** Schema-absent vs. value-null —
   distinct or unified?
3. **Admissible guard forms.** Which predicates produce type-refinement
   vs. just runtime filtering? Finite-enum membership is the obvious
   safe one; arbitrary boolean expressions are not.
4. **Selector syntax.** How to write `I.S.{1,2,3,5,6}` and
   `I.S.* \ {4}` first-class.
5. **Catalog vs. catalog-type relationship.** A catalog has *one*
   catalog type as its schema, but a rule's input catalog-type is
   usually a *union* selected from one root catalog's hierarchy. Worth
   spelling out that selection produces a catalog *type*, not a catalog
   (you'd then filter the catalog by that type to get a sub-catalog at
   runtime).
6. **Identity.** Is the row identity (a) carried by a designated field,
   (b) implicit and assigned by the catalog, or (c) structural (the row
   itself)? §VI rules don't reference identity, but downstream lineage
   and audit will.
