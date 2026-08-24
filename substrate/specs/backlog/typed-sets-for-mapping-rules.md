# Typed Sets for Mapping Rules (and Pseudo-Variables)

Design note. Not yet a normative spec — captures the approach we
settled on while sketching the LCR appendix VI encoding, and informs
B4b (TS codegen) in [authoring-workflow.md](../authoring-workflow.md).

## Problem

Regulatory text like the LCR rule contains two things that look
program-shaped but resist the obvious encodings:

1. **Mapping rules.** Tables that say "a record from the FR 2052a
   report counts as *Stable Retail Deposit §.32(a)(1)* if its PID is
   `O.D.1` or `O.D.2`, its counterparty is Retail or Small Business,
   and it is FDIC-insured." Appendix VI has ~60 of these.
2. **Pseudo-variables.** Names like *Outflow values* that appear
   inside formulas but are never explicitly defined. Their meaning is
   "sum, over every record that falls under any of these mapping
   rules, of `Maturity Amount × runoff rate for the rule`."

An earlier sketch introduced **roles** (parameterised aggregation
slots) and **bindings** (rules that contribute records to a role) as
two new top-level IR concepts. That was rejected: it adds machinery
the domain doesn't ask for, and these things are not actually
special.

## The approach

Lean on what's already in the language. From
[`specs/language/concepts/datatype.md`](../language/concepts/datatype.md):

> A type describes a **set of values** and the operations that apply
> to them. … For open sets the **membership rule** is stated instead.

So:

- **Each mapping rule is a datatype** that refines a base type
  (e.g. `Fr2052aRecord`) by a membership predicate, with
  [attributes](../language/concepts/attribute.md) carrying
  rule-specific metadata (runoff rate, section reference, etc.).
- **Group headings ("OUTFLOW VALUES")** are datatypes built by
  **union** of their member rule-types.
- **Cross-cutting names like "Level 1 HQLA"** are datatypes built by
  **intersection / further refinement** of broader datatypes.
- **Pseudo-variables like "Outflow values"** are ordinary named
  formulas whose body aggregates over one of those typed sets. No
  new concept; the aggregator (`Σ`, `max`, …) is an operation on
  collections, which the language already needs.

This collapses *roles* and *bindings* back into **datatype** and
**formula** — concepts we already have.

## IR sketch (fragment)

```jsonc
// VI-lcr-mapping.substrate.json
{
  "datatypes": [
    { "id": "Fr2052aRecord", "import": "../fields/fr2052a-record" },

    // each numbered mapping row is a refinement with attributes
    { "id": "StableRetailDeposit_32a1", "srcId": "section-10",
      "refines": "Fr2052aRecord",
      "where": {
        "and": [
          { "eq": ["reportingEntity", "LCR Firm"] },
          { "in": ["pid", ["O.D.1", "O.D.2"]] },
          { "in": ["counterparty", ["Retail", "Small Business"]] },
          { "eq": ["insured", "FDIC"] }
        ]
      },
      "attributes": { "runoffRate": 0.03, "section": "32(a)(1)" } },

    // grouping = union
    { "id": "AllOutflows", "srcId": "section-OUTFLOW_VALUES",
      "union": ["StableRetailDeposit_32a1", "OtherRetailDeposit_32a2"] },

    // intersection / further refinement
    { "id": "Level1Hqla", "refines": "Fr2052aRecord",
      "where": { "in": ["collateralClass", "$level1Codes"] } }
  ],

  "inputs": [
    { "id": "records", "type": "Set<Fr2052aRecord>" },
    { "id": "outflowAdjustmentPercentage", "type": "number" }
  ],

  "formulas": [
    { "id": "outflowValues", "srcId": "...",
      "body": { "sumOver": "AllOutflows ∩ records",
                "of": { "mul": ["x.maturityAmount", "x.attr.runoffRate"] } } },

    { "id": "totalNetCashOutflows", "srcId": "...",
      "body": { /* ordinary arithmetic over the variables above */ } }
  ]
}
```

## Generated TypeScript (target shape)

```ts
import { Fr2052aRecord, refine, union, sumOver } from "@substrate/runtime";

export const StableRetailDeposit_32a1 = refine<Fr2052aRecord>("§.32(a)(1)", {
  predicate: r =>
       r.reportingEntity === "LCR Firm"
    && (["O.D.1", "O.D.2"] as const).includes(r.pid)
    && ["Retail", "Small Business"].includes(r.counterparty)
    && r.insured === "FDIC",
  attributes: { runoffRate: 0.03, section: "32(a)(1)" as const },
});

export const AllOutflows = union("AllOutflows",
  StableRetailDeposit_32a1, OtherRetailDeposit_32a2 /* , ... */);

export const Level1Hqla = refine<Fr2052aRecord>("Level 1 HQLA", {
  predicate: r => level1Codes.includes(r.collateralClass),
});

export class LcrMapping {
  constructor(readonly inputs: {
    records: ReadonlyArray<Fr2052aRecord>;
    outflowAdjustmentPercentage: number;
    level1HqlaAdjustedValues: number;   // explicit input
    level1HqlaHaircutValues:  number;
    // ...
  }) {}

  /** "Outflow values" */
  get outflowValues(): number {
    return sumOver(AllOutflows, this.inputs.records,
                   (r, attr) => r.maturityAmount * attr.runoffRate);
  }

  /** "Total Net Cash Outflows" */
  get totalNetCashOutflows(): number {
    return this.inputs.outflowAdjustmentPercentage *
      (this.outflowValues - Math.min(this.inflowValues, 0.75 * this.outflowValues)
       + this.maturityMismatchAddOn);
  }
}
```

What `tsc` catches because the helpers carry type information:

- typos in `predicate` lambdas against the base record's fields;
- typos in `attributes` lookups inside `sumOver` lambdas;
- `union(...)` members with mismatched base types;
- missing inputs referenced by formulas.

Parameterised slices ("outflow values for §.32(g) … with maturity
bucket of n") need no new IR concept — they are on-the-fly
refinements of `AllOutflows` plus a filter over `records`:

```ts
sumOver(
  AllOutflows.where(attr => sliceSections.includes(attr.section)),
  this.inputs.records.filter(r => r.maturityBucket === n),
  (r, attr) => r.maturityAmount * attr.runoffRate);
```

## What this collapses in the building blocks

- B4b's codegen registry covers just **datatype** (with refinement,
  union, attributes) and **formula** (with aggregator operators).
  No "role" or "binding" emitters.
- B6 visualisation: mapping table → predicate of a typed set;
  group heading → union; pseudo-variable → formula with a sum-over
  node. One renderer per concept, no separate role/binding renderers.

## Open questions

These are the next things to grill before this becomes a normative
spec.

1. **Overlapping membership.** What happens when a record satisfies
   the predicates of two members of a union? LCR mapping rules are
   designed not to overlap, but the system needs a defined answer:
   error, first-wins, or contribute-to-both?
2. **Attribute model.** Do refinement-type attributes reuse the
   existing [Attribute](../language/concepts/attribute.md) concept
   wholesale, or do they need their own shape? Initial read says
   reuse, but worth confirming when drafting the refinement spec.
3. **Cross-file datatype references.** Refinements reference a base
   type (often defined in another markdown file). Do they always
   import explicitly per sidecar, or does the codegen consult a
   package-wide type registry? Lean: explicit per-sidecar imports —
   each file stays self-describing.

## Status

Not yet promoted to `specs/language/`. Lives here in `backlog/`
until:

- the three open questions above are answered,
- the existing `datatype.md` is extended (or a sibling
  `refinement-type.md` added) to make the membership predicate and
  set operations first-class, and
- the first vertical slice from
  [authoring-workflow.md](../authoring-workflow.md) actually exercises
  the encoding end to end on an LCR file.
