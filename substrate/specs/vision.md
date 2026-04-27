# Vision: Verifiable Knowledge for Human–LLM Collaboration

## 1. Executive Summary

Substrate is a **specification substrate**: a structured, link-typed,
human-readable corpus of markdown documents that captures what a system
*should* do — its concepts, rules, operations, and examples — in a form
that both humans and LLMs can read, edit, and reason about.

Its purpose is to turn the documents an organization already writes —
specifications, regulations, domain models, runbooks — into **verifiable
knowledge**: a corpus whose internal consistency, type compatibility, and
behavioural claims can be checked by tooling rather than taken on faith.
Once knowledge is verifiable, it becomes the durable shared context
across humans, code, and AI agents.

Substrate is not, primarily, a programming language. The corpus is
ordinary markdown, designed to be read on GitHub by anyone. Where
precision warrants, fragments of that markdown are *executable* — they
carry types, examples, and test cases that the tooling can run — but the
medium and the audience remain prose-first.

## 2. The Problem We Address

Most institutional knowledge lives in documents that are **unverifiable**:
wikis, PDFs, slide decks, tickets. Nothing checks that a definition on
page 12 matches the rule on page 47, that an example still produces the
stated output, or that a downstream system actually implements the
described behaviour. As specifications evolve, the gap between document
and reality widens silently.

LLMs make this worse before they make it better. They are powerful
readers and writers of unstructured prose, but their answers are only as
trustworthy as the context they are given. Feeding an LLM the wrong slice
of a sprawling document set, or a slice that quietly contradicts itself,
produces confident output that is wrong in ways no one catches.

The opportunity is symmetrical: the same structure that makes a corpus
mechanically verifiable also makes it the ideal context source for an
LLM. A document set that tools can check, an LLM can be trusted to act
on.

## 3. What Substrate Is

Substrate has three layers:

**A medium.** GitHub-flavored markdown, rendered everywhere, written by
humans. No custom syntax. Structure is expressed through ordinary
markdown features — headings, tables, lists, footnotes, and especially
**links**, which carry semantic meaning between documents.

**A corpus model.** Files are organized into versioned **packages** —
either *libraries* (reusable concepts, types, operations) or a *corpus*
(an authoritative, leaf-level body of specification for a specific
domain). Cross-package references are ordinary relative links; tooling
keeps them resolvable.

**A toolchain.** A CLI that extracts focused context for LLMs, validates
the corpus for consistency and type compatibility, refactors safely
across files, runs the embedded tests, and binds specifications to live
data for stakeholder-facing debugging.

## 4. Core Principles

### 4.1 Verifiable Knowledge

Every claim the corpus makes — that this term has that type, that this
operation produces that output for this input, that this rule depends on
that definition — should be mechanically checkable. Verification is
layered: structural validity, link resolution, type compatibility,
example-driven test cases. The corpus earns its trust through tooling,
not through review fatigue.

### 4.2 Markdown as the Source of Truth

The markdown files are the canonical artifact. Anything else — derived
implementations, type indices, dependency graphs — is a projection of
the markdown. Authors write prose and links; tools maintain everything
downstream. The corpus remains readable, diffable, and reviewable with
the tools every contributor already has.

### 4.3 Links as a Lightweight Type System

Plain markdown becomes structured by linking. A reference to a *concept*
or *type* or *operation* is a link to its definition; the link target,
not a separate annotation, is what carries the semantic relationship.
This turns prose into a navigable graph that both humans and LLMs can
follow.

### 4.4 Designed for Human–LLM Collaboration

The corpus is the **shared context** between people and language models.
LLMs draft and refine it; humans curate it; tooling keeps both honest.
Three properties make this work in practice:

- **Tree-shakeable context.** The tooling can produce a self-contained
  slice of the corpus reachable from any starting point — small enough
  to fit in a model's context window, complete enough to answer
  questions accurately.
- **Round-trippable structure.** Documents can be enriched with inferred
  metadata (e.g. inferred types as footnotes) without losing prose
  fidelity. An LLM can read enriched documents on the next pass.
- **Safe automated edits.** Refactors update every cross-document
  reference atomically, so an LLM rewriting one section never silently
  breaks links elsewhere.

### 4.5 Executable Where Precision Warrants

Some knowledge is precise enough to run. Substrate lets a specification
fragment carry types, inputs, outputs, and test cases — and the tooling
can evaluate definitions, run the tests, and report failures against the
originating prose. Execution is opt-in, not pervasive: most of the
corpus stays narrative.

### 4.6 Spec-First, Not Code-First

Where Substrate *is* used to drive software, the specification is the
source of truth and implementations are derived from it. A change to
behaviour is a change to the corpus first; the implementation follows.

## 5. Tooling Pillars

The CLI is organized around five capabilities:

**Context.** Extract a self-contained, link-resolved slice of the corpus
starting from one or more files or sections. The output is plain
markdown, suitable for piping into an LLM, attaching to a ticket, or
reviewing in isolation. Tree-shaking ensures only what is reachable is
included.

**Validation.** Check the corpus for structural consistency, link
resolution, type compatibility across operations, and example-driven
test coverage. Findings are reported against the originating
specification fragment, not against an opaque intermediate
representation.

**Refactoring.** Rename files and sections, move sections between files,
and split or merge documents — with every cross-corpus reference
updated atomically. Authors and LLMs can restructure freely without
breaking the link graph.

**Packaging.** Manage cross-repository dependencies through a manifest
and a vendored `substrate/` tree. Packages are versioned with ordinary
git tags and semver; updating a dependency is a reviewable commit, not
an opaque resolution step.

**Live binding and debugging.** Attach a specification to a real data
source — a database, a query result, a file — and step through it in
the rendered markdown. Table cells are annotated with live values,
conditions light up as they evaluate, and the active step is highlighted
in the prose. Editing a rule re-runs the corpus and surfaces the diff in
output. The specification *is* the debugger interface, accessible to
domain experts without engineering tooling.

## 6. Projections to Implementations

Where a corpus is precise enough, AI agents can derive runnable
implementations in target languages — TypeScript, Python, SQL — from the
specification. The natural-language descriptions and embedded test cases
are the authoritative semantic reference; the projection is validated by
running the corpus's own test cases against the generated code.

Projections are downstream of the corpus, not parallel to it. The
specification, not the projection, is the source of truth, and
provenance links flow from generated code back to the originating
fragments.

## 7. Versioning

Corpora evolve as the regulations or domains they codify are amended.
Substrate treats this as ordinary software versioning: git tags, semver,
package-manager releases. A corpus at a given version *is* the
authoritative specification for that version of the domain; historical
reporting is served by checking out the appropriate corpus version.

The language itself stays free of effective-date machinery. Date-sensitive
behaviour within a single version is expressed using ordinary constructs
— for example, a decision table with a reporting-date column.

## 8. Who Substrate Is For

- **Domain experts** — write and review specifications in prose, debug
  them against real data, without learning a programming language.
- **Engineers** — derive and maintain implementations from a verified
  source of truth, with refactors that don't break references.
- **AI agents** — operate against a corpus whose structure and
  consistency they can rely on, with tooling that gives them exactly
  the slice of context a task requires.
- **Auditors and stakeholders** — read the same documents the system
  runs, with provenance from any output back to the rule that produced
  it.

## 9. Long-Term Ambition

> Institutions accumulate verifiable knowledge — specifications they can
> trust, evolve, and project into running systems — co-developed with AI
> and explainable to humans.

A Substrate corpus becomes, simultaneously:

- The documentation
- The contract
- The test harness
- The shared context for human–LLM collaboration
- The blueprint from which implementations are derived

All in one artifact, written in ordinary markdown, kept honest by
tooling.
