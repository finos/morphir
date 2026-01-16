---
title: Tasks
sidebar_label: Tasks
sidebar_position: 4
---

# Tasks

This document defines the task system for Morphir, modeled after [mise tasks](https://mise.jdx.dev/tasks/).

## Overview

Morphir provides **built-in tasks** for common operations and allows **user-defined tasks** for custom workflows. Tasks are run via `morphir run <task>`.

### Built-in Tasks

Morphir and its extensions provide intrinsic tasks that work out of the box:

| Task | Description | Equivalent Command |
|------|-------------|-------------------|
| `build` | Compile project to IR | `morphir build` |
| `test` | Run tests | `morphir test` |
| `check` | Lint and validate | `morphir check` |
| `codegen` | Generate code for targets | `morphir codegen` |
| `clean` | Remove build artifacts | `morphir clean` |
| `pack` | Create distributable package | `morphir pack` |
| `publish` | Publish to registry | `morphir publish` |

```bash
# These all work without any configuration
morphir run build
morphir run test
morphir run codegen
```

### User-Defined Tasks

Users can define custom tasks or override built-in tasks:

```toml
# morphir.toml
[tasks]
# Custom task
integration = "./scripts/integration-tests.sh"

# Override built-in task
test = "morphir test && ./scripts/integration-tests.sh"
```

```bash
morphir run integration    # Custom task
morphir run test           # Runs overridden test task
```

### Extension-Provided Tasks

Extensions (via WASM components) can register additional intrinsic tasks:

```bash
# Tasks provided by a TypeScript codegen extension
morphir run codegen:typescript

# Tasks provided by a Scala codegen extension
morphir run codegen:scala
```

See [WASM Components](../vfs-protocol/wasm-component.md) for how extensions register tasks.

## Task Definition

### Inline Tasks

The simplest form is an inline command string:

```toml
[tasks]
lint = "morphir check --strict"
clean = "rm -rf .morphir dist/"
```

### Detailed Tasks

For more control, use the detailed table syntax:

```toml
[tasks.build]
description = "Build the project and generate TypeScript"
run = "morphir build && morphir codegen typescript"

[tasks.test]
description = "Run all tests"
run = [
    "morphir build",
    "morphir test",
    "./scripts/integration-tests.sh"
]
depends = ["lint"]
```

### Task Options

| Option | Type | Description |
|--------|------|-------------|
| `run` | string or string[] | Command(s) to execute |
| `description` | string | Description shown in `morphir run --list` |
| `depends` | string[] | Tasks to run before this task |
| `env` | table | Environment variables for the task |
| `dir` | string | Working directory (default: project root) |
| `sources` | string[] | File patterns that trigger rebuild |
| `outputs` | string[] | Expected output files |
| `hide` | bool | Hide from task listings |

## Task Dependencies

Tasks can depend on other tasks:

```toml
[tasks.lint]
run = "morphir check"

[tasks.test]
run = "morphir test"
depends = ["lint"]

[tasks.ci]
description = "Run full CI pipeline"
depends = ["lint", "test", "build"]
run = "echo 'CI complete'"
```

Dependencies run in order. If multiple dependencies have no interdependencies, they may run in parallel.

## Environment Variables

Set environment variables for tasks:

```toml
[tasks.test]
run = "morphir test"
env = { MORPHIR_LOG_LEVEL = "debug", CI = "true" }

[tasks.deploy]
run = "./scripts/deploy.sh"
env = { ENVIRONMENT = "production" }
```

## File-Based Tasks

For complex tasks, use external scripts in a `tasks/` or `.morphir/tasks/` directory:

```
my-project/
├── morphir.toml
├── tasks/
│   ├── build.sh
│   ├── deploy.sh
│   └── test.py
```

File-based tasks are automatically discovered and can include metadata:

```bash
#!/usr/bin/env bash
#MISE description="Build and package for release"
#MISE depends=["lint", "test"]

set -euo pipefail
morphir build --release
morphir pack
```

Reference file tasks in configuration:

```toml
[tasks.build]
file = "tasks/build.sh"

[tasks.deploy]
file = "tasks/deploy.sh"
env = { ENVIRONMENT = "production" }
```

## Pre/Post Hooks

Conventional `pre:` and `post:` task prefixes allow extending built-in Morphir commands:

```toml
[tasks."pre:build"]
description = "Run before morphir build"
run = "echo 'Starting build...'"

[tasks."post:build"]
description = "Run after morphir build"
run = [
    "cp .morphir-dist/morphir-ir.json dist/",
    "echo 'Build complete'"
]

[tasks."pre:test"]
run = "morphir build"

[tasks."post:codegen"]
run = "prettier --write generated/"
```

### Hook Execution Order

When running `morphir build`:

1. `pre:build` task (if defined)
2. Built-in `morphir build` command
3. `post:build` task (if defined)

### Available Hooks

| Hook | Triggered By |
|------|-------------|
| `pre:build` / `post:build` | `morphir build` |
| `pre:test` / `post:test` | `morphir test` |
| `pre:codegen` / `post:codegen` | `morphir codegen` |
| `pre:pack` / `post:pack` | `morphir pack` |
| `pre:publish` / `post:publish` | `morphir publish` |
| `pre:clean` / `post:clean` | `morphir clean` |

### Disabling Hooks

```bash
# Skip hooks for a single command
morphir build --no-hooks

# Skip specific hook
morphir build --skip-hook=pre:build
```

## Workspace Tasks

In workspaces, tasks can be defined at workspace or project level:

```toml
# workspace/morphir.toml
[workspace]
members = ["packages/*"]

[tasks]
# Workspace-level tasks available from anywhere
build-all = "morphir workspace build"
test-all = "morphir workspace test"
```

```toml
# workspace/packages/core/morphir.toml
[project]
name = "my-org/core"

[tasks]
# Project-specific tasks
benchmark = "./scripts/benchmark.sh"
```

### Running Workspace Tasks

```bash
# From workspace root
morphir run build-all

# From project directory (runs project task)
cd packages/core
morphir run benchmark

# Run workspace task from project directory
morphir run --workspace build-all
```

## Built-in Variables

Tasks have access to these environment variables:

| Variable | Description |
|----------|-------------|
| `MORPHIR_PROJECT_ROOT` | Project root directory |
| `MORPHIR_WORKSPACE_ROOT` | Workspace root (if in workspace) |
| `MORPHIR_PROJECT_NAME` | Current project name |
| `MORPHIR_TASK_NAME` | Name of the current task |
| `MORPHIR_CONFIG_DIR` | Directory containing morphir.toml |

```toml
[tasks.info]
run = "echo Building $MORPHIR_PROJECT_NAME from $MORPHIR_PROJECT_ROOT"
```

## Incremental Tasks

Use `sources` and `outputs` for incremental execution:

```toml
[tasks.codegen]
description = "Generate TypeScript (incremental)"
run = "morphir codegen typescript --output generated/"
sources = ["src/**/*.morphir", ".morphir-dist/**/*.json"]
outputs = ["generated/**/*.ts"]
```

The task only runs if sources are newer than outputs.

## CLI Reference

```bash
# List available tasks
morphir run --list

# Run a task
morphir run <task>

# Run with arguments (passed to task)
morphir run test -- --verbose

# Run multiple tasks
morphir run lint test build

# Dry run (show what would execute)
morphir run --dry-run build

# Force run (ignore incremental check)
morphir run --force codegen
```

## Examples

### CI Pipeline with Hooks

Since `build`, `test`, and `check` are built-in tasks, you only need to configure custom behavior:

```toml
# Use pre/post hooks to extend built-in tasks
[tasks."pre:test"]
description = "Ensure build is fresh before testing"
run = "morphir build"

[tasks."post:test"]
description = "Generate coverage report"
run = "./scripts/coverage-report.sh"

# Custom CI task that chains built-in tasks
[tasks.ci]
description = "Full CI pipeline"
depends = ["check", "test", "build", "pack"]
run = "echo 'CI passed'"
```

```bash
# Built-in tasks work immediately
morphir run build     # Runs pre:build -> build -> post:build
morphir run test      # Runs pre:test -> test -> post:test
morphir run ci        # Runs the full pipeline
```

### Development Workflow

```toml
[tasks.dev]
description = "Start development with watch mode"
run = "morphir workspace watch"

[tasks."post:build"]
description = "Auto-format generated code"
run = "prettier --write .morphir-dist/"

[tasks."post:codegen"]
description = "Format generated TypeScript"
run = "prettier --write generated/"

[tasks.release]
description = "Create a release"
depends = ["test", "build", "pack"]
run = "morphir publish --backend github"
env = { MORPHIR_RELEASE = "true" }
```

### Monorepo Tasks

```toml
# workspace/morphir.toml
[tasks.bootstrap]
description = "Initialize workspace after clone"
run = [
    "morphir deps resolve",
    "morphir workspace build"
]

[tasks.release-all]
description = "Release all packages"
depends = ["test"]  # Built-in test runs for all projects
run = "./scripts/release-all.sh"
```

### Custom Integration Tests

```toml
# Add integration tests after the built-in test task
[tasks."post:test"]
run = "./scripts/integration-tests.sh"

# Or define a separate task
[tasks.integration]
description = "Run integration tests"
depends = ["build"]
run = "./scripts/integration-tests.sh"
```

## Migration from Toolchain Config

If you previously used `[toolchain]` configuration, migrate to tasks:

```toml
# Before (deprecated)
[toolchain.morphir-elm]
enabled = true
[toolchain.morphir-elm.tasks.make]
exec = "morphir-elm"
args = ["make"]

# After (tasks)
[tasks.elm-make]
description = "Build with morphir-elm"
run = "morphir-elm make"
```

## Design Notes

1. **Simplicity**: Tasks are just shell commands, no special DSL
2. **Composability**: Dependencies allow building complex workflows from simple tasks
3. **Convention**: Pre/post hooks follow predictable naming
4. **Compatibility**: File-based tasks work with any scripting language
5. **Incremental**: Source/output tracking avoids unnecessary work

For extension points beyond tasks (custom commands, protocol extensions), see [Extensions](../vfs-protocol/wasm-component.md) for the WASM Component Model approach.
