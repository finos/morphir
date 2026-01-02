# ADR-0001: Representing Morphir IR Sum Types (Discriminated Unions) in Go

- Status: Accepted
- Date: 2026-01-01
- Deciders: Morphir Maintainers
- Technical Story: Port Morphir IR from DU-first languages (F#/Elm) to Go with multi-version JSON schema support.

## Context

Morphir IR (as used across implementations such as `finos/morphir-elm` and the Morphir .NET docs/spec) is heavily based on discriminated unions (sum types) and recursive tree structures. We are porting or interoperating with code written in languages with first-class discriminated unions (e.g., F#).

Key constraints and drivers:

- **Morphir JSON format varies by schema/version**. Encoding details differ between format versions (e.g., tagged arrays vs tagged objects).
- The IR is a **large, recursive AST/IR** with many union types and many cases.
- We expect to implement many compiler-like passes:
  - traversals (folds, visitors),
  - transforms/rewrites (maps),
  - analyses (collect, annotate).
- We need:
  - strong internal correctness (avoid invalid states),
  - reasonable ergonomics for traversal,
  - stable I/O via a schema/version aware codec layer.

We considered multiple approaches for simulating sum types in Go:

1. Single struct with discriminator field (`Kind`) plus optional payload fields.
2. Interfaces with per-case structs.
3. Single struct with one-of fields (case name as field) where exactly one field is populated.
4. Hybrid “tag wrapper + interface payload”.
5. Arena/indexed representation for performance.
6. Code generation to scale across many union types.

## Decision

This section captures the **target end-state** we are converging toward. The next section (“Implementation Status”) documents what is already implemented today.

We will model Morphir IR sum types in Go using:

1. **Sealed interfaces + one struct per case** for each union type (internal representation).
2. **Generated `Match`, `Fold`, and (optionally) `Map` helpers** per union type for ergonomics and consistency.
3. **Schema/version-specific codec packages** that translate between JSON and the internal IR model:
   - `codec/vX` packages implement (un)marshaling for version X (e.g., array-tagged unions).
   - The `ir` package stays free of JSON shape assumptions.
4. We will strongly prefer **code generation** for the per-union boilerplate:
   - case structs,
   - sealed interfaces,
   - match/fold/map helpers,
   - JSON codecs per schema version,
   - validation for decoded data where useful.

This yields a DU-like internal model with robust versioned I/O.

## Implementation Status (Current Repo)

This ADR describes the preferred *end-state* architecture. The repo currently implements the core of the approach, with some deliberate pragmatism while the port is still early.

### Implemented

- **Sealed interfaces + per-case structs**
  - Example: `Type[A]` in `pkg/models/stable/ir` uses an unexported interface method (e.g., `isType()`) to prevent implementations outside the package.
- **Match/Fold/Map helpers (manual, for `Type`)**
  - Implemented for `Type[A]` in `pkg/models/stable/ir/type_match_fold.go`.
  - Provides `MatchType`, `FoldType`, `MapType`, and `MapTypeAttributes` (plus `Must*` convenience functions).
- **Codec boundary (version-aware) without leaking JSON into IR**
  - JSON encoding/decoding is implemented under `pkg/models/stable/ir/codec/json`.
  - A single codec package supports multiple Morphir JSON shapes via an `Options{FormatVersion: ...}` switch (v1/v2/v3).
  - Includes codecs for `Name`, `Path`, `QName`, `FQName`, `Type`, `TypeSpecification`, `TypeDefinition`, constructors, and `AccessControlled`.
- **Tests exist and are version-aware**
  - Roundtrips plus version-specific shape assertions and negative tests for cross-version mismatches.

### Not Implemented Yet (Gaps vs Recommendation)

- **Code generation**
  - All union modeling and codecs are handwritten today.
  - This is manageable for the first module(s), but it will become costly as more IR modules are ported.
- **Generated helpers across all unions**
  - Only `Type` currently has `Match`/`Fold`/`Map` helpers.
  - Other unions will currently rely on `type switch` at call sites until helpers are added or generated.
- **Per-version codec packages (`codec/v1`, `codec/v2`, …)**
  - We currently have a single package with internal branching by `FormatVersion`.
  - This keeps the public surface small early on, but can increase complexity as more versions/types are supported.

### Practical Consequences / Trade-offs (Why this is OK for now)

- The **core invariant** still holds: IR types are stable and do not embed JSON knowledge; version churn is isolated to the codec layer.
- The repo gets **fast iteration** early: one package, one Options switch, fewer files.
- The main risk is **scaling pressure**:
  - match/fold/map helpers and per-version codec branching will become repetitive.
  - code generation will likely be the right next step once we move beyond the first few IR modules.

### Trigger Points for Retrofitting Toward the ADR

Consider introducing generation and/or per-version codec packages when one or more of these become true:

- We start porting additional IR modules with many unions (e.g., `Value`, `Pattern`, `Literal`).
- Codec functions routinely hit lint thresholds for complexity/duplication.
- We need systematic traversal/rewrites across many unions (not just `Type`).
- We want schema-driven evolution where the schema itself becomes the generator input.

## Rationale

### Why sealed interfaces + per-case structs

- **Type safety / invalid states**: A value is exactly one case at a time, avoiding the “Kind says Apply but Literal is set” class of bugs.
- **Maintainability**: Each case’s fields are localized to one struct, making changes and reviews easier.
- **Traversal fit**: Recursive trees are naturally handled by `type switch` or generated `Match`/`Fold`.
- **Evolution**: Adding/removing cases changes a small surface area in the generated code.

### Why separate codecs by schema/version

- Morphir’s JSON format **changes by version**. Coupling JSON shape to the IR types would force churn throughout the codebase.
- A codec boundary allows:
  - supporting multiple versions concurrently,
  - deterministic upgrade paths,
  - targeted tests per version.

### Why generate Match + Fold

Go lacks first-class pattern matching and exhaustiveness checking. Generated helpers provide:

- **Consistent ergonomics** across the entire IR.
- **“Exhaustive-ish” pressure**: Adding a case forces updates in one centralized generated switch and in the matcher/folder structs.
- **Cleaner code** for IR transforms/analyses vs repetitive `switch x := n.(type)` at call sites.

## Detailed Design

### Package structure

- `ir/`
  - Core IR types: sealed interfaces + per-case structs.
  - No JSON tags and no JSON (un)marshal logic.
  - Optionally: helpers not tied to any JSON version.

- `codec/`
  - `codec/v1/`, `codec/v2/`, ... (one per Morphir format version)
  - Each version package implements encode/decode between JSON and `ir` types.
  - Optional: a version dispatcher `codec.Decode(data)` that reads a top-level version marker and routes to the correct version.

- `internal/gen/` (or `tools/gen/`)
  - Code generation tooling reading Morphir schema/spec to generate:
    - `ir` union definitions and constructors (optional),
    - `Match`/`Fold`/`Map`,
    - `codec/vX` implementations.

  **As implemented today** (incremental subset of the above):

  - `pkg/models/stable/ir/` — stable IR domain types (no JSON tags, no `encoding/json` hooks)
  - `pkg/models/stable/ir/codec/json/` — version-aware Morphir-compatible JSON codecs selected via `Options.FormatVersion`

### Sealed interface pattern (closed world)

In Go, we emulate a “closed” union by using an unexported method:

```go
// ir package

type sealed interface{ sealed() }

type Expr interface {
    sealed
    isExpr()
}
```

Each case implements the unexported method, preventing implementations outside the `ir` package:

```go
type Apply struct {
    Fn  Expr
    Arg Expr
}
func (Apply) sealed() {}
func (Apply) isExpr() {}
```

### Match helper (functional pattern matching)

For each union, generate:

```go
// ir package

type ExprCases[T any] struct {
    Apply    func(Apply) T
    Variable func(Variable) T
    // ... one function per case
}

func MatchExpr[T any](e Expr, c ExprCases[T]) T {
    switch v := e.(type) {
    case Apply:
        return c.Apply(v)
    case Variable:
        return c.Variable(v)
    default:
        panic("unknown Expr case")
    }
}
```

Notes:
- The default `panic` should be unreachable if the union is sealed and defined in-package.
- We may optionally provide:
  - `MustMatchExpr` (panic on missing handler),
  - `MatchExprDefault` (a default handler for unhandled cases), depending on team preference.

### Fold helper (tree traversal)

We will also generate `Fold` functions for recursive types to standardize traversal.

There are two common styles; we will generate one consistently:

**Style A: Algebra-based fold (catamorphism-like)**

- Define an algebra of functions that consumes already-folded child results:

```go
type ExprFold[T any] struct {
    Apply    func(fn T, arg T) T
    Variable func(name []string) T
    // ...
}

func FoldExpr[T any](e Expr, f ExprFold[T]) T {
    switch v := e.(type) {
    case Apply:
        fn := FoldExpr[T](v.Fn, f)
        arg := FoldExpr[T](v.Arg, f)
        return f.Apply(fn, arg)
    case Variable:
        return f.Variable(v.Name)
    default:
        panic("unknown Expr case")
    }
}
```

This style is compact and encourages pure, compositional analyses.

**Style B: Visitor fold (pre/post-order hooks)**

- Not chosen as the primary approach, but can be added later for specialized needs.

We will implement **Style A** as the default generated fold.

### JSON codecs (version-specific)

Each `codec/vX` package will implement:

- `func DecodeExpr(data []byte) (ir.Expr, error)`
- `func EncodeExpr(e ir.Expr) ([]byte, error)`
- and equivalents for other IR types.

Implementation approach depends on the schema encoding. For example, for **array-tagged unions**:

- Unmarshal to `[]json.RawMessage`,
- read the first element as the tag,
- decode the payload based on the tag,
- recursively decode child nodes.

For **object-tagged unions**, decode the discriminator field then payload.

Because this logic is repetitive and case-heavy, it will be code-generated per schema version.

### Validation

- Constructors and sealed per-case structs already prevent many invalid states.
- For JSON decode, we will:
  - validate tag arity (expected payload element counts),
  - validate required fields,
  - return descriptive errors on unknown tags or malformed payloads.
- Optional: generate `Validate()` methods for each union case if deeper invariants are needed.

## Consequences

### Positive

- Stronger internal correctness than discriminator mega-struct approaches.
- Traversals and transforms become consistent via generated `Match` and `Fold`.
- JSON version churn is isolated to `codec/vX`.
- Scales to a large IR due to generation.

### Negative / Trade-offs

- Requires custom (un)marshal code (mitigated via codegen).
- Go cannot provide true compile-time exhaustiveness; generated helpers provide “exhaustive-ish” friction but not guarantees.
- More files/types than a single mega-struct model (acceptable for clarity and safety).

### Performance implications

- Per-case structs with interfaces introduce interface values and (often) heap allocations for recursive nodes.
- This is acceptable initially; if profiling later shows allocation pressure:
  - consider pointer vs value choices on a per-type basis,
  - consider interning, memoization, or an arena representation as an optimization layer,
  - keep codecs separate so internal representation can change without breaking JSON.

## Alternatives Considered

### A) Single struct with discriminator + optional payload fields

Pros:
- Simple JSON mapping if schema is object-tagged.
- Single node container.

Cons:
- Invalid states easy to represent (multiple payloads set, mismatched Kind).
- Noisy nil checks and invariant handling.
- Requires constructors/validation everywhere; error-prone at Morphir scale.

Rejected due to weak internal type safety and high maintenance risk.

### B) “One-of fields” struct (field name indicates case)

Pros:
- May align with certain JSON shapes.

Cons:
- Worst invariants (two fields can be set; no cheap switch).
- Awkward traversal.
- Hard versioning story.

Rejected.

### C) Arena/indexed nodes

Pros:
- High-performance, fewer allocations, cache-friendly.

Cons:
- Lower ergonomics; invariants shift into constructors.
- More complex to implement; more distance from the source IR model.
- Codec complexity increases.

Deferred as a potential optimization if profiling indicates need.

### D) Hybrid tagged wrapper + interface payload

This can be useful for certain I/O needs but is effectively subsumed by:
- sealed interfaces internally, and
- codec packages externally.

Not selected as a primary representation; may be used internally in codecs if beneficial.

## Implementation Plan

1. Define generator inputs:
   - schema links/spec per Morphir format version.
2. Generate `ir` package:
   - sealed interfaces,
   - case structs,
   - `Match*` and `Fold*` helpers.
3. Generate `codec/vX`:
   - decode/encode functions for each union type.
4. Add tests:
   - golden JSON fixtures per schema version,
   - round-trip tests (decode → encode → compare normalized form),
   - traversal correctness tests using `Fold`.
5. Profile real workloads; consider optimizations only if required.

## Notes

- The `ir` package must remain free of JSON tags and version-specific concerns.
- The generator should be deterministic and format with `gofmt`.
- All public APIs should be documented with the Morphir IR case names to help readers coming from Elm/F#.
