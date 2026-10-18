---
order: 8
---
# Morphir Moonbit Architecture

## Overview

This repository implements Morphir in Moonbit, organized as a monorepo with multiple interdependent packages. The architecture is designed to support both server-side (WASI) and browser-based (WASM-GC) WebAssembly targets.

## Domain model and effects

Morphir uses functional domain modeling and a functional core with an imperative
shell. Domain types express meaning and invariants. Closed enums and discriminated
unions represent choices and state transitions; validated value types represent
identities and constrained values. Unrestricted strings, sentinel values and
independent flags should not represent domain states with invalid combinations.
Booleans remain appropriate for independent facts and derived predicates.

Decode external JSON and strings into domain values at explicit boundaries. Pure
functions validate requirements, choose behavior and calculate state transitions.
Adapters perform worker, network, filesystem and host effects using those decisions.
Encode domain values when crossing an external boundary. A compatibility spelling
in a protocol does not define the vocabulary inside the domain model.

The canonical vocabulary is in [CONTEXT.md](../CONTEXT.md). For example, a capability
checking policy is a closed choice reused by the engine and UI. The historical
`admission` wire key and source aliases remain compatibility identifiers. Capability
claims and UI descriptions are information about support; a validated execution
plan captures the requirements and policy for a particular run.

## Repository Structure

```
morphir-moonbit/
├── .config/mise/              # Development tooling configuration
│   ├── config.toml           # Tool versions and environment
│   └── tasks/                # Build, test, and lint tasks
├── .github/
│   └── workflows/            # CI/CD pipelines
├── docs/                     # Documentation
├── pkgs/                     # Moonbit packages (workspace member modules)
│   ├── morphir-sdk/
│   │   ├── moon.mod         # Module definition
│   │   └── moon.pkg         # Package definition
│   ├── morphir-core/
│   │   ├── moon.mod         # Module definition
│   │   └── moon.pkg         # Package definition
│   └── morphir-moonbit-bindings/
│       ├── moon.mod         # Module definition
│       └── moon.pkg         # Package definition
├── moon.mod                  # Root module configuration
└── moon.work                 # Workspace manifest (member modules)
```

Note: Each package in `pkgs/` is a Moonbit module with its own `moon.mod` (module definition) and `moon.pkg` (package definition within that module). The root `moon.work` registers each module as a workspace member so they can depend on one another from source, without a registry round-trip.

## Package Organization

### morphir-core

**Purpose**: Core abstractions and fundamental types for the Morphir ecosystem.

**Responsibilities**:
- Define core types and interfaces
- Provide fundamental abstractions
- Establish type system foundations
- Define IR (Intermediate Representation) structures

**Dependencies**: None (foundational package)

### morphir-sdk

**Purpose**: Standard library providing functional programming primitives and data structures.

**Responsibilities**:
- Implement common data structures (List, Dict, Set, etc.)
- Provide functional utilities (map, filter, fold, etc.)
- Define standard types and interfaces
- Supply helper functions for common operations

**Dependencies**: `morphir-core`

### morphir-moonbit-bindings

**Purpose**: Foreign Function Interface (FFI) bindings for Moonbit WASM targets.

**Responsibilities**:
- Provide JavaScript interop for browser target
- Define WASI bindings for server-side target
- Expose platform-specific APIs
- Handle serialization/deserialization across boundaries

**Dependencies**: `morphir-core`, `morphir-sdk`

## Build Targets

### WASI Target (`wasm`)

- **Use Case**: Server-side applications, CLI tools, and WASI runtimes
- **Runtime**: WasmEdge, Wasmtime, or any WASI-compliant runtime
- **Features**: File system access, network I/O, system calls via WASI

### Browser Target (`wasm-gc`)

- **Use Case**: Browser-based applications
- **Runtime**: Modern browsers with WASM-GC support
- **Features**: JavaScript interop, DOM access, optimized GC integration

## Development Workflow

### Task Orchestration

All development tasks are managed through **mise** (formerly rtx), which provides:

1. **Consistent tooling**: Same tool versions across all developers
2. **Cross-platform support**: Tasks work on Linux, macOS, and Windows
3. **Simple interface**: Single command to run any task
4. **Environment management**: Automatic tool installation and PATH setup

### Task Categories

1. **Linting**: Code quality checks (YAML, Moonbit formatting)
2. **Formatting**: Automatic code formatting
3. **Building**: Compilation for different targets
4. **Testing**: Unit and integration tests
5. **Cleaning**: Remove build artifacts

## CI/CD Pipeline

### Parallel Execution Strategy

The CI pipeline is optimized for fast feedback:

```
┌─────────┐  ┌──────────────┐
│  Lint   │  │ Format Check │
└────┬────┘  └──────┬───────┘
     │              │
     └──────┬───────┘
            │
     ┌──────▼───────┐
     │   Test       │
     └──────┬───────┘
            │
     ┌──────▼───────┐
     │   Build      │
     │  (Matrix)    │
     │ - WASI       │
     │ - Browser    │
     └──────────────┘
```

### Job Descriptions

1. **Lint Job**: Validates YAML files and checks for common issues
2. **Format Check Job**: Ensures code follows formatting standards
3. **Test Job**: Runs all package tests
4. **Build Job**: Builds all packages for both targets (matrix strategy)

## Package Dependencies

```
┌──────────────────────┐
│   morphir-core       │  (No dependencies)
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│   morphir-sdk        │  (Depends on: core)
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ morphir-moonbit-     │  (Depends on: core, sdk)
│     bindings         │
└──────────────────────┘
```

## Tool Stack

### Development Tools (Managed by mise)

- **Moonbit**: Primary programming language
- **Bun**: Fast JavaScript runtime for scripting
- **yamllint**: YAML validation
- **uv**: Python package management

### MoonBit libraries

Our MoonBit toolchain includes these foundational libraries. This is a
non-exhaustive overview; individual modules declare the dependencies they need.

| Library | Role |
| --- | --- |
| [`moonbitlang/core`](https://github.com/moonbitlang/core) | Standard library for collections, strings, numbers, JSON and other shared functionality. |
| [`moonbitlang/x`](https://github.com/moonbitlang/x) | Experimental and extension packages that complement the standard library. |
| [`moonbitlang/async`](https://github.com/moonbitlang/async) | Asynchronous I/O and structured concurrency for tooling, including filesystem operations, subprocesses and task orchestration. |

Async support is included in our tooling architecture, especially the CLI and
engine/pipeline host layers that process workspaces, projects, directories and
files. Use `moonbitlang/async` where the selected package and target support the
required operations. Keep target-specific I/O in host adapters so shared IR and
transformation logic can run across our supported targets.

### CI/CD

- **GitHub Actions**: Continuous integration
- **mise-action**: Tool installation in CI

## Design Principles

1. **Minimal Dependencies**: Each package has only necessary dependencies
2. **Target Flexibility**: All packages support multiple WASM targets
3. **Task Consistency**: Same commands work locally and in CI
4. **Cross-Platform**: Works on Linux, macOS, and Windows
5. **Fast Feedback**: Parallel CI jobs for quick iteration

## Future Considerations

### Planned Additions

1. **morphir-elm-interop**: Interoperability with Elm implementations
2. **morphir-tooling**: Development tools and utilities
3. **morphir-examples**: Example applications and tutorials

### Scalability

The monorepo structure allows for:
- Easy addition of new packages
- Shared tooling and configuration
- Consistent versioning across packages
- Simplified dependency management

## References

- [Moonbit Documentation](https://www.moonbitlang.com/docs/)
- [Mise Documentation](https://mise.jdx.dev/)
- [WebAssembly Specification](https://webassembly.org/)
- [WASI Specification](https://wasi.dev/)

## IR transformation and execution

`morphir-ir` owns the current model, explicit v1–v4 models, codecs and migrations.
`morphir-scheme` supplies the embeddable language, functional Scheme frontend,
IR backend and runtime support. `morphir-engine` orchestrates files, directories,
projects and workspaces using host-provided I/O and Scheme configuration.

```text
Host → Engine → Frontend → Current IR → Script transforms → Backend → Artifacts
                             ↓
                      Scheme execution
```

The engine returns artifacts and stage diagnostics. Each source produces an
independent artifact. `morphir-host` supplies memory, native, Node, WASI and
WASM-GC adapters, snapshot preparation and recoverable task publication. Cross-file
linking remains separate compiler work. See [Morphir Engine](../pkgs/morphir-engine/README.md) and
[Morphir Scheme](../pkgs/morphir-scheme/README.mbt.md) for APIs, executable examples
and the supported language boundary.
