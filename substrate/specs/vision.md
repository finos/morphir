# Vision Document: An LLM-Native Executable Specification Language

## 1. Executive Summary

This project envisions a new kind of programming language: an
**LLM-native executable specification language** designed for
spec-driven development.

The language is:

- Generated and refined by LLMs
- Structurally analyzable and verifiable
- Debuggable by humans --- including non-technical stakeholders
- Explicitly designed around traceability and dataflow semantics

It is not merely a programming language, but a **formal substrate for
building verifiable systems from natural-language specifications**.

---

## 2. Core Design Principles

### 2.1 Semantics Over Syntax

The language prioritizes meaning over form. Structure emerges from semantic
intent --- what something means matters more than how it is written. There is
no rigid grammar or formal syntax; the canonical representation is markdown
enriched with natural language.

The language uses native markdown syntax wherever possible. Extended syntax
is permitted only when it is broadly supported by major rendering tools,
with GitHub-flavored Markdown as the primary compatibility target. This
keeps the specification approachable: any contributor --- human or
machine --- can read, edit, and render it with standard tooling.

Alternative intermediate formats are permitted when markdown alone is
insufficient for precision or conciseness. They may appear as code blocks
embedded in a module or as separate artifact files. In either case, every
alternative-format fragment must carry a provenance reference identifying the
specification section or operation it belongs to.

### 2.2 Spec-First, Not Code-First

The primary artifact is the _executable specification_.\
Implementation emerges from structured specification --- not the other
way around.

### 2.3 LLM-Native by Design

The language must support:

- Natural language → structured semantics extraction
- Structured semantics → natural language regeneration
- Partial subtree regeneration
- Semantic (structure-aware) diffing
- Deterministic regeneration under refinement

Markdown is the primary representation. Alternative formats may be embedded
as code blocks or referenced as separate artifacts, always with provenance
back to the originating specification fragment.

### 2.4 Structured + Human-Readable Hybrid

Natural language is preserved where appropriate, but embedded inside a
structured substrate that enables:

- Semantic validation
- Consistency checking
- Dependency validation
- Tooling support

The markdown documents serve as an all-encompassing semantic context for
human and machine contributors. Links are the primary enrichment
mechanism: they associate types, operations, and provenance with terms and
structures that would otherwise be plain text. All available markdown
features --- headings, tables, lists, links, footnotes --- are used to
carry semantic information within the document.

The markdown format is intentionally permissive. Structure is defined by
relative heading depth (e.g., a test cases section must appear under its
operation's heading) rather than by absolute heading levels. Additional
grouping sections are allowed between any structural elements.

---

## 3. Semantic Model

### 3.1 Executable Specification Graph

The program is a **typed dataflow graph** where:

- Nodes represent transformations or decisions
- Edges represent explicit data contracts
- Inputs and outputs are first-class
- Execution order is derived from data dependencies

Timing dependencies are not primary --- dataflow is.

### 3.2 Markdown as Source of Truth

The markdown specification is the canonical artifact:

- It is the primary human-readable and LLM-readable form
- It enables structural validation via relative heading relationships
- It supports automated tooling without prescribing rigid formatting
- It carries provenance metadata linking logic back to natural language

Alternative formats (embedded code blocks or separate files) are projections
of the markdown source and must maintain bidirectional traceability. Structured
representations such as YAML may be derived from the markdown, but they are
not the source of truth.

### 3.3 Source-Map-Like Provenance

Every structured node may carry metadata linking back to:

- Original natural language fragments
- Specification paragraphs
- Semantic anchors

This enables:

- Auditable traceability
- Explainable rule behavior
- Regeneration without losing intent mapping

---

## 4. Verification Model

### 4.1 Static Verification

The system should support:

- Structural validation
- Schema consistency
- Type compatibility
- Dependency completeness
- Detection of unreachable or orphan nodes

### 4.2 Dynamic Verification

At runtime, the system supports:

- Example-driven testing (BDD-style)
- Property validation
- Data contract enforcement
- Invariant checking

Verification is layered and granular --- not monolithic.

---

## 5. Human Debuggability

The language must be understandable beyond engineering teams.

This requires:

- Clear rule identifiers
- Plain-language descriptions bound to logic
- Visualizable execution graphs
- Deterministic execution traces
- Error messages that reference specification fragments

Failures must be explainable in business terms, not just technical stack
traces.

---

## 6. Productionization Path

The language should enable transformation from:

Exploratory code → Structured spec → Verified executable → Language projection → Production system

This includes:

- Extraction of inputs/outputs
- Formalization of transformations
- Embedding of example datasets
- Automatic generation of validation tests
- Documentation derived from the spec itself
- Derivation of target-language implementations via AI agents

The executable specification becomes the single source of truth across
environments.

---

## 7. Architectural Characteristics

The envisioned language is:

- Semantics-first
- Declarative
- Dataflow-oriented
- Metadata-rich
- Deterministic
- Extensible via embedded DSLs
- Projection-friendly
- Designed for LLM collaboration

It unifies documentation, testing, orchestration, and execution into a
single semantic substrate.

---

## 8. Long-Term Ambition

To establish a new paradigm:

> Systems are built from structured, verifiable specifications that are
> co-developed with LLMs and remain explainable to humans.

The executable specification becomes:

- The documentation
- The contract
- The test harness
- The runtime blueprint
- The source for automatic derivation of target-language implementations

All in one artifact.

---

## 9. Language Projections

A core goal of the language is **automatic derivation of implementations in
target programming languages** by AI agents.

A projection transforms a specification into a runnable implementation in a
target language (e.g., TypeScript, Python, SQL). The specification's natural
language descriptions and test cases serve as the authoritative semantic
reference. Built-in operations have no implementation in the language itself
unless they are derived from other operations --- the natural language
description and test cases together **are** the definition.

Projections must:

- Preserve the semantics defined by the specification
- Pass all test cases defined in the source module
- Maintain provenance links to the originating specification fragments

A projection is validated by running the test cases from the specification
against the generated implementation. The specification, not the projection,
is the source of truth.

---

## 10. Type Inference and Document Enrichment

A dedicated tool performs **type inference and type checking** across the
specification corpus. Its two responsibilities are distinct:

**Type checking** validates that every operation's inputs, outputs, and
derived relationships are consistent with the declared types across all
modules. Errors and warnings are reported against the originating
specification fragment.

**Document enrichment** augments the existing markdown source files with
type information derived from inference. Enrichment is non-destructive: it
does not alter the authored prose or table content. Instead, it attaches
inferred type annotations as **reference-style footnotes** supported by
GitHub-flavored Markdown (e.g., `[^type-price]` at the annotated term,
with `[^type-price]: inferred type: Decimal` at the end of the file).
Footnotes keep type information co-located with the content they describe
while remaining visually unobtrusive in rendered output.

This approach preserves full round-trip fidelity: the enriched document
remains valid, human-readable markdown, and the footnotes serve as
machine-readable type metadata that further tooling --- including LLMs ---
can consume during subsequent inference or projection passes.

---

## 11. Live Data Binding and Specification Debugging

A specification can be **bound to a live data source** --- a production
database, a query result set, or a data file --- and executed against real
inputs while the operator observes the rendered markdown document.

This creates a **markdown-native debugger** aimed at non-technical
stakeholders. Rather than presenting stack frames or variable watches, the
debugger drives a rendered view of the specification itself. As execution
steps through an operation, the current input values and intermediate
results are overlaid directly on the relevant section of the markdown
document: table cells are annotated with live values, rule conditions light
up as they are evaluated, and the active step is highlighted within the
prose.

The interaction model mirrors a conventional step-debugger:

- **Bind** — attach a data source (database connection, file, or in-memory
  dataset) to a specification module.
- **Step** --- advance execution one operation or one row at a time,
  observing how values flow through the defined logic.
- **Inspect** --- hover or select any term in the rendered document to see
  the current bound value and its provenance in the data source.
- **Replay** --- re-run the same inputs after editing the specification to
  observe the effect of the change immediately.

Because the visualization is driven by the markdown document rather than a
separate debugger UI, the experience is identical whether the viewer is an
engineer or a domain expert. The specification is the debugger interface.

---

## 12. Immediate Impact Analysis

When a specification is edited, the tool can re-execute the entire
specification against the current bound data source and **highlight the
differences in output** relative to the previous run. This gives the author
immediate, evidence-based feedback on the consequences of a change.

The diff is presented in the rendered markdown view:

- Outputs that changed value are annotated inline, showing both the old and
  new result.
- Rows or cases that newly pass or fail a condition are marked visually.
- Aggregates and derived values that are transitively affected by the change
  are surfaced, even if the edited operation is not the direct producer.

This transforms specification editing from a write-and-guess workflow into
a **tight feedback loop**: edit a rule, observe the ripple effect across all
data immediately, and confirm or revert the change before it propagates
further. The impact analysis operates on the same markdown-native interface
as the live debugger, requiring no additional tooling or context switch.

---

## 13. Versioning

Specification corpora evolve over time as the regulations or domains they
codify are amended or superseded. Substrate treats this as an ordinary
software versioning problem rather than a temporal modelling problem:
corpora are versioned using the same mechanisms used for source code and
library packages --- git tags, semantic version identifiers, package-manager
releases. A given corpus at a given version is the authoritative
specification for the regulatory version it codifies; historical reporting
is served by checking out the appropriate corpus version.

This keeps the specification language itself free of effective-date
machinery. Date-sensitive behaviour within a single corpus version, when it
occurs, is expressed using the ordinary constructs --- for example, a
[Decision Table](language/concepts/decision-table.md) with a reporting-date
column --- rather than through a dedicated versioning construct.
