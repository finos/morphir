# Toolchain Enablement and Target Resolution Design

This document captures the design decisions for how toolchains are enabled and how targets are resolved to tasks in workflows.

## Overview

The Morphir toolchain framework supports multiple toolchains (morphir-elm, golang, wit, etc.) that can provide tasks fulfilling common targets (make, gen, validate). This design addresses how toolchains are enabled for a project and how workflows resolve targets to executable tasks.

## Design Decisions

### 1. Toolchain Enablement

Toolchains can be enabled through two mechanisms:

**Auto-detection**: Each toolchain declares an `AutoEnable` predicate function during registration that determines if the toolchain should be automatically enabled based on project context. The predicate receives an `AutoEnableContext` with VFS access for portable file detection.

```go
// AutoEnableContext provides context for toolchain auto-enable detection.
type AutoEnableContext struct {
    // VFS is the virtual filesystem for checking file existence
    VFS vfs.VFS

    // ProjectRoot is the root path of the project in the VFS
    ProjectRoot vfs.VPath
}

// Helper methods available on AutoEnableContext:
// - FileExists(relativePath string) bool
// - HasAllFiles(relativePaths ...string) bool
// - HasAnyFile(relativePaths ...string) bool
// - HasMatchingFiles(pattern string) bool
// - HasAnyMatchingFiles(patterns ...string) bool

type Toolchain struct {
    // ... existing fields

    // AutoEnable is a predicate that determines if this toolchain should be
    // auto-enabled based on project context. If nil, the toolchain is not
    // auto-enabled (requires explicit configuration).
    AutoEnable func(ctx AutoEnableContext) bool
}
```

**Built-in toolchain auto-enable predicates:**

| Toolchain | Auto-enables when |
|-----------|-------------------|
| morphir-elm | `elm.json` OR `morphir.json` exists |
| golang | `go.mod` OR `go.work` exists |
| wit | Any `*.wit` or `**/*.wit` files exist |

Example implementation for morphir-elm:
```go
AutoEnable: func(ctx toolchain.AutoEnableContext) bool {
    return ctx.HasAnyFile("elm.json", "morphir.json")
}
```

**Explicit configuration**: Users can explicitly enable or disable toolchains in `morphir.toml`. Explicit configuration always overrides auto-detection.

```toml
[toolchains.morphir-elm]
enabled = true   # explicitly enable

[toolchains.wit]
enabled = false  # explicitly disable (even if *.wit files exist)
```

If `enabled` is omitted, the auto-detection predicate is used. If the toolchain has no `AutoEnable` predicate and no explicit config, it is not enabled.

### 2. EnablementConfig

The `EnablementConfig` type combines explicit configuration with auto-enable context:

```go
type EnablementConfig struct {
    // ExplicitEnabled maps toolchain names to their explicit enabled state.
    // If a toolchain is not in this map, auto-detection is used.
    ExplicitEnabled map[string]bool

    // AutoEnableCtx is the context for auto-enable detection.
    // If nil, auto-enable predicates are not evaluated.
    AutoEnableCtx *AutoEnableContext
}
```

The `Registry.IsEnabled()` method checks enablement:
1. First checks `ExplicitEnabled` map for explicit true/false
2. Falls back to evaluating the toolchain's `AutoEnable` predicate
3. Returns false if no predicate and no explicit config

### 3. Target Resolution

When a workflow stage specifies targets:

```toml
[[workflows.build.stages]]
name = "compile"
targets = ["make"]
```

The planner:
1. Finds ALL tasks where `Fulfills` contains the target name ("make")
2. Filters to only tasks from ENABLED toolchains
3. Schedules all matching tasks for execution

This means `targets = ["make"]` could run `morphir-elm/make`, `golang/make`, and `wit/make` if all three toolchains are enabled.

### 4. Direct Task References

Users can bypass target resolution by using the `toolchain/task` syntax:

```toml
[[workflows.build.stages]]
name = "compile"
targets = ["morphir-elm/make"]  # direct reference
```

The parser detects direct task references by checking for `/` before any `:`:
- Contains `/` before `:` → direct task reference (e.g., `morphir-elm/make`, `morphir-elm/gen:scala`)
- No `/` → target resolution (e.g., `make`, `gen:scala`)

Direct task references:
- Still require the referenced toolchain to be enabled
- Support variants with `:variant` suffix (e.g., `morphir-elm/gen:scala`)
- Return an error if the toolchain or task doesn't exist

### 5. Execution Order

Task execution order is inferred from declared dependencies:

- Tasks declare input artifacts referencing other task outputs (e.g., `@morphir-elm/make:ir`)
- The planner builds a dependency graph and determines execution order
- Tasks with no dependency relationship can run in parallel

Example: If `golang/make` declares it needs `morphir-ir` output (produced by `morphir-elm/make`), then `morphir-elm/make` runs first.

## Configuration Examples

### Minimal (auto-detection)
```toml
[workflows.build]
[[workflows.build.stages]]
name = "compile"
targets = ["make"]  # runs all auto-enabled toolchains' make tasks
```

### Explicit toolchain control
```toml
[toolchains.morphir-elm]
enabled = true

[toolchains.golang]
enabled = false  # disable even if go.mod exists

[workflows.build]
[[workflows.build.stages]]
name = "compile"
targets = ["make"]  # only runs morphir-elm/make
```

### Direct task reference
```toml
[workflows.build]
[[workflows.build.stages]]
name = "compile"
targets = ["morphir-elm/make"]  # only this specific task
```

### Mixed targets and direct references
```toml
[workflows.build]
[[workflows.build.stages]]
name = "compile"
targets = ["make"]  # all enabled toolchains

[[workflows.build.stages]]
name = "generate"
targets = ["morphir-elm/gen:scala"]  # specific task with variant
```

## Implementation Status

- [x] Add `AutoEnableContext` type with VFS-based helpers
- [x] Add `AutoEnable` field to `Toolchain` struct
- [x] Implement auto-enable predicates for built-in toolchains (morphir-elm, golang, wit)
- [x] Add `enabled` config parsing in `ToolchainConfig`
- [x] Add `EnablementConfig` type and `Registry.IsEnabled()` method
- [x] Update plan builder to filter by enabled toolchains
- [x] Update plan builder to run ALL matching tasks (not fail on multiple)
- [x] Implement direct task reference parsing (`toolchain/task` syntax)
- [x] Add unit tests for auto-enable context helpers
- [x] Add unit tests for multi-toolchain target resolution
- [x] Add unit tests for direct task references
- [x] Update BDD scenarios for new behavior

## Key Files

| File | Purpose |
|------|---------|
| `pkg/toolchain/types.go` | `AutoEnableContext`, `EnablementConfig`, `Registry.IsEnabled()` |
| `pkg/toolchain/plan.go` | `resolveTasks()`, `resolveDirectTaskRef()`, `isDirectTaskRef()` |
| `pkg/config/config.go` | `ToolchainConfig.Enabled()` method |
| `cmd/morphir/cmd/plan.go` | `buildEnablementConfig()` function |
| `pkg/bindings/*/toolchain/toolchain.go` | Auto-enable predicates for each toolchain |
