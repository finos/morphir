# Workflow: Business User Authors a Full Solution

> Status: **Draft** — exploratory design. Captures a target end-to-end
> workflow for a business user building a complete data-processing
> solution in substrate, with an AI agent as collaborator. This is more
> concrete than [vision.md](../vision.md) and is intended as a working
> document while the supporting features (notably **data binding**) are
> fleshed out.

## 1. Premise

A business user — not a developer — wants to build a complete solution
to a business problem: source some datasets, join them, filter, aggregate,
run domain calculations (e.g. netting or other financial logic), and
produce a single result dataset. They want to do this by *describing*
what they want, validating it against real data, and ending up with a
shareable specification that downstream IT can bind to production.

The workflow assumes substrate already contains:

- **Documented data sources** — abstract dataset definitions in the
  knowledge base, with schemas, semantics, and provenance, but not
  necessarily bound to any concrete physical system yet.
- **Domain concepts and operations** — the vocabulary the user's
  problem will be expressed in.

What the user contributes is the *intent*; what the agent contributes is
the *construction* and the *evidence*.

## 2. The Workflow

The workflow has five phases. Phases 3 and 4 iterate.

### Phase 1 — Intent capture

The user opens a chat with the substrate AI agent and describes, in
natural language, what they want to build. Example:

> "I need to take our trades dataset, join it to the reference data for
> counterparties, filter to EMEA, net the exposures by counterparty,
> and give me one row per counterparty with the net exposure."

The agent does not yet do anything irreversible. It clarifies scope,
identifies which documented datasets and operations are in play, and
confirms its understanding back to the user before construction.

### Phase 2 — Solution construction

The agent searches the knowledge base for the relevant data sources and
domain operations, then assembles a candidate solution as substrate
artifacts: dataset derivations, joins, filters, aggregations, and any
calculation steps (decision tables, choice trees, formulas) needed for
the domain logic.

At this stage the solution is **abstract** — it references documented
datasets and operations, but has not been executed against any real
data.

### Phase 3 — Grounding via data binding

This is where we rely on a feature that does not yet exist in substrate
and is the main capability this workflow demands:

> **Data binding** lets a user (or IT) attach a concrete, executable
> dataset — a database table, file, query, API — behind an abstract
> dataset definition. The abstract definition is the contract; the
> binding is one realization of that contract in a particular
> environment.

Bindings are **environment-scoped**. A given abstract dataset can have
a "production" binding (the real warehouse table), a "test" binding
(the masked example data — see Phase 5), a "dev" binding, etc. The
specification itself never names a physical system; the binding does.

With production bindings in place, the agent runs the candidate
solution against real production data — under whatever access controls
the environment enforces — to ground the abstract solution in real
behavior.

### Phase 4 — Scenario generation and review (the iterative loop)

The agent does not just hand back "here's the result." It enumerates
the **edge cases** implied by the solution's logic and finds a
representative real-data example for each one. Edge cases come from:

- branches in any decision trees or decision tables,
- join outcomes (matched, missing reference data on either side, many-to-one fan-out, etc.),
- aggregation boundary conditions (empty groups, single-row groups, nulls),
- domain-calculation branches (e.g. different netting paths — same currency, cross-currency, zero net, sign flips).

For each edge case the agent presents a **BDD-style scenario**:

```
Scenario: Trade with counterparty missing from reference data
  Given <input rows from real data>
  When  the solution runs
  Then  the expected output is <observed output>
```

The user reviews each scenario and either:

- **Accepts** the expected output as the intended behavior, locking it
  in as a regression example, or
- **Rejects / refines** — clarifies the requirements, after which the
  agent revises the solution and re-runs the loop.

The loop terminates when every generated scenario is accepted.

### Phase 5 — Finalization and masking

The accepted scenarios were drawn from production data and may contain
sensitive information (PII, position sizes, counterparty identities,
etc.), so they cannot be checked into a shared specification as-is.

A finalization step **masks** the production-derived examples — replacing
sensitive values with synthetic-but-shape-preserving substitutes — while
keeping the structure, the edge-case coverage, and the
input/output relationships intact.

The masked scenarios are then saved into the knowledge base alongside
the solution, in markdown (for readability) or CSV (for tabular
fixtures). At this point the solution is a fully self-contained
substrate specification: prose + structure + worked examples.

The masked example data is itself just another binding of the abstract
datasets — a "test" or "specification" environment binding, conceptually
no different from the production binding except that the data is
synthetic. The same solution can therefore run against either. The only 
difference is that in the test environment output datasets serve as
expectations while in other bindings those are actual results.

## 3. Roles and Responsibilities

| Actor | Contributes |
|-------|-------------|
| Business user | Intent, acceptance of scenarios, refinement of requirements |
| AI agent | Solution construction, edge-case enumeration, scenario generation, masking |
| IT / data owners | Production data bindings, access controls, masking policies |
| Substrate tooling | Verification that the specification is internally consistent and that examples reproduce |

## 4. Artifacts Produced

By the end of the workflow, the knowledge base contains:

1. The **solution specification** — the abstract pipeline of dataset
   operations, expressed in substrate's normal vocabulary.
2. **Masked BDD scenarios** — accepted edge cases with input/output
   examples, in markdown or CSV.
3. **Bindings** — at minimum the test/specification binding (masked
   data); production bindings are managed separately by IT but are
   structurally the same kind of object.

All three are version-controlled markdown/CSV artifacts.

## 5. Open Questions

These need resolution before the workflow can be implemented end-to-end.

- **Data binding spec.** How are bindings declared, scoped, and
  resolved? What is the contract between an abstract dataset and a
  binding? See: needs a dedicated spec under `specs/language/` or
  `specs/tools/`.
- **Edge-case enumeration.** What is the agent's algorithm for deciding
  which branches and join conditions warrant a scenario? Should this be
  driven from substrate's own structural information (decision tables,
  choice nodes) so it is reproducible rather than ad-hoc?
  - **Answer** Yes, there should be dedicated tooling that can process
    the substrate structures and programatically derive the different 
    edge cases that need to be covered. This will be largely based on 
    some additional sections in the language spec documents specifically 
    about edge cases for a given operation or data type. Once the edge
    case definitions are returned by the tooling the agent will try to 
    find examples in the bound datasets or report that there are no examples.
    Finding the examples will be done through a standardised API that 
    allows the agent to query any dataset.
- **Scenario format.** Is there a single canonical BDD scenario format
  in substrate, or do we let scenarios live as freeform markdown with
  link-typed references to the solution under test?
  - **Answer** There should be a well-defined structure for scenarios 
    just like any of the existing substrate concepts.
- **Masking policy.** Where do masking rules live — per-dataset, per-attribute,
  per-environment? How do we make masking auditable so reviewers can
  confirm no sensitive data leaked through?
  - **Answer** It should generally be per attribute but I can imagine 
    dataset specific tweaks as well. The masking algorithm itself should
    be documented and audited before they are used, and the actual masked
    data should be audited by the business user before they get stored 
    in the test data.
- **Acceptance provenance.** When a user accepts an expected output,
  that acceptance is itself a fact worth recording (who, when, against
  which version of the solution and which binding). How do we represent
  it?
  - **Answer** Let's record that in the test binding itself which should 
    also be a markdwon document. It should be similar to how changes of 
    standards are being tracked today as part of the documentation itself.
- **Re-grounding on change.** When the solution or upstream data
  changes, which accepted scenarios are invalidated and need
  re-review? This is essentially regression testing for
  specifications.

## 6. Relationship to Existing Concepts

- [dataset.md](../language/dataflow/dataset.md) — the abstract dataset
  definitions this workflow operates over.
- [decision-table.md](../language/concepts/decision-table.md) and
  [choice.md](../language/concepts/choice.md) — primary structural
  sources of edge cases for scenario generation.
- [vision.md](../vision.md) — the broader framing; this workflow is one
  concrete realization of "verifiable knowledge."
