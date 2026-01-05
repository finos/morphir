# ADR-0002: Processing Pipeline Architecture

- Status: Proposed
- Date: 2026-01-01
- Deciders: Morphir Maintainers
- Technical Story: Define a functional processing pipeline for Morphir Go.

## Context

Morphir Go needs a consistent way to process IR across commands such as validate,
build, analyze, and generate. The Morphir IR is the central AST, with decorators
as extensible sidecar metadata. Other ASTs may flow through the pipeline
(e.g., Elm ASTs). Today there is no pipeline implementation in `pkg/pipeline`,
and the CLI implements behavior command-by-command.

We need:

- Composable, testable processing steps.
- Clear separation of I/O from core logic.
- Structured diagnostics and JSON output for automation.
- Alignment with Morphir's functional programming principles.
- A VEntry abstraction (files, documents, nodes, folders, archives) with metadata.
- A mountable virtual filesystem with precedence and read-only/read-write zones.
- Targets (build/test/clean) and tasks that can execute intrinsic actions and
  external commands.

## Decision

We will implement a functional pipeline framework in `pkg/pipeline` with:

1. **Pure step functions** that accept immutable context and input and return
   output plus structured results (diagnostics, artifacts, errors).
2. **Ordered pipeline composition** that executes steps sequentially and
   short-circuits on error while retaining collected outputs.
3. **Structured results** that can be encoded to JSON for CLI `--json` output.
4. **Explicit I/O boundaries**: I/O lives in CLI or tooling layers, not in
   pipeline steps.
5. **VEntry and VFS abstractions** to represent inputs/outputs and mounted
   workspace/config environments.
6. **Targets and tasks** to orchestrate pipelines and support external commands.

## Consequences

- CLI commands become thin wrappers that assemble pipelines and render results.
- Step implementations are isolated and unit-testable.
- Diagnostics are consistent across commands.
- Future extensions (caching, parallelism) can be added without changing
  step semantics.

## Alternatives Considered

1. **Ad-hoc command logic** per CLI command.
   - Rejected due to duplication and inconsistent diagnostics.
2. **Pipeline with side-effecting steps**.
   - Rejected due to poorer testability and misalignment with functional goals.
3. **External workflow engine**.
   - Rejected as too heavy for the current scope.

## Implementation Notes

- `pkg/pipeline` will host core types and composition helpers.
- `pkg/tooling` will provide step implementations (validation, reports, etc.).
- `pkg/vfs` (or similar) will define VEntry and virtual filesystem types.
- `cmd/morphir` will assemble pipelines and route outputs to stdout/stderr.
