# Toolchain Integration Framework Design

**Status:** Draft
**Authors:** Morphir Team
**Created:** 2026-01-08
**Epic:** morphir-pfi

## Overview

This document describes the design of Morphir's Toolchain Integration Framework, which enables orchestration of external tools (like `morphir-elm`) through a flexible, composable abstraction.

### Goals

1. **Polyglot Integration**: Support tools from any ecosystem (npm, dotnet, native binaries)
2. **Unified CLI**: Present a consistent interface regardless of underlying toolchain
3. **Composable Workflows**: Enable complex build pipelines from simple building blocks
4. **Inspectability**: Users can understand and debug what will happen before execution
5. **Extensibility**: Third-party toolchains can integrate seamlessly

### Non-Goals (for initial version)

- LSP/MCP/BSP/gRPC communication protocols (future)
- Distributed/remote execution (future)
- Fine-grained incremental compilation (future)

## Core Concepts

### Conceptual Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│  CLI Commands                                                   │
│  morphir make | morphir build | morphir gen:scala              │
├─────────────────────────────────────────────────────────────────┤
│  Workflows (named orchestrations)                               │
│  build, ci, release, custom workflows...                       │
├─────────────────────────────────────────────────────────────────┤
│  Targets (capabilities)                                         │
│  make, gen, test, validate, format...                          │
├─────────────────────────────────────────────────────────────────┤
│  Tasks (toolchain implementations)                              │
│  morphir-elm/make, morphir-elm/gen, morphir-native/validate    │
├─────────────────────────────────────────────────────────────────┤
│  Toolchains (provide tasks)                                     │
│  morphir-elm, morphir-native, custom toolchains                │
└─────────────────────────────────────────────────────────────────┘
```

### Toolchains

A **toolchain** is both an external tool adapter AND a capability provider. It:

- Declares how to acquire and invoke external tools
- Registers tasks that fulfill targets
- Can hook into task execution lifecycle (middleware pattern)

```toml
[toolchain.morphir-elm]
name = "morphir-elm"
version = "2.90.0"

# Acquisition
acquire.backend = "npx"           # or "npm", "mise", "dotnet-tool", "path"
acquire.package = "morphir-elm"
acquire.version = "^2.90.0"

# Environment
env.NODE_OPTIONS = "--max-old-space-size=4096"
working_dir = "."
timeout = "5m"

# Tasks provided
[toolchain.morphir-elm.tasks.make]
exec = "morphir-elm"
args = ["make", "-o", "{outputs.ir}"]
inputs = ["elm.json", "src/**/*.elm"]
outputs = { ir = { path = "morphir-ir.json", type = "morphir-ir" } }
fulfills = ["make"]

[toolchain.morphir-elm.tasks.gen]
exec = "morphir-elm"
args = ["gen", "-i", "{inputs.ir}", "-o", "{outputs.dir}", "-t", "{variant}"]
inputs = { ir = "@morphir-elm/make:ir" }
outputs = { dir = "dist/{variant}/**/*" }
fulfills = ["gen"]
variants = ["Scala", "JsonSchema", "TypeScript"]
```

### Targets

A **target** is a CLI-facing capability that tasks fulfill. Targets:

- Have well-known names that map to CLI commands
- Declare artifact contracts (what they produce/require)
- Support variants (e.g., `gen:scala`, `gen:typescript`)

```toml
[targets.make]
description = "Compile sources to Morphir IR"
produces = ["morphir-ir"]

[targets.gen]
description = "Generate code from IR"
requires = ["morphir-ir"]
produces = ["generated-code"]
variants = ["scala", "json-schema", "typescript"]

[targets.validate]
description = "Validate IR structure"
requires = ["morphir-ir"]
produces = ["diagnostics"]
```

**Target Resolution:**
- `morphir make` → find task(s) fulfilling "make" target
- `morphir gen:scala` → find task(s) fulfilling "gen" with variant "scala"
- Multiple providers → `morphir doctor` advises, project config can pin

### Tasks

A **task** is a concrete implementation provided by a toolchain. Tasks:

- Execute external processes or native Go code
- Declare inputs (files, artifact references)
- Produce outputs to `.morphir/out/{toolchain}/{task}/`
- Can be cached based on input hashes

**Input References:**
```toml
# File glob patterns
inputs = ["src/**/*.elm", "elm.json"]

# Task output references (logical)
inputs = { ir = "@morphir-elm/make:ir" }

# Mixed
inputs = {
  sources = "src/**/*.elm",
  ir = "@morphir-elm/make:ir"
}
```

### Workflows

A **workflow** composes targets into named, staged orchestrations. Workflows:

- Define explicit stages with names
- Can run targets in parallel within stages
- Support conditions for conditional execution
- Can extend other workflows (inheritance)

```toml
[workflows.build]
description = "Standard build workflow"
stages = [
  { name = "frontend", targets = ["make"] },
  { name = "backend", targets = ["gen:scala"] },
]

[workflows.ci]
description = "CI pipeline with validation"
stages = [
  { name = "compile", targets = ["make"] },
  { name = "validate", targets = ["validate"], parallel = true },
  { name = "generate", targets = ["gen:scala"] },
  { name = "test", targets = ["test"] },
]

[workflows.release]
description = "Full release workflow"
extends = "ci"
stages = [
  { name = "package", targets = ["package"] },
  { name = "publish", targets = ["publish"], condition = "branch == 'main'" },
]
```

**Workflow Inheritance:**
```
┌─────────────────────────────────────────────────────┐
│  Project workflows (morphir.toml)                   │
│    extends = "@morphir-elm/elm-standard"            │
├─────────────────────────────────────────────────────┤
│  Toolchain workflows (morphir-elm)                  │
│    extends = "@morphir/default-build"               │
├─────────────────────────────────────────────────────┤
│  Built-in defaults (morphir core)                   │
│    build, test, check, clean, ...                   │
└─────────────────────────────────────────────────────┘
```

## Execution Model

### Execution Plan

The system computes an **execution plan** by merging workflow stages with target dependencies:

```
┌─────────────────┐     ┌─────────────────┐
│  Workflow Order │     │  Target Deps    │
│  (stages)       │  +  │  (requires/     │
│                 │     │   produces)     │
└────────┬────────┘     └────────┬────────┘
         │                       │
         └───────────┬───────────┘
                     ▼
         ┌───────────────────────┐
         │   Execution Plan      │
         │  - Validated          │
         │  - Optimized          │
         │  - Inspectable        │
         └───────────────────────┘
```

**Plan Features:**
- **Validation**: Catches workflow/dependency conflicts before execution
- **Optimization**: Identifies parallelization opportunities
- **Caching**: Skips tasks with unchanged inputs
- **Persistence**: Cached to `.morphir/out/plan.json`, optionally committable

### Plan Commands

```bash
# Show execution plan
morphir plan build

# Show optimized plan with parallelization
morphir plan ci --optimize

# Explain why a specific task runs
morphir plan ci --explain gen:scala

# Export plan as JSON
morphir plan ci --output plan.json
```

**Example Output:**
```
$ morphir plan ci

Execution Plan for workflow "ci":
┌─────────────────────────────────────────────────────────────────┐
│ Stage: compile                                                  │
│   └── morphir-elm/make                                          │
│       ├── inputs: src/**/*.elm, elm.json                        │
│       └── outputs: .morphir/out/morphir-elm/make/ir.json        │
├─────────────────────────────────────────────────────────────────┤
│ Stage: validate (parallel)                                      │
│   └── morphir-native/validate                                   │
│       └── inputs: @morphir-elm/make:ir                          │
├─────────────────────────────────────────────────────────────────┤
│ Stage: generate                                                 │
│   └── morphir-elm/gen [variant: scala]                          │
│       └── inputs: @morphir-elm/make:ir                          │
└─────────────────────────────────────────────────────────────────┘

Cache status: make (cached), validate (stale), gen (pending)
```

### Task Execution Lifecycle

Each task executes through a pipeline with hook points:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Task Execution Pipeline                      │
├─────────────────────────────────────────────────────────────────┤
│  RESOLVE → CACHE → PREPARE → EXECUTE → COLLECT → REPORT        │
│     ↑        ↑        ↑         ↑         ↑         ↑          │
│     │        │        │         │         │         │          │
│  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐  ┌───┴───┐  ┌──┴──┐  ┌───┴───┐     │
│  │hook │  │hook │  │hook │  │ hook  │  │hook │  │ hook  │     │
│  │chain│  │chain│  │chain│  │ chain │  │chain│  │ chain │     │
│  └─────┘  └─────┘  └─────┘  └───────┘  └─────┘  └───────┘     │
└─────────────────────────────────────────────────────────────────┘
```

**Stages:**
1. **RESOLVE**: Find toolchain, check tool acquired, resolve input artifacts
2. **CACHE**: Hash inputs, check for cache hit in `.morphir/out/`
3. **PREPARE**: Run pre-task hooks, create output directory, set up environment
4. **EXECUTE**: Spawn process, capture output, stream diagnostics
5. **COLLECT**: Gather artifacts, write meta.json, run post-task hooks
6. **REPORT**: Report success/failure, aggregate diagnostics

**Middleware Pattern:**
Toolchains can inject handlers at any stage to modify context, add behavior, or short-circuit execution.

## Artifact Model

### Output Structure

All task outputs go to a structured directory:

```
.morphir/
├── cache/                          # Download cache (tools, dependencies)
└── out/                            # Task outputs (namespaced)
    ├── morphir-elm/
    │   ├── make/
    │   │   ├── meta.json           # Task metadata
    │   │   ├── ir.json             # Actual output (JSONC)
    │   │   └── diagnostics.jsonl   # Warnings/errors (JSONL)
    │   └── gen/
    │       ├── scala/
    │       │   ├── meta.json
    │       │   └── output/         # Generated files
    │       └── json-schema/
    │           └── ...
    └── morphir-native/
        └── validate/
            ├── meta.json
            └── diagnostics.jsonl
```

### Artifact Formats

| Type | Format | Use |
|------|--------|-----|
| Task outputs | JSONC | Human-readable, supports comments |
| Diagnostics | JSONL/NDJSON | Streaming errors, warnings, progress |
| Metadata | JSON | `meta.json` with inputs_hash, duration, etc. |
| Plan | JSON | `plan.json` for caching and export |

### Artifact References

Tasks reference artifacts using logical paths that the VFS resolves:

```toml
# Reference another task's output
inputs = { ir = "@morphir-elm/make:ir" }

# System resolves to: .morphir/out/morphir-elm/make/ir.json
```

**Artifact Typing:**
```toml
outputs = {
  ir = { path = "morphir-ir.json", type = "morphir-ir/v3" }
}

inputs = {
  ir = { ref = "@morphir-elm/make:ir", type = "morphir-ir/v3" }
}
```

Type compatibility is validated at plan time with auto-detection support.

## Tool Acquisition

### Acquisition Backends

| Backend | Description | Priority |
|---------|-------------|----------|
| `path` | Tool already on PATH | Immediate |
| `npx` | Run via npx (avoids global install conflicts) | Near-term |
| `npm` | Install via npm | Near-term |
| `mise` | Manage via mise | Near-term |
| `dotnet-tool` | Install via dotnet tool | Future |
| `binary` | Download pre-built binary | Future |

### Acquisition Configuration

```toml
[toolchain.morphir-elm.acquire]
backend = "npx"
package = "morphir-elm"
version = "^2.90.0"

# Or for path-based
[toolchain.custom-tool.acquire]
backend = "path"
executable = "my-custom-tool"
```

### Environment Configuration

```toml
[toolchain.morphir-elm]
# Additional PATH entries
path = ["./node_modules/.bin"]

# Environment variables
env.NODE_OPTIONS = "--max-old-space-size=4096"

# Working directory (relative to project root)
working_dir = "."

# Resource limits
timeout = "5m"
```

## CLI Integration

### Command Mapping

```bash
# Run targets directly
morphir make              # Run "make" target
morphir gen:scala         # Run "gen" target with variant "scala"
morphir validate          # Run "validate" target

# Run workflows
morphir build             # Run "build" workflow
morphir ci                # Run "ci" workflow

# Plan commands
morphir plan build        # Show execution plan
morphir plan --explain X  # Explain why task X runs

# Doctor
morphir doctor            # Check for issues, ambiguities
```

### Target Variants

Variants use colon syntax:
```bash
morphir gen:scala
morphir gen:typescript
morphir gen:json-schema
```

### Disambiguation

When multiple toolchains provide a target:
```bash
$ morphir make
WARNING: Multiple toolchains fulfill "make": morphir-elm, morphir-haskell
Run `morphir doctor` for advice, or set targets.make in morphir.toml
```

## Configuration

### Toolchain Definition Locations

1. **Built-in** (lowest precedence): Embedded in Morphir binary
2. **Toolchain packages**: Distributed with toolchains
3. **User global**: `~/.config/morphir/morphir.toml`
4. **Project**: `morphir.toml` (highest precedence)

### Example Project Configuration

```toml
[project]
name = "my-morphir-project"

# Pin target implementations
[project.targets]
make = "@morphir-elm/make"
gen = "@morphir-elm/gen"

# Toolchain configuration
[toolchain.morphir-elm]
version = "2.90.0"
acquire.backend = "npx"

# Custom workflow
[workflows.deploy]
extends = "build"
stages = [
  { name = "upload", targets = ["@my-toolchain/deploy-s3"] },
]

# Custom target
[targets.deploy-s3]
description = "Deploy to S3"
requires = ["generated-code"]
```

## Diagnostics & Error Handling

### Error Ownership

The **task system** owns error reporting. Toolchains contribute diagnostics in a structured format.

### Diagnostic Format (JSONL)

```jsonl
{"level": "error", "file": "src/Foo.elm", "line": 10, "col": 5, "message": "Type mismatch", "code": "E001"}
{"level": "warning", "file": "src/Bar.elm", "line": 20, "message": "Unused import"}
{"level": "info", "message": "Compiled 15 modules"}
```

### Diagnostic Sources

- **stderr**: Tool writes JSONL to stderr (preferred)
- **file**: Tool writes to `diagnostics.jsonl` (fallback)
- **stdout**: Captured and wrapped if unstructured

Diagnostics are tee'd by default (both displayed and saved to file), configurable via settings.

### Doctor Command

```bash
$ morphir doctor

Checking toolchain configuration...
✓ morphir-elm: version 2.90.0 (via npx)
✓ morphir-native: built-in

Checking target resolution...
⚠ Target "gen" has multiple providers:
  - morphir-elm/gen (variants: scala, json-schema, typescript)
  - custom-toolchain/gen (variants: spark)
  Suggestion: Pin in morphir.toml: targets.gen = "@morphir-elm/gen"

Checking workflows...
✓ build: valid
✓ ci: valid
✗ release: invalid
  - Stage "publish" depends on target "package" which is not defined

Suggestions:
  1. Define target "package" or remove stage "publish"
  2. Run `morphir plan release` for detailed dependency analysis
```

## Implementation Phases

### Phase 1: Foundation
- [ ] Core types: Toolchain, Target, Task, Workflow
- [ ] Configuration loading for toolchains
- [ ] Basic task execution (path backend only)
- [ ] Output directory structure

### Phase 2: morphir-elm Integration
- [ ] NPX acquisition backend
- [ ] morphir-elm toolchain definition
- [ ] `make` and `gen` task implementations
- [ ] File-based artifact passing

### Phase 3: Workflows & Planning
- [ ] Workflow definition and parsing
- [ ] Execution plan computation
- [ ] Plan validation and optimization
- [ ] `morphir plan` command

### Phase 4: Caching & Performance
- [ ] Input hashing
- [ ] Cache hit/miss detection
- [ ] Plan caching
- [ ] Parallel execution within stages

### Phase 5: Polish & Ecosystem
- [ ] `morphir doctor` command
- [ ] Additional acquisition backends (mise, npm)
- [ ] Workflow inheritance
- [ ] Diagnostic aggregation

## Related Documents

- [ADR-0002: Processing Pipeline](adr/ADR-0002-processing-pipeline.md)
- [Processing Pipeline Design](processing-pipeline-design.md)
- [Configuration Guide](configuration.md)

## Open Questions

1. **Plan lock file format**: Should `morphir.lock` include resolved tool versions?
2. **Remote caching**: Should we support shared caches (like Bazel/Turborepo)?
3. **Plugin distribution**: How should third-party toolchains be distributed?
4. **Streaming large artifacts**: How to handle artifacts too large for JSONC?

## Appendix: Comparison with Other Tools

| Feature | Morphir | Mill | Bazel | Make | Turborepo |
|---------|---------|------|-------|------|-----------|
| Task caching | Yes | Yes | Yes | No | Yes |
| Execution plan | Yes | Yes | Yes | No | No |
| Polyglot | Yes | JVM | Yes | Yes | JS |
| Artifact typing | Yes | Yes | Yes | No | No |
| Workflow inheritance | Yes | No | No | No | No |
| Tool acquisition | Yes | No | Yes | No | No |
