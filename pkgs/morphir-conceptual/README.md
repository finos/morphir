# Conceptual model and intent links

[`finos/morphir-conceptual/model`](model/README.md) preserves the complete M1/M2
rich graph, exposes record views and inspects exact references and independent
gaps. The engine data adapter carries it through existing Ion text/binary codecs
as unit-owned IRUnit metadata.

## Constructed intent links

`finos/morphir-conceptual/intent` inspects constructed source, requirement, claim and
evidence records. It adapts caller-supplied KB excerpts and projects a read-only PRD.
Every operation is pure. The library performs no acquisition, lifecycle transition,
expression evaluation or proof inference.

The input semantics come from
[M1's exact conceptual draft](https://github.com/finos/morphir/blob/9fe3a6f5cf05e8fe6862b2883db05ca9ed7d1551/spec/conceptual/model/contract.html),
`morphir-conceptual/0.1.0-draft.1`. This package implements an **inspection slice**,
not the full M1 graph decoder or carrier. Constructed `Contract`, `Declaration`,
`Scenario` and `Implementation` values expose the links needed here; they do not
replace the complete M1 records. Callers retain the original model and its other
fields. `Scenario` content, notation, scope, descriptive values and observation
data use the existing `moonrockz/ion` value type.

| Operation | Result |
| --- | --- |
| `adapt_kb_source(KbSnapshot)` | Caller-identified Source and intent, exact excerpt and KB origin. May reject colliding source/entity IDs. |
| `inspect(Model)` | Identified structural errors and independent formalization, example, binding and evidence gaps. |
| `prd_view(Model)` | Identified requirements in authored order, categories, exact text, notation, source refs and links. Invalid graphs retain rows and diagnostics but expose no usable assertion links. |
| `assess_claim(Model, ResolvedRef, RevisionContext)` | Each support/contradiction assertion with its original observation and `Current`, `Stale` or `Inconclusive` currency. No evidence yields `Unknown`; invalid graph/query yields `InvalidClaim`. |

`Id`, `Revision` and `Category` have validating `parse` constructors. IDs and
revisions are opaque nonempty strings and are never normalized. Categories must
have a namespace. Functional, data, performance, operational and regulatory use
M1's `morphir:requirement-kind/` prefix. EARS classification belongs in notation.

`RevisionContext::new(model, entities~, sources~, implementations~)` rejects
duplicate IDs in each list and copies the lists. Its accessors return copies.
Matching uses complete sets of exact revisions, ignoring order. Required context
includes both the claim's and observation's declared dependencies and the sources,
entities and artifacts reachable through explicit links. Supplied snapshots of
declared dependencies are checked even without a graph link. Exact references
select their snapshots; conflicting unlinked candidates are inconclusive.
Observation source refs and run clauses add their own requirements. A run clause
must resolve uniquely within the evidence owner's supplied closure; its source
references, declaration and implementation binding contribute dependencies too.
Missing or ambiguous clause ownership is inconclusive. Missing
context is inconclusive; a revision or subject-set
change is stale. Supplied source snapshots are checked too, so two matching old
contexts cannot conceal an edited source. A source context uses the **document
ID**, not the local Source record ID. Contradictions never replace support.

KB origin records retain the bundle, short number, slug and optional existing
state. The six states are Backlog, Refinement, InProgress, Released, Cancelled and
Superseded. The KB service owns their meaning and transitions. Its short number
is scoped to a bundle, and its JSON view provides no document revision. Callers
must supply stable source/document/entity identities and an exact revision. Moving
a path changes the locator; editing source creates a new snapshot. Neither a
Released intent nor accepted review creates formalization or run evidence.

Explicit dependency snapshots are supplied in `Model.dependencies`. References
select exact model/entity revisions. Duplicate dependency snapshots, including
cycles, are invalid. A missing declared resolved target is invalid; an authored
unresolved target remains a visible gap. No locator triggers a fetch.
PRD example links include dependency-owned scenarios. Each relationship is
validated in its owning model before its exact endpoints are projected.
Inspection includes support and contradiction assertions from the entire supplied
closure, including assertions about dependency-owned claims. Each returned
`EvidenceAssessment` retains `relationship_model: Snapshot` alongside the local
`relationship: Id`, so assertions with equal IDs in different model revisions
remain distinguishable.
Structural dependency discovery and formalization/example gap checks also use
the entire supplied closure. An ancestor may assert links about a dependency's
entities; each link remains validated in its asserting model, and each source
reference resolves in its owner's model. The claim's own model revision remains
the context anchor.

The package does not validate full contract binder/signature rules, interpret
opaque scenario content, verify source digests, decode graph profiles, admit
capabilities, or provide general contradiction detection. Its source slice uses
document revisions; verified digest admission remains a separate source adapter.
`Current` describes recorded currency only, including for an accepted review, a
type analysis or a run with no observed output.

The [shared examples](https://github.com/finos/morphir/tree/main/spec/conceptual/intent)
contain independently authored inputs and literal expected observations. Their
guide maps each case to public-API tests here. They add no compatibility runner.

## Bounded typed-value admission

[`finos/morphir-conceptual/validation/admission`](validation/admission/README.md)
checks candidate typed values against declared records, custom types,
generics, arbitrary tuples, collections and untagged unions under the
`morphir-contracts/0.1.0-draft.1` fixture profile. Refinements and opacity
are respected, budgets never pass an exhausted check, and unsupported types
or ambiguous union membership are reported instead of guessed.

Run the focused suite from the repository root:

```bash
moon test -p finos/morphir-conceptual/intent --target wasm
moon test -p finos/morphir-conceptual/intent --target wasm-gc
moon test -p finos/morphir-conceptual/intent --target js
moon test -p finos/morphir-conceptual/intent --target native
```
