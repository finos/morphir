---
title: Morphir-VFS & Polyglot Protocol Design (v4)
sidebar_label: VFS Protocol v4
sidebar_position: 1
---

# Morphir-VFS & Polyglot Protocol Design (v4)

| | |
|---|---|
| **Version** | 0.1.0-draft |
| **Date** | 2026-01-15 |
| **Status** | DRAFT |

:::caution
This is a **DRAFT** design document. All types and protocols are subject to change.
:::

## Introduction

### Purpose

This document specifies the "Morphir-VFS" architecture and the JSON-RPC 2.0 protocol for the next generation Morphir toolchain (v4). It enables a polyglot ecosystem where a Core Daemon orchestrates compilation and refactoring across language-agnostic backends.

### Design Principles

- **Immutability First**: All IR transformations are modeled as immutable state transitions.
- **VFS-Centric**: The Morphir Distribution is modeled as a hierarchical file system, accessible to standard shell tools.
- **Graceful Degradation**: Support for "Best Effort" code generation during incremental refactoring.
- **Transactional Integrity**: Multi-module refactors are handled via a Propose-Commit lifecycle.
- **Dual Mode**: Support both classic single-blob distribution and discrete VFS file layout.

### Reference Implementation

All type definitions in this document use **Gleam** syntax as the canonical reference implementation, ensuring functional contracts and sum/product type semantics.

## Architecture Overview

### Hub-and-Spoke Model

```
                    ┌─────────────────────┐
                    │     Core Daemon     │
                    │  (Gleam/Go/Rust)    │
                    │                     │
                    │  ┌───────────────┐  │
                    │  │  VFS Manager  │  │
                    │  └───────────────┘  │
                    │  ┌───────────────┐  │
                    │  │  IR Graph     │  │
                    │  │  (In-Memory)  │  │
                    │  └───────────────┘  │
                    └──────────┬──────────┘
                               │ JSON-RPC 2.0
           ┌───────────────────┼───────────────────┐
           │                   │                   │
           ▼                   ▼                   ▼
    ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
    │  TypeScript │     │ Spark/Scala │     │     Go      │
    │   Backend   │     │   Backend   │     │   Backend   │
    └─────────────┘     └─────────────┘     └─────────────┘
```

- **Hub (Core Daemon)**: Language-agnostic daemon that acts as JSON-RPC 2.0 server and VFS orchestrator.
- **Spokes (Backends)**: Polyglot "sidecars" that consume IR via the VFS protocol.
- **Transport**: JSON-RPC 2.0 over HTTP (CLI-to-Daemon) or Stdin/Stdout (LSP/One-shot).

### Dual Distribution Modes

| Mode | Layout | Use Case |
|------|--------|----------|
| **Classic** | Single `morphir-ir.json` blob | Compatibility with existing tooling, simple projects |
| **VFS (Discrete)** | `.morphir-dist/` directory tree | Large projects, shell-tool integration, incremental updates |

## Schema Architecture

The v4 schema specification uses **separate root schemas with shared `$ref` definitions**.

```
schemas/v4/
├── common/                 # Shared $ref definitions
│   ├── naming.yaml             # Path, Name, FQName, Locator
│   ├── types.yaml              # Type expressions & definitions
│   ├── values.yaml             # Value expressions & definitions
│   └── access.yaml             # AccessControlled wrapper
├── classic/                # Single-blob mode
│   └── distribution.yaml       # Root: Distribution
└── vfs/                    # Discrete mode
    ├── format.yaml             # .morphir-dist/format.json
    ├── module.yaml             # module.json schema
    ├── type-node.yaml          # *.type.json schema
    └── value-node.yaml         # *.value.json schema
```

### VFS Granularity

The VFS mode uses **one file per definition**:

- `User.type.json` contains only the `User` type definition
- `login.value.json` contains only the `login` value definition
- `module.json` contains module metadata and exports

## Distribution Structure (.morphir-dist)

```
.morphir-dist/
├── format.json            # Layout metadata and spec version (semver)
├── morphir.toml           # Project-level configuration
├── session.jsonl          # Append-only transaction journal
├── pkg/                   # Local project IR (Namespace-to-Directory)
│   └── my-org/
│       └── my-project/
│           ├── module.json       # Module manifest
│           ├── types/
│           │   └── user.type.json
│           └── values/
│               └── login.value.json
├── deps/                  # Dependency IR (versioned)
│   └── morphir/
│       └── sdk/
│           └── 1.2.0/
│               └── ...
└── deco/                  # Decorations (layered metadata)
    ├── format.json            # Decoration system metadata
    ├── schemas/               # Local schema cache
    └── layers/                # Decoration layers (core, tooling, user)
```

### VFS File Types

| File | Content | Purpose |
|------|---------|---------|
| `format.json` | Distribution metadata | Layout version, distribution type, package name |
| `module.json` | Module manifest | Lists types and values in the module |
| `*.type.json` | Type definition OR specification | TypeDefinition or TypeSpecification |
| `*.value.json` | Value definition OR specification | ValueDefinition or ValueSpecification |
| `session.jsonl` | Transaction journal | Append-only log for crash recovery |

### VFS File Polymorphism

Type and value files use **mutually exclusive keys** to indicate whether they contain a definition or specification:

```json
// Type file with definition (Library distribution)
{ "formatVersion": "4.0.0", "name": "user", "def": { "TypeAliasDefinition": { ... } } }

// Type file with specification (Specs distribution or dependency)
{ "formatVersion": "4.0.0", "name": "user", "spec": { "TypeAliasSpecification": { ... } } }
```

| Key | Used In | Contains |
|-----|---------|----------|
| `def` | Library (pkg/) | Full implementation (TypeDefinition, ValueDefinition) |
| `spec` | Specs distribution, resolved dependencies | Public interface only (TypeSpecification, ValueSpecification) |

### Format Versioning

All VFS files include a `formatVersion` field using semantic versioning (semver):

- **Major**: Breaking changes to structure or semantics
- **Minor**: Backwards-compatible additions
- **Patch**: Bug fixes, clarifications

Current version: `4.0.0`

### Namespace Mapping Rules

Morphir paths (e.g., `["Main", "Domain"]`) map to physical directories using canonical naming:

1. `pkg/` or `deps/{pkg}/{ver}/` is the root
2. Each path segment is a canonical kebab-case directory (e.g., `main/domain/`)
3. Terminal types are suffixed `.type.json` (e.g., `user.type.json`)
4. Terminal values are suffixed `.value.json` (e.g., `login.value.json`)
5. Every module directory contains a `module.json`

Example: Path `["Main", "Domain"]` → `pkg/main/domain/`

## Gleam Type Definitions

The IR type definitions are organized into separate modules for maintainability:

| Module | Description | Documentation |
|--------|-------------|---------------|
| **Naming** | Name, Path, QName, FQName types and canonical string format | [vfs-protocol/naming.md](./vfs-protocol/naming.md) |
| **Types** | Type expressions, specifications, and definitions | [vfs-protocol/types.md](./vfs-protocol/types.md) |
| **Values** | Literals, patterns, value expressions, and definitions | [vfs-protocol/values.md](./vfs-protocol/values.md) |
| **Modules** | Module structure, documentation, and serialization | [vfs-protocol/modules.md](./vfs-protocol/modules.md) |
| **Packages** | Package specifications and definitions | [vfs-protocol/packages.md](./vfs-protocol/packages.md) |
| **Distributions** | Distribution types, semantic versioning, and VFS layout | [vfs-protocol/distributions.md](./vfs-protocol/distributions.md) |
| **Decorations** | Layered metadata system for IR annotations | [vfs-protocol/decorations.md](./vfs-protocol/decorations.md) |
| **Document** | Schema-less JSON-like data type | [vfs-protocol/document.md](./vfs-protocol/document.md) |
| **Metadata** | File-level metadata (`$meta`) | [vfs-protocol/meta.md](./vfs-protocol/meta.md) |
| **References** | Node references (`$ref`) for deduplication | [vfs-protocol/refs.md](./vfs-protocol/refs.md) |

### IR Hierarchy Summary

```
Distribution
├── Library(LibraryDistribution)
│   ├── package: PackageInfo (name, version)
│   ├── definition: PackageDefinition
│   │   └── modules: Dict(ModulePath, AccessControlled(ModuleDefinition))
│   └── dependencies: Dict(PackagePath, PackageSpecification)
│
├── Specs(SpecsDistribution)
│   ├── package: PackageInfo (name, version)
│   ├── specification: PackageSpecification
│   │   └── modules: Dict(ModulePath, ModuleSpecification)
│   └── dependencies: Dict(PackagePath, PackageSpecification)
│
└── Application(ApplicationDistribution)
    ├── package: PackageInfo (name, version)
    ├── definition: PackageDefinition
    │   └── modules: Dict(ModulePath, AccessControlled(ModuleDefinition))
    ├── dependencies: Dict(PackagePath, PackageDefinition)  ← Full definitions (statically linked)
    └── entry_points: Dict(Name, EntryPoint)
        └── EntryPoint
            ├── target: FQName
            ├── kind: EntryPointKind (Main|Command|Handler|Job|Policy)
            └── doc: Option(Documentation)
```

## JSON-RPC 2.0 Protocol

### VFS Methods

#### vfs/read

Retrieve a specific node from the VFS with resolved configuration context.

```json
{
  "method": "vfs/read",
  "params": {
    "uri": "morphir://pkg/main/domain/user.type.json"
  }
}
```

#### vfs/proposeUpdate

Starts a speculative change to the IR. The Daemon verifies type-checking before committing.

```json
{
  "method": "vfs/proposeUpdate",
  "params": {
    "txId": "refactor-001",
    "ops": [
      {
        "op": "RenameType",
        "path": "main/domain",
        "oldName": "order",
        "newName": "purchase"
      }
    ],
    "dryRun": false
  }
}
```

#### vfs/commit

Finalizes a transaction.

1. The Daemon writes the `commit` line to `session.jsonl`
2. The Pending State is synced to the physical `.morphir-dist` directory
3. A `vfs/onChanged` notification is broadcast to all active backends

#### vfs/subscribe

Backends observe specific namespaces to reduce network traffic.

```json
{
  "method": "vfs/subscribe",
  "params": {
    "namespaces": ["main/domain"],
    "depth": "recursive"
  }
}
```

### Notifications

#### vfs/onChanged

Sent by the Daemon whenever the IR or Config is updated.

```json
{
  "method": "vfs/onChanged",
  "params": {
    "uri": "morphir://pkg/main/domain/order.type.json",
    "changeType": "Update",
    "content": { "..." : "..." },
    "resolvedConfig": { "..." : "..." }
  }
}
```

### IR Operations

```gleam
/// Operations for IR mutations
pub type IrOperation {
  UpsertType(path: Path, name: Name, definition: TypeDefinition(Attributes))
  UpsertValue(path: Path, name: Name, definition: ValueDefinition(Attributes))
  DeleteNode(path: Path, name: Name)
  RenameNode(path: Path, old_name: Name, new_name: Name)
}
```

## Best-Effort Generation

### Generation Status

```gleam
/// Artifact produced by code generation
pub type Artifact {
  Artifact(path: String, content: String)
}

/// Result of backend code generation
pub type GenerationStatus {
  /// Generation succeeded perfectly
  Clean(artifacts: List(Artifact))
  /// Generation succeeded with placeholders for broken call-sites
  Degraded(artifacts: List(Artifact), holes: List(HoleReport))
  /// Structural errors prevented any output
  Failed(errors: List(Diagnostic))
}
```

### Hole Report

```gleam
/// Identifies where "Best-Effort" placeholders were inserted
pub type HoleReport {
  HoleReport(
    location: SourceLocation,
    ir_reference: FQName,
    reason: HoleReason,
  )
}

pub type SourceLocation {
  SourceLocation(uri: String, range: Range)
}

pub type Range {
  Range(start: Position, end: Position)
}

pub type Position {
  Position(line: Int, character: Int)
}
```

### Diagnostic

```gleam
pub type Severity {
  Error
  Warning
  Info
}

pub type Diagnostic {
  Diagnostic(
    severity: Severity,
    code: String,
    message: String,
    range: Range,
  )
}
```

## Configuration Merge Rules

The Core Daemon provides a **Resolved Configuration View**. Layers merge in priority order (highest first):

1. **Session Overlays**: Volatile overrides sent via `vfs/setOverlay`
2. **Environment Variables**: `MORPHIR__SECTION__KEY` format
3. **Module Config**: `module.json` or local `morphir.toml`
4. **Project Config**: Root `morphir.toml`
5. **User/Global Config**: System-level defaults

## Session Management

The `session.jsonl` file is an append-only log for crash recovery and refactoring history.

```json
{"ts": "2026-01-15T11:00:00Z", "tx": "tx-1", "op": "begin"}
{"ts": "2026-01-15T11:00:01Z", "tx": "tx-1", "op": "upsert_type", "path": "my-org/domain", "name": "user", "data": {"..."}}
{"ts": "2026-01-15T11:00:05Z", "tx": "tx-1", "op": "commit"}
```

### Session Operations

```gleam
pub type SessionOp {
  Begin
  UpsertType
  UpsertValue
  DeleteNode
  SetConfigOverlay
  Commit
  Rollback
}

pub type SessionEntry {
  SessionEntry(
    ts: String,        // ISO 8601 timestamp
    tx: String,        // Transaction ID
    op: SessionOp,
    path: Option(Path),
    name: Option(Name),
    data: Option(Dynamic),
  )
}
```

## Backend Registration

Backends register with the Daemon to define their capabilities.

```gleam
pub type Transport {
  Http
  Stdio
}

pub type BackendCapabilities {
  BackendCapabilities(
    incremental: Bool,      // Supports incremental updates
    best_effort: Bool,      // Supports degraded generation
    transports: List(Transport),
  )
}

pub type BackendRegistration {
  BackendRegistration(
    name: String,
    capabilities: BackendCapabilities,
  )
}
```

## Open Questions

:::note
The following items require further design discussion:

1. ~~**Value expressions** - Complete the Value type definitions~~ ✓ Done
2. ~~**Module structure** - Define ModuleSpecification and ModuleDefinition~~ ✓ Done
3. ~~**Package/Distribution** - Define top-level containers for both modes~~ ✓ Done
4. ~~**Specs Distribution** - Define specification-only distribution type~~ ✓ Done
5. ~~**Application Distribution** - Define `ApplicationDistribution` variant for executable distributions~~ ✓ Done
6. **WASM Component Model** - Define wit interfaces for backend extensions
7. ~~**Intrinsic Document Type** - First-class JSON-like/tree data structure (similar to Smithy's Document type or Ion's S-expressions) for schema-less data within the IR~~ ✓ Done
8. ~~**Context Metadata (`$meta`)** - Add a `$meta` key to VFS JSON files for extensible metadata without polluting the main schema~~ ✓ Done
9. ~~**Node References (`$ref`)** - Support JSON Schema style references for deduplicating repeated node trees~~ ✓ Done
10. ~~**Type Reference Shorthand** - Allow canonical FQName string as shorthand for `{ "Reference": { "fqname": "..." } }` when attributes are empty/null~~ ✓ Done
11. ~~**Decorators** - Design support for Morphir decorators (@alias, @doc, @deprecated, custom annotations) in the IR~~ ✓ Done
:::

## Appendix A: Integrity Status Summary

| Status | Meaning |
|--------|---------|
| `Clean` | Generation succeeded perfectly |
| `Degraded` | Generation succeeded with placeholders/runtime-errors for broken call-sites |
| `Failed` | Structural errors prevented any output |

## Appendix B: Placeholder Strategies

### Runtime Error (TypeScript/Scala)

```typescript
const user = morphir.runtime.hole("Unresolved Type: UserAccount", { line: 12 });
```

### Type Erasure (Java/Go)

```java
public Object processOrder(Object order) {
    /* Hole: Order type missing */
    return null;
}
```
