# Keeping `src/` Aligned With the Language Specification (Working Notes)

> Status: **design**. This document captures the agreed strategy for keeping
> the TypeScript implementation in `src/` aligned with the language
> specification in `specs/language/`. It is the output of a design session
> and the starting point for the implementation work that follows. No code
> has been written against it yet.

## Problem

The language specification under `specs/language/` is the source of truth for
substrate's semantics. The implementation under `src/language/` — operation
evaluators, the registry, the dataflow runtime — has to match that
specification. Today the alignment is maintained by hand: when an operation
is added, renamed, or its semantics change, both the spec and the matching
TypeScript code have to be edited in lockstep, and there is no mechanical
gate that catches drift. We want a strategy that makes drift either
impossible or immediately visible.

## Goals

Three goals, in increasing order of ambition:

1. **Behavioral equivalence.** Every `Test cases` table embedded in the
   language spec executes as a test against the implementation. Any divergence
   between what the spec says an operation does and what the implementation
   actually computes is a CI failure.
2. **Surface coverage.** Every operation declared in the spec has a
   corresponding entry in `src/`, and every entry in `src/` corresponds to a
   declared operation. Missing implementations and orphan implementations are
   both reported.
3. **Generated implementation.** Eventually, `src/language/expressions/*.ts`
   is regenerated from a *TypeScript horizontal* — a substrate horizontal
   package that pairs each operation's spec anchor with its TypeScript
   evaluator snippet. Once that workstream lands, hand-editing the generated
   files is forbidden; alignment is structural rather than disciplinary.

## Workstreams

Three workstreams, sequenced as follows:

- **Workstream 1 — Test runner extension.** Extend the existing test stage so
  that every operation in the spec is actually executed against the
  registered evaluator. This is the *oracle* the other workstreams depend on.
- **Workstream 2 — Coverage tool.** Implement `substrate coverage` per the
  existing specification at `specs/tools/cli/coverage.md`. Wire it into CI as
  a gate against missing/orphan operations in the language spec.
- **Workstream 3 — TypeScript horizontal + regeneration skill.** Author the
  TS horizontal retroactively, build the regeneration workflow as an
  agent-invocable skill, cut `src/language/expressions/` over to generated
  output.

Workstreams 1 and 2 run in parallel. Workstream 3 starts after Workstream 1
is solid enough that the test runner can prove behavioral equivalence — that
is what gates the cutover in (3).

## Design Decisions

### 1. Cell-value parsing uses link literals; no implicit parsing

Test-case table cells use the markdown-link-literal convention that the spec
already documents for boolean (`[true][bool]`). Each type's `## Literals`
section defines its surface syntax; each `src/language/<type>.ts` registers a
`parseLiteral` alongside its operations, keyed by the type's spec anchor.

There is no ad-hoc fallback parser. The current `parseCellValue` heuristic
(`true`/`false`/numeric guessing) is removed. Bare literals work only when
the column's declared type unambiguously determines parsing (see decision
3).

### 2. Operations carry explicit signatures

Every operation gains a structured signature, written in the same shape as
pipeline input/output declarations:

```markdown
### NOT [Operation](../concepts/operation.md)

Inverts the value of a Boolean.

#### Inputs
- `value`: [Boolean][bool]

#### Outputs
- `result`: [Boolean][bool]

#### [Test cases][tc]
| `value` | `result` |
| ------- | -------- |
| true    | false    |
| false   | true     |
```

`specs/language/concepts/operation.md` is amended to declare Inputs/Outputs
as required structural elements of an operation definition.

### 3. Column headers bind to parameter names

Test-case table column headers must be the parameter name in backticks,
matching exactly one entry in the Inputs/Outputs sections. The runner looks
up each header in the signature to determine which parameter the column
carries and how to parse its cells. Column order in the table is free;
missing columns are an error; unknown columns are an error.

Backticked headers must be strictly the parameter name — no decoration. Output
columns may be interleaved with inputs (binding is by name, so order is
irrelevant by construction).

### 4. Type classes use a single `[Type Instance]` slot, not named variables

Every type-class operation in the current language parameterises on a single
implementing type. Rather than introducing named type variables, the spec
adds a `## Type Instance` section to `specs/language/concepts/type-class.md`
that defines a single canonical slot. Type-class operation signatures
reference it directly:

```markdown
### Equal [Operation](../concepts/operation.md)

#### Inputs
- `left`: [Type Instance][instance]
- `right`: [Type Instance][instance]

#### Outputs
- `result`: [Boolean][bool]

[instance]: ../concepts/type-class.md#type-instance
```

If a future type class needs more than one hole (e.g. `Convertible : A → B`,
`Mappable`), the convention is extended at that point. This is a deliberate
bet against premature generality.

### 5. Instance test cases live under each type's `## Type Class Instances`

Type-class files contain only signatures and prose; they have no test cases
of their own. Test cases for each instance live under the implementing
type's `## Type Class Instances` section, structured per operation:

```markdown
## [Type Class Instances](../concepts/datatype.md#type-class-instances)

### [Equality][eq]

Boolean implements [Equality][eq]: two Boolean values are equal when they
are the same member.

#### [Equal][eq-equal] [Operation][op]

##### [Test cases][tc]
| `left` | `right` | `result` |
| ------ | ------- | -------- |
| true   | true    | true     |
...
```

Derived operations are tested per instance just like required ones. The
default implementation of a derived operation, expressed in terms of
required operations, stays prose-with-link-references on the type-class
side — it documents how the default works but is not executed by the runner.

The runner binds `[Type Instance]` to a concrete type by walking up from a
test-case heading through the `Type Class Instances > <ClassName> > <OpName>`
structure to the enclosing file H1. The H1 of the type's file IS the
binding.

### 6. Cross-file resolution is solved by `substrate context` composition

The runner stays single-file at the entry point. A new pipeline stage
invokes `substrate context` to compose the entry file plus everything it
transitively links to into a single self-contained mdast tree, with
cross-file references rewritten as in-document anchors. The runner consumes
the composed tree. There is no separate signature index, no eager pre-scan,
no lazy cross-file fetch — composition produces the whole reachable corpus
inline, and within-document resolution handles everything from there.

### 7. The composition stage runs between `references` and `typecheck`

Current stage chain: `parse → include → lint → references → typecheck →
test`.

New stage chain: `parse → include → lint → references → context → typecheck
→ test`.

`context` runs before `typecheck` because the typechecker also needs the
composed view to resolve cross-file type references. The CI invocation is
the corpus root README, which is expected to transitively link to every
normative section (gap-fill where it does not).

### 8. The test runner is strict from day one

No transitional acceptance of the old positional/ad-hoc format. The runner
is built against the new conventions; every spec file is migrated in the
same change. Because the corpus is small (~20 files) and the project is at
an early stage where sweeping changes are appropriate, the cost of an
atomic landing is preferred over the cost of carrying a deprecation path.

Spec-of-the-spec edits land first (`operation.md`, `type-class.md`,
`test-case.md`), authorising the new conventions, before any individual
operation page is migrated.

### 9. The TypeScript horizontal is a real horizontal package

The TS implementation lives in `horizontals/typescript/` as a substrate
package with `package.kind: horizontal`, in this repo for now (to be split
out before substrate 1.0). It mirrors the `specs/language/` directory layout
1:1. Each file links to the operation anchors it implements; under each
linked operation, a fenced `ts` code block carries the evaluator.

The snippet shape is a **typed lambda with named parameters drawn from the
signature**:

```ts
(value: boolean): boolean => !value
```

The generator emits the wrapper, the registry entry, and the arity from the
signature; the snippet's job is just the body in terms of named parameters.
The generator also emits the index assembly in `expressions/index.ts`. The
`Value` union in `ast.ts` stays hand-written for now.

Using the real horizontal mechanism gives future leverage: a Python
horizontal, an F# horizontal, etc. are each separate packages with
identical structure, each consumed by their own generator. Cross-target
conformance testing becomes possible by composing multiple horizontals.

### 10. The horizontal is LLM-interpreted, not deterministically parsed

The "generator" is an LLM agent invocation rather than a strict parser. The
markdown structure around each TS snippet does not have to be perfectly
machine-readable — it has to be clear enough for an agent to ground its
output. The TS snippets themselves are the load-bearing artifact.

This weakens reproducibility (running the agent twice may produce different
src files) but does not weaken correctness: the test runner from
Workstream 1 gates every regenerated tree against the spec's truth tables.
Any agent output that passes is valid; any output that fails is rejected.
The structural rigor of Workstreams 1 and 2 is what bounds the looser
horizontal.

### 11. Regeneration is on-demand via an agent-invocable skill

A new skill, shipped alongside the existing `substrate-cli` skill in
`assets/ai-instructions/`, encodes the regeneration workflow:

1. Compose the spec + TS horizontal via `substrate context --horizontal`.
2. Regenerate `src/language/expressions/*.ts` plus the index assembly.
3. Run `substrate verify` against the regenerated tree.
4. Surface the result.

The skill is portable across agent harnesses (Claude Code, Cursor, AFK
agents). Substrate itself stays free of model-API dependencies; the CLI
provides building blocks (`context`, `verify`, generator stubs); the skill
provides orchestration.

The trigger is explicit, not continuous: a developer asks their agent to run
the regeneration skill. CI does not auto-commit regenerated src. The
weakness of LLM non-determinism is contained by making invocation a
deliberate act, not invisible plumbing.

### 12. Failure mode: stop and surface

When the test runner rejects regenerated src, the skill stops and surfaces
the failures to the developer. The developer decides whether to re-invoke
the agent, edit the horizontal manually, or recognize the change needs
deeper thought. No auto-retry loop in the foundation; an `--auto-retry`
opt-in can be added later once failure patterns are understood.

Regeneration defaults to the whole tree. A per-operation targeting flag
(`--operation expressions/boolean.md#and-operation`) supports fast iteration
during horizontal development.

## Migration

The migration is one sweeping change, not a series of small PRs. In rough
order:

1. **Spec-of-the-spec edits.** `operation.md` gains Inputs/Outputs as
   required elements. `type-class.md` gains the `## Type Instance` section
   and explains the substitution rule. `test-case.md` documents the
   name-bound column header rule and the structural placement of instance
   test cases.
2. **Operation page edits.** Every `expressions/<type>.md` operation gains
   Inputs/Outputs; every test-case table switches to backticked named
   headers matching the parameters.
3. **Type-class extraction.** Each type-class file has its Boolean/Integer
   truth tables removed; signatures switch to `[Type Instance]`. The
   removed tables move to each implementing type's `## Type Class Instances`
   section in structured form.
4. **Cell parser overhaul.** `parseCellValue` is replaced by the
   link-literal registry. Each `src/language/<type>.ts` exports a
   `parseLiteral` alongside its operations; the runner dispatches by
   column's declared type.
5. **Composition stage.** A new `context` stage in `src/stages/` wraps the
   existing `substrate context` logic and threads the composed mdast tree
   into `typecheck` and `test`.
6. **Test runner rewrite.** The runner is rewritten against the new
   conventions: signatures, named columns, type-instance substitution,
   composed input.
7. **Coverage tool.** Implementation per `specs/tools/cli/coverage.md`,
   wired into CI.
8. **TS horizontal authoring.** `horizontals/typescript/` mirrors
   `specs/language/`; each operation gets a typed-lambda snippet.
9. **Regeneration skill.** Shipped under `assets/ai-instructions/`,
   distributed via `substrate install`.
10. **Cutover.** First agent-driven regeneration; `src/language/expressions/`
    becomes generated artifact, marked DO NOT EDIT.

## Open Items (Deferred)

- **Examples directory in CI.** Whether `examples/` documents are also run
  through the test runner, or only the language spec.
- **Non-operation concepts with test cases.** `concepts/decision-table.md`
  and similar — today skipped with a warning; whether they get evaluators
  in this round or stay out of scope.
- **Coverage tool extensions.** Whether coverage reports signature/evaluator
  mismatch (parameter named `divisor` in spec but `b` in the TS evaluator),
  or stays focused on anchor coverage.
- **Multi-parameter type classes.** Today's single `[Type Instance]` slot is
  sufficient for the existing language. Convertible/Mappable-style classes
  will require extending the convention with named type variables.
- **Out-of-repo horizontal split.** The TS horizontal stays in this repo for
  the foreseeable future; splitting it into its own npm package is a
  pre-1.0 task.
