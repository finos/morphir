# Toolchain Enablement and Target Resolution Design

This document captures the design decisions for how toolchains are enabled and how targets are resolved to tasks in workflows.

## Overview

The Morphir toolchain framework supports multiple toolchains (morphir-elm, golang, wit, etc.) that can provide tasks fulfilling common targets (make, gen, validate). This design addresses how toolchains are enabled for a project and how workflows resolve targets to executable tasks.

## Design Decisions

### 1. Toolchain Enablement

Toolchains can be enabled through two mechanisms:

**Auto-detection**: Each toolchain declares an `AutoEnable` predicate function during registration that determines if the toolchain should be automatically enabled based on project context.

```go
type Toolchain struct {
    // ... existing fields

    // AutoEnable predicate - returns true if toolchain should be
    // auto-enabled for the given project path
    AutoEnable func(projectPath string) bool
}
```

Example for morphir-elm:
```go
AutoEnable: func(path string) bool {
    _, err1 := os.Stat(filepath.Join(path, "elm.json"))
    _, err2 := os.Stat(filepath.Join(path, "morphir.json"))
    return err1 == nil && err2 == nil
}
```

**Explicit configuration**: Users can explicitly enable or disable toolchains in `morphir.toml`. Explicit configuration always overrides auto-detection.

```toml
[toolchain.morphir-elm]
enabled = true   # explicitly enable

[toolchain.wit]
enabled = false  # explicitly disable
```

If `enabled` is omitted, the auto-detection predicate is used.

### 2. Target Resolution

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

### 3. Direct Task References

Users can bypass target resolution by using the `toolchain/task` syntax:

```toml
[[workflows.build.stages]]
name = "compile"
targets = ["morphir-elm/make"]  # direct reference
```

The parser checks for `/` in the target spec:
- Contains `/` → direct task reference (e.g., `morphir-elm/make`)
- No `/` → target resolution (e.g., `make`)

Direct task references still require the referenced toolchain to be enabled.

### 4. Execution Order

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
[toolchain.morphir-elm]
enabled = true

[toolchain.golang]
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

## Implementation Status

- [ ] Add `AutoEnable` field to `Toolchain` struct
- [ ] Implement auto-enable predicates for built-in toolchains
- [ ] Add `enabled` config parsing
- [ ] Update plan builder to filter by enabled toolchains
- [ ] Update plan builder to run ALL matching tasks (not fail on multiple)
- [ ] Implement direct task reference parsing (`toolchain/task` syntax)
- [ ] Update BDD tests for new behavior
