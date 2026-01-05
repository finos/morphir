---
id: processing-pipeline-design
title: Morphir Processing Pipeline Design
---

# Morphir Processing Pipeline Design

## Overview

This design proposes a functional, composable processing pipeline for Morphir Go.
The pipeline is an orchestration layer for IR validation, transformation, analysis,
and code generation. It favors immutable data, pure step functions, and clear I/O
boundaries. The Morphir IR is the central AST, with decorators as extensible sidecar
metadata, while other ASTs may flow through the pipeline (e.g., Elm ASTs).

## Design Principles

- Functional composition over imperative flow.
- Immutable data structures and return-new-value patterns.
- Clear separation of I/O from pure processing.
- Deterministic outputs and structured diagnostics.

## High-Level Architecture

- `pkg/pipeline` defines core pipeline types and composition helpers.
- `pkg/tooling` hosts step implementations (validation, reporting, etc.).
- `pkg/vfs` (or similar) defines the VEntry and virtual filesystem abstraction.
- `cmd/morphir` assembles pipelines for CLI commands and routes output.

## Core Types (Proposed)

```go
// Step is a pure transformation with a stable name and description.
type Step[In, Out any] struct {
	Name        string
	Description string
	Run         func(Context, In) (Out, StepResult)
}

// Context is immutable execution context passed to all steps.
type Context struct {
	WorkspaceRoot string
	FormatVersion int
	Now           time.Time
	Mode          Mode
	VFS           VFS
}

## VFS Integration Note

The pipeline `Context` should carry a `VFS` instance so steps can access inputs and
artifacts via a mountable filesystem abstraction. Implementation guidance:

- Construct the VFS in the CLI or orchestration layer (e.g., OS-backed mounts for
  workspace/config/env, in-memory mounts for generated artifacts).
- Keep the pipeline steps pure: steps read from VFS and emit artifacts/diagnostics,
  but do not perform direct OS I/O.
- Pipeline tests can inject in-memory VFS mounts to avoid filesystem dependencies.

// StepResult captures diagnostics and artifacts emitted by a step.
type StepResult struct {
	Diagnostics []Diagnostic
	Artifacts   []Artifact
	Err         error
}

// Pipeline is a sequence of steps that transforms In to Out.
type Pipeline[In, Out any] struct {
	Name  string
	Steps []AnyStep
	Run   func(Context, In) (Out, PipelineResult, error)
}

// PipelineResult aggregates execution metadata.
type PipelineResult struct {
	Diagnostics []Diagnostic
	Artifacts   []Artifact
	Steps       []StepExecution
}
```

Notes:
- `AnyStep` and `StepExecution` are adapters for heterogenous steps.
- `StepResult.Err` indicates step failure without forcing a panic.
- `Mode` represents CLI mode (interactive, json, default).

## Composition and Execution

- Pipelines are assembled by composing steps left-to-right.
- Each step receives the previous step output and the same `Context`.
- If a step returns an error:
  - Execution stops.
  - Collected diagnostics and artifacts are preserved.
  - The pipeline returns a structured error with step metadata.

## Pipeline Lifecycle Example

Example flow for an Elm project:

1. Trigger: `morphir make` invokes the `build` target (a conventional task name).
2. Gather context: mount workspace/config/env into the VFS and load project config.
3. Collect inputs: discover Elm source files and documents via VEntry traversal.
4. Parse: Elm sources into an Elm AST (transient).
5. Transform: Elm AST into Morphir IR.
6. Decorate: attach decorators and project metadata sidecars.
7. Analyze: run analyzers over config/IR/artifacts, emit diagnostics.
8. Emit outputs: write `morphir-ir.json` or generated artifacts to output mounts.

## Targets and Tasks

Targets follow build system conventions (e.g., build, test, clean). Conceptually,
targets are just conventional task names or aliases, so we should avoid
over-modeling the distinction unless a practical need emerges. CLI commands can
invoke targets directly, while allowing users to customize execution with pre/post
hooks (tasks that run before or after a target).

Tasks can run:

- Intrinsic actions (internal Morphir steps).
- External commands (mise-like execution).

Tasks support parameters and environment variables. Configuration lives in
`morphir.toml` (and matching JSON if needed).

Tasks can declare dependencies. Tasks should also declare inputs and outputs to
support caching and incremental builds. Task outputs should be JSON-serializable
to enable structured reporting (similar to mill task outputs).

External commands should run in a sandboxed context by default: only explicitly
declared read-write mounts are writable. Provide an explicit opt-in to broaden
access when needed.

## Diagnostics and Artifacts

Diagnostics should include:
- Severity (info, warn, error).
- Code (stable identifier).
- Message.
- Location (optional file/path + pointer).
- Step name.

## Analyzers

The pipeline should support analyzer-style steps (similar to Roslyn/Ionide analyzers)
that inspect inputs or IR and emit diagnostics without necessarily transforming the
core output. Analyzers can run at multiple stages (source, config, IR, generated
artifacts) and should integrate with the shared diagnostics model.

Analyzer capabilities should include:

- Configurable enable/disable, rule sets, and severity overrides.
- Optional quick-fix suggestions attached to diagnostics.
- Emission of analyzer artifacts (reports, metadata) in addition to diagnostics.
- Categories (style, correctness, compatibility, etc).
- Sequential execution by default, with optional parallelization within a stage.

Artifacts should include:
- Kind (ir, report, codegen, metadata).
- Content or a path reference.
- Content type.

## CLI Integration

- CLI commands construct pipelines and run them with a `Context`.
- `--json` uses `PipelineResult` encoding on stdout.
- Diagnostics always go to stderr (even in JSON mode).
- Interactive TUI mode is a separate layer and consumes pipeline results.

## Versioning and Compatibility

- `Context.FormatVersion` informs validation and codec steps.
- Pipelines must be able to run across IR format versions (v1-v3).
- The pipeline should not embed JSON encoding logic; use codecs in `pkg/models/ir/codec`.

## Extensibility

Future steps may include:
- Normalization and desugaring passes.
- Linting/analysis passes with rule sets.
- Code generation for specific targets.
- IR diffing and regression checks.

## Testing Approach

- Each step is unit-tested with table-driven tests.
- Pipeline composition tests verify:
  - Step order.
  - Diagnostics aggregation.
  - Error short-circuiting.
- Use small, deterministic IR fixtures under `tests/` or `examples/`.

## Open Design Topics

- Define a shared JSON schema for pipeline results.
- Decide how to represent step durations (wall time vs monotonic).
- Determine how to model partial outputs on failure.
- Specify the initial set of VEntry variants and traversal patterns.
- Define task execution isolation rules for external commands.
- Decide whether config shadowing should support optional merge policies.
## VEntry and Virtual Filesystem

We define a shared `VEntry` interface for files, documents, nodes, folders, and archives.
All entries can carry metadata (like unifiedjs VFile data) to enable richer processing.

Archives behave like directories (traversable, mountable) but remain distinct artifacts.

The virtual filesystem (VFS) supports:

- Named mounts with precedence (later mounts override earlier ones).
- Read-only mounts for configuration and environment.
- Read-write mounts for workspace/build output.
- Optional sandbox enforcement (writes restricted to permitted mounts).

### VPath Defaults

We will use a custom POSIX-like `VPath` type:

- Forward-slash separators only (no OS-specific separators).
- Normalized paths (no `.` or `..` segments after normalization).
- Case-sensitive by default.
- Explicit root (e.g., `/workspace/...`) to avoid OS path confusion.
- Relative paths are allowed within a mount context.
- Resolving `..` that would escape the root should return an error.
- Globbing is handled by VFS traversal/query APIs, not by VPath itself.

### Entry Types (Draft)

- `VEntry`: base interface with `Path`, `Kind`, `Meta`, and `Origin`.
- `VFile`: leaf content; supports eager bytes and lazy streaming access.
- `VDocument`: specialized `VFile` with a root `VNode` for hierarchical structure.
- `VNode`: node with `Type`, `Attrs`, and `Children`.
- `VFolder`: container of child `VEntry` values.
- `VArchive`: archive artifact with raw bytes and optional exploded view.

### Mount Precedence and Shadowing

When mounts overlap, later mounts take precedence but earlier entries are preserved
as shadowed entries (available for inspection/auditing).

Shadowed entries should be read-only when accessed through the overlay view, while
preserving their mount metadata (RO/RW) for explicit mount access.

Suggested API shape:

- `Resolve(path VPath) (VEntry, []VEntryShadow)` returns the visible entry plus the
  full lineage of shadowed entries.
- `List(path VPath, opts)` supports `IncludeShadowed` for directory listings.

`VEntryShadow` should include the shadowed entry, mount metadata, and the override
reason. Shadowed entries are returned in precedence order (highest to lowest).

### Metadata

Metadata is supported in two forms:

- Dynamic map form for flexibility (`map[string]any`).
- Typed metadata for structured use; provide mapping helpers between the two.

Typed metadata should support multiple namespaces (e.g., `morphir.ir`, `morphir.config`)
and dynamic metadata keys should be namespaced to avoid collisions.

Typed metadata may exist without serializers for in-memory use, but JSON output
should surface missing serializers as warnings or controlled failures depending
on strictness.

### Traversal Helpers

Traversal should support both functional helpers and optional visitor-style patterns:

- Pre-order and post-order traversal.
- Path-based traversal with globbing at the VFS level.
- Shadowed entries included by default (with opt-out).

Suggested functional helpers:

- `Walk(entry, preFn, postFn)` with control (continue/skip/stop).
- `Filter(entry, pred)` returns matching entries.
- `MapSame(entry, fn)` for same-kind replacement.
- `Map(entry, fn)` for cross-kind rewrite (e.g., `VFile` to `VDocument`).
- `Fold(entry, acc, fn)` for aggregation.

Visitor-style helpers can be provided for case-based extension without
type switches.

## Extension and Traversal Patterns

We will use patterns that enable extensible behavior over the core types. In Go, this
may include a visitor-like interface, explicit `Match` helpers, or other functional
traversal patterns. The choice is pragmatic: pick the pattern that fits the task
without forcing a single style everywhere.
