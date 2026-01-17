---
title: Deprecated Designs
sidebar_label: Overview
sidebar_position: 1
---

# Deprecated Designs

This folder contains design documents for approaches that have been superseded or abandoned. These documents are preserved for historical reference and to document decision-making rationale.

## Toolchain Integration Framework (Superseded)

**Status:** Superseded by simplified task system
**Date Deprecated:** 2026-01-16
**Superseded By:** [Tasks](../draft/configuration/tasks.md)

The original Toolchain Integration Framework was a comprehensive system for:
- External tool orchestration (morphir-elm, mise, npm tools)
- Native Go toolchain adapters
- Complex workflow definitions with stages
- Target/task abstraction layer
- Tool acquisition backends (npx, npm, mise, dotnet-tool)

### Why Superseded

The framework introduced significant complexity:
1. **Multiple abstractions**: Toolchains, targets, tasks, and workflows were separate concepts requiring understanding of all layers
2. **Configuration overhead**: Defining toolchains required extensive TOML configuration
3. **Implementation burden**: The framework required substantial code for tool acquisition, artifact management, and workflow orchestration

### New Approach

The simplified task system follows [mise's task model](https://mise.jdx.dev/tasks/):
- **Built-in tasks**: Core operations (build, test, codegen) work automatically
- **User tasks**: Simple shell commands defined in `[tasks]`
- **Pre/post hooks**: Extend built-in commands with `pre:` and `post:` prefixes
- **Extensions**: Complex toolchain integration uses WASM Component Model

### Documents in This Section

| Document | Original Purpose |
|----------|------------------|
| [toolchain-integration-design.md](./toolchain-integration-design.md) | Full framework design |
| [toolchain-enablement.md](./toolchain-enablement.md) | Auto-enable and target resolution |
| [ADR-0003-toolchain-integration.md](./ADR-0003-toolchain-integration.md) | Architecture decision record |

### Implications for Existing Work

Some implementation work was done on the toolchain framework:
- **VFS/Pipeline types**: Still relevant, used by the simplified system
- **Task execution engine**: Core execution remains, but simplified
- **Workflow configuration**: Replaced by simple task dependencies
- **Tool acquisition**: Deferred; users manage tool installation

See [Design Pivot: Toolchain to Tasks](./design-pivot-toolchain-to-tasks.md) for migration guidance.
