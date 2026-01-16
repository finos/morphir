---
title: "Design Pivot: Toolchain to Tasks"
sidebar_label: Design Pivot
sidebar_position: 2
---

# Design Pivot: Toolchain Integration to Simple Tasks

**Date:** 2026-01-16
**Status:** Active
**Affects:** Toolchain framework, workflow configuration, tool acquisition

## Summary

The Morphir project is pivoting from the comprehensive Toolchain Integration Framework to a simplified task system modeled after [mise tasks](https://mise.jdx.dev/tasks/). This document explains the rationale, what changes, what remains, and migration guidance.

## Rationale

### Problems with the Toolchain Framework

1. **Complexity**: The framework introduced four distinct abstractions (toolchains, targets, tasks, workflows) that all needed to be understood together.

2. **Configuration Burden**: Defining a new toolchain required extensive configuration:
   ```toml
   # Old approach - verbose configuration
   [toolchain.morphir-elm]
   name = "morphir-elm"
   version = "2.90.0"
   acquire.backend = "npx"
   acquire.package = "morphir-elm"
   acquire.version = "^2.90.0"
   env.NODE_OPTIONS = "--max-old-space-size=4096"

   [toolchain.morphir-elm.tasks.make]
   exec = "morphir-elm"
   args = ["make", "-o", "{outputs.ir}"]
   inputs = ["elm.json", "src/**/*.elm"]
   outputs = { ir = { path = "morphir-ir.json", type = "morphir-ir" } }
   fulfills = ["make"]
   ```

3. **Implementation Scope**: Full implementation required:
   - Tool acquisition backends (npx, npm, mise, dotnet-tool)
   - Artifact type system and validation
   - Workflow inheritance and merging
   - Execution plan computation
   - Cache invalidation based on input hashing

4. **Over-Engineering for Current Needs**: Most users need simple build automation, not a comprehensive build system.

### Benefits of the New Approach

1. **Simplicity**: Tasks are shell commands. Pre/post hooks extend built-in behavior.
   ```toml
   # New approach - simple
   [tasks."post:build"]
   run = "prettier --write .morphir-dist/"
   ```

2. **Built-in Operations**: Core tasks (build, test, codegen) work automatically without configuration.

3. **Familiar Model**: Follows mise's well-documented task pattern.

4. **Extension via WASM**: Complex toolchain integration uses WASM Component Model for proper isolation and capability management.

## What Changes

### Removed Concepts

| Concept | Replacement |
|---------|-------------|
| Toolchain definitions | Built-in tasks + WASM extensions |
| Target abstraction | Direct task names |
| Workflow stages | Task dependencies |
| Tool acquisition backends | User manages tool installation |
| Artifact type system | Simple file-based outputs |

### Configuration Changes

**Before (Toolchain Framework):**
```toml
[toolchains.morphir-elm]
enabled = true
acquire.backend = "npx"

[toolchains.morphir-elm.tasks.make]
exec = "morphir-elm"
args = ["make"]
fulfills = ["make"]

[workflows.build]
stages = [
  { name = "compile", targets = ["make"] },
  { name = "generate", targets = ["gen:scala"] },
]
```

**After (Simple Tasks):**
```toml
# Built-in tasks work automatically
# Only define custom tasks or hooks

[tasks.ci]
description = "Run CI pipeline"
depends = ["check", "test", "build"]

[tasks."post:build"]
run = "prettier --write .morphir-dist/"
```

## What Remains

### VFS and Pipeline Types

The VFS (Virtual Filesystem) and pipeline core types remain relevant:
- `VEntry`, `VPath`, filesystem abstraction
- Pipeline composition helpers
- Streaming JSONL processing

These support the simplified task execution engine.

### Task Execution Engine

The core task execution capability continues, but simplified:
- Execute shell commands
- Handle task dependencies
- Capture stdout/stderr
- Support environment variables

The middleware/hook system for execution stages (RESOLVE → CACHE → PREPARE → EXECUTE → COLLECT → REPORT) is simplified to pre/post hooks.

### Intrinsic Tasks

Built-in tasks for core operations:
- `build` - Compile to IR
- `test` - Run tests
- `check` - Lint and validate
- `codegen` - Generate target code
- `pack` - Create distributable package
- `publish` - Publish to registry

### WASM Extension Model

Complex toolchain integration moves to WASM Component Model:
- Extensions register capabilities via WIT interfaces
- Proper isolation and sandboxing
- Can provide additional intrinsic tasks
- Protocol-based communication (JSON-RPC)

## Migration Guide

### For Users

1. **Remove toolchain configuration**: Delete `[toolchains.*]` and `[workflows.*]` sections.

2. **Use built-in tasks**: Most operations work without configuration.

3. **Add hooks for customization**:
   ```toml
   [tasks."post:build"]
   run = "./scripts/post-build.sh"
   ```

4. **Manage tools externally**: Install tools via npm, mise, or package manager.

### For Implementers

1. **Task execution**: Simplify to shell command execution with dependencies.

2. **Extensions**: Implement complex integrations as WASM components.

3. **VFS usage**: Continue using VFS for file operations and sandboxing.

## Affected GitHub Issues

The following issues are closed as "will not do":

| Issue | Title | Reason |
|-------|-------|--------|
| #498 | Epic: Toolchain Integration Framework | Framework superseded |
| #496 | Toolchain Integration: Phase 5 - Caching & Performance | Deferred to simpler approach |
| #497 | Toolchain Integration: Phase 6 - Polish & Ecosystem | Framework superseded |
| #537 | Toolchain: Add integration tests for workflow execution | Workflows removed |
| #536 | Toolchain: Add integration tests for morphir-elm gen variants | Simplified approach |

## Related Work That Continues

- **VFS core types** (morphir-go-765): Still needed
- **Pipeline composition** (morphir-go-766): Still needed
- **Task execution** (morphir-go-772): Continues with simplified scope

## Future Considerations

1. **WASM Extensions**: As the WASM Component Model matures, extensions can provide rich toolchain-like capabilities.

2. **Tool Acquisition**: May revisit integrated tool management if user demand warrants.

3. **Caching**: Simple input-based caching may be added to tasks without the full artifact type system.

## References

- [Tasks Design](../draft/configuration/tasks.md) - New task system
- [WASM Components](../draft/vfs-protocol/wasm-component.md) - Extension model
- [mise tasks](https://mise.jdx.dev/tasks/) - Inspiration for new approach
