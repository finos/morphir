# ADR-0003: Toolchain Integration Framework

**Status:** Proposed
**Date:** 2026-01-08
**Authors:** Morphir Team

## Context

Morphir needs to integrate with both external tools (like `morphir-elm`) and native Go implementations (like WIT bindings) to provide a complete development experience.

**External tools** (morphir-elm):
- `morphir-elm make`: Compiles Elm sources to Morphir IR (frontend)
- `morphir-elm gen`: Generates target language code from IR (backend)

**Native implementations** (WIT bindings - already implemented):
- `morphir wit make`: Compiles WIT to Morphir IR
- `morphir wit gen`: Generates WIT from Morphir IR
- `morphir wit build`: Full pipeline with round-trip validation
- JSONL batch processing support

We want to:
1. Orchestrate both external tools and native implementations through a unified CLI
2. Support future toolchains (Haskell, PureScript frontends; Spark, Scala backends)
3. Provide a unified, inspectable build experience
4. Enable caching and incremental builds
5. Adapt the existing WIT pipeline as the first native toolchain

## Decision

We will implement a **Toolchain Integration Framework** with the following architecture:

### Core Abstractions

1. **Toolchains**: Tool adapters (native or external) that provide tasks and can hook into execution lifecycle
   - **Native toolchains**: In-process Go implementations (e.g., WIT bindings)
   - **External toolchains**: Process-based tools (e.g., morphir-elm via npx)
2. **Targets**: CLI-facing capabilities (make, gen, test) that tasks fulfill
3. **Tasks**: Concrete implementations that produce artifacts (via Go code or process execution)
4. **Workflows**: Named compositions of targets with staged execution

### Key Design Choices

#### Hybrid Pipeline Model
- **Targets** declare capabilities and artifact contracts
- **Workflows** define orchestration (stages, parallelism, conditions)
- **Execution plan** is computed by merging workflow order with target dependencies
- Plan is validated, optimized, and inspectable via `morphir plan`

#### Artifact-Based Communication
- Tasks produce outputs to `.morphir/out/{toolchain}/{task}/`
- Artifacts are JSONC files (human-readable with comments)
- Diagnostics stream as JSONL/NDJSON
- Tasks reference other outputs via logical paths (`@toolchain/task:artifact`)

#### Middleware Execution
- Task execution follows a pipeline: RESOLVE → CACHE → PREPARE → EXECUTE → COLLECT → REPORT
- Toolchains can inject hooks at any stage
- Task system owns error reporting; toolchains contribute diagnostics

#### Configuration Inheritance
- Workflows support `extends` for inheritance
- Precedence: project > toolchain > built-in defaults
- Similar to tsconfig/eslint extends pattern

### CLI Mapping

```bash
morphir make           # Run target
morphir gen:scala      # Run target variant
morphir build          # Run workflow
morphir plan build     # Show execution plan
morphir doctor         # Diagnose configuration issues
```

## Consequences

### Positive
- Unified CLI regardless of underlying toolchain
- Inspectable builds via `morphir plan`
- Cacheable tasks based on input hashing
- Extensible to new frontends/backends
- Familiar patterns (Mill, Bazel, Make)

### Negative
- Complexity of merged execution model (mitigated by plan visualization)
- Two concepts (targets + workflows) to understand
- File-based communication may be slow for large artifacts (future: streaming)

### Neutral
- External tools must be acquired/installed
- Initial focus on file-based I/O (LSP/gRPC deferred)

## Alternatives Considered

### A: Pipeline-only (no targets)
- Simpler but less composable
- Hard to express "any tool that produces IR"
- Rejected: loses flexibility

### B: Targets-only (no workflows)
- Target dependencies form implicit pipeline
- Simpler but less control over staging
- Rejected: need explicit stages for complex builds

### C: Current choice (hybrid)
- Targets for capabilities, workflows for orchestration
- Plan merges both with validation
- Accepted: best balance of power and safety

## References

- [Toolchain Integration Design](../toolchain-integration-design.md)
- [ADR-0002: Processing Pipeline](ADR-0002-processing-pipeline.md)
- [Mill Build Tool](https://mill-build.com/)
- [moonrepo](https://moonrepo.dev/)
- [mise](https://mise.jdx.dev/)
