---
id: processing-pipeline-requirements
title: Morphir Processing Pipeline Requirements
---

# Morphir Processing Pipeline Requirements

## Summary

This document captures the requirements for a Morphir processing pipeline in the Go port.
The pipeline is the backbone for non-interactive commands (validate, build, generate, analyze)
and should remain consistent with Morphir's functional principles. The Morphir IR is the
central AST, with decorators as extensible metadata sidecars.

## Goals

- Provide a composable, testable pipeline abstraction for Morphir IR processing.
- Keep core steps pure, isolating I/O at clear boundaries.
- Support diagnostics, structured results, and JSON output for CLI commands.
- Enable reuse across CLI commands and SDK-driven workflows.
- Align with Morphir IR specification and upstream tooling behavior.
- Support a VEntry abstraction (files, documents, nodes, folders, archives) with metadata.
- Support a mountable virtual filesystem with precedence and read-only/read-write zones.
- Support task/target execution (build/test/clean) with intrinsic actions and external commands.
- Support caching and incremental builds as a fast follower to the MVP.

## Non-Goals (v1)

- Distributed execution or remote pipeline orchestration.
- Parallel execution across steps (sequential execution only).
- Persistent caching and incremental builds are not required for MVP, but are expected
  in the first post-MVP iteration (v1).
- Interactive UI concerns (handled by the TUI layer, not pipeline core).

## Primary Use Cases

- Load and validate Morphir IR from file or workspace.
- Transform IR (normalize, desugar, annotate) before downstream stages.
- Run analyses (linting, compatibility checks, metrics).
- Generate target artifacts (codegen, docs, schemas).
- Emit structured reports for CI pipelines and automation.
- Process mixed inputs (source code, documents, archives) into Morphir IR.

## Functional Requirements

- Define a pipeline as an ordered sequence of steps.
- Each step must:
  - Accept an input value and immutable context.
  - Return a new output value or a structured error.
  - Emit diagnostics without printing directly to stdout.
- Represent inputs and outputs as VEntry instances (files, docs, nodes, folders, archives).
- Represent hierarchical documents and nodes with per-entry metadata.
- Provide a standard way to:
  - Capture diagnostics (severity, code, message, location, step).
  - Capture artifacts (primary result plus auxiliary outputs).
  - Short-circuit on error while preserving prior step results.
- Support multiple entry points:
  - IR file path.
  - Workspace root (morphir.toml / morphir.json).
  - Raw IR bytes (for integration).
- Support JSON output for non-interactive commands.
- Maintain strict stdout/stderr separation:
  - stdout: pipeline results and JSON output.
  - stderr: diagnostics, progress, and errors.
- Support targets (build/test/clean) that orchestrate pipelines and tasks.

## Non-Functional Requirements

- Deterministic and reproducible results.
- Minimal global state and no hidden mutation.
- Clear, stable interfaces for CLI integration.
- Testable steps with table-driven unit tests.
- Extensible to new targets and IR versions.
- Enforce mount precedence with read-only and read-write boundaries.

## Interfaces and Outputs

- Provide a pipeline result object containing:
  - Output value.
  - Diagnostics list.
  - Artifact list.
  - Execution metadata (timing, step list).
- Provide a JSON schema for pipeline results to enable `--json`.
- Provide VEntry and VFS APIs that allow safe traversal and transformation.

## Constraints

- Follow functional programming principles (immutability, pure functions).
- Keep IR models free of JSON encoding assumptions.
- Avoid new dependencies that require network access in core packages.

## Open Questions

- What is the minimal standard set of pipeline steps for v1?
- How should pipeline results surface partial progress on failure?
- Should step-level caching be modeled in v1 types or deferred?
