---
id: golang-backend-requirements
title: Morphir Golang Backend Requirements
---

# Morphir Golang Backend Requirements

## Summary

This document captures requirements for adding a Morphir backend that generates Go
modules or multi-module workspaces from Morphir IR. The backend should integrate
with the existing make/build/gen workflow, starting with the current pipeline
patterns used by the WIT binding and evolving as the broader pipeline integration
work lands.

## Goals

- Provide a Go backend that converts Morphir IR into a Go module or workspace.
- Align with Morphir IR specification and existing binding patterns (WIT pipeline).
- Support an MVP implementation that can be iterated as integration design evolves.
- Keep the backend focused on generation (IR -> Go) while enabling validation
  and round-trip workflows later.

## Non-Goals (MVP)

- Full runtime support or execution framework for generated Go code.
- Comprehensive Go packaging policy (beyond module/workspace scaffolding).
- Code formatting or linting enforcement (can be handled by downstream tools).
- Advanced incremental build/caching (defer to pipeline improvements).

## Scope and Phasing

### Phase 1 (MVP)

- Introduce a new Go module for the backend at `pkg/bindings/golang`.
- Implement the backend pipeline steps for:
  - `gen`: IR -> Go module/workspace generation.
  - `make`: initial placeholder for source -> IR if needed for parity with WIT.
  - `build`: orchestration of make + gen with simple validation hooks.
- Expose CLI commands aligned with current patterns:
  - `morphir golang make`
  - `morphir golang gen`
  - `morphir golang build`
- Generate a single-module Go project by default with optional multi-module
  workspace output (go.work + per-module go.mod).

### Phase 2 (Follow-on)

- Integrate with revised make/build/gen architecture when available.
- Add IR decorators for Go-specific metadata (package naming, module mapping).
- Expand source-to-IR support if a Go frontend is introduced.
- Improve diagnostics and partial-success reporting.

## Functional Requirements

- Accept Morphir IR input from:
  - IR JSON file.
  - Loaded workspace (root or member project).
- Generate a Go module or multi-module workspace with:
  - `go.mod` files per module.
  - `go.work` at workspace root when multi-module output is requested.
  - Package structure that preserves Morphir module paths.
- Provide deterministic output for identical IR input.
- Emit structured diagnostics (warnings and errors) without writing to stdout
  except for actual command output.
- Support JSON output for non-interactive CLI commands (`--json`).
- Allow configuration of output target paths.

## Non-Functional Requirements

- Pure, composable functions for core transformations.
- Isolated I/O boundaries for file generation.
- Table-driven unit tests for module/workspace layout logic.
- Align with existing `pkg/bindings/wit/pipeline` step patterns to enable
  future convergence.

## Test Plan

This backend must be delivered with unit, BDD, and acceptance tests. Tests should
focus on deterministic output, diagnostics, and workspace layout correctness.

### Unit Tests

- IR -> Go module layout mapping:
  - Morphir package/module path -> Go package path rules.
  - File naming and directory structure for module output.
- Go module/workspace scaffolding:
  - Single-module `go.mod` generation.
  - Multi-module workspace `go.work` + per-module `go.mod` generation.
- Diagnostics:
  - Missing/invalid IR surfaces errors with codes.
  - Warnings for lossy or unsupported mappings.
- Pipeline step behavior:
  - `gen` step returns artifacts and diagnostics without writing to stdout.
  - `make`/`build` steps short-circuit on errors but preserve prior diagnostics.

### BDD Tests

Add BDD scenarios under `tests/bdd` that mirror the existing patterns used by WIT:

- Scenario: Generate a Go module from a simple IR fixture
  - Given a small IR fixture with one package and one module
  - When I run `morphir golang gen`
  - Then the output directory contains `go.mod` and expected package files
- Scenario: Generate a multi-module workspace
  - Given an IR fixture with multiple packages
  - When I run `morphir golang gen --workspace`
  - Then a `go.work` file exists with correct module references
- Scenario: Diagnostics surface warnings for unsupported mappings
  - Given an IR fixture with unsupported constructs
  - When I run `morphir golang gen --json`
  - Then the JSON output includes warning diagnostics with codes

### Acceptance Tests

Acceptance tests should validate CLI behavior end-to-end, including JSON output
and file generation. These can be implemented as BDD scenarios or standalone
tests that execute the CLI:

- `morphir golang gen` produces a runnable Go module:
  - `go.mod` exists with correct module path.
  - Generated Go files compile (`go test ./...` in generated output).
- `morphir golang gen --workspace` produces a valid `go.work`:
  - `go work use` entries reference generated modules.
  - Modules compile independently with `go test ./...`.
- `morphir golang build` integrates make + gen:
  - Reports diagnostics to stderr.
  - Emits JSON result to stdout when `--json` is set.

## Integration Notes

- The WIT binding already implements make/gen/build steps. The Golang backend
  should follow the same interface shape and diagnostics conventions.
- Planned changes to the make/build/gen integration will be addressed after
  the MVP lands; the backend should be written to minimize refactors (e.g., keep
  step inputs/outputs and diagnostics in dedicated types).

## Open Questions

- Final CLI command naming (`golang` vs `go`).
- How to map Morphir package names to Go module paths by default.
- How to handle multiple Morphir packages in a single workspace (module-per-package
  vs shared module).
- What the minimal Go codegen surface should be for MVP (types only vs types +
  functions + stubs).
