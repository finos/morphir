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

## Documentation Structure

This specification is organized into the following sections:

| Document | Description |
|----------|-------------|
| [Naming](./naming.md) | Name, Path, QName, FQName types and canonical string format |
| [Types](./types.md) | Type expressions, specifications, and definitions |
| [Values](./values.md) | Literals, patterns, value expressions, and definitions |
| [Modules](./modules.md) | Module structure, documentation, and serialization |
| [Packages](./packages.md) | Package specifications and definitions |
| [Distributions](./distributions.md) | Distribution types, semantic versioning, and VFS layout |
| [Decorations](./decorations.md) | Layered metadata system for IR annotations |
| [Document](./document.md) | Schema-less JSON-like data type |
| [Metadata](./meta.md) | File-level metadata (`$meta`) |

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

## Quick Links

- **[Naming Module](./naming.md)** - Canonical string formats for names and paths
- **[Types Module](./types.md)** - Type system definitions
- **[Values Module](./values.md)** - Value expressions and patterns
- **[Modules Module](./modules.md)** - Module structure and documentation
- **[Packages Module](./packages.md)** - Package organization
- **[Distributions Module](./distributions.md)** - Distribution types and VFS layout
- **[Decorations Module](./decorations.md)** - Layered metadata system for IR annotations
- **[Document Module](./document.md)** - Schema-less JSON-like data type
- **[Metadata Module](./meta.md)** - File-level metadata (`$meta`)
