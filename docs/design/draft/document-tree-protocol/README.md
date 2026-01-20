---
title: Document Tree Protocol Design (v4)
sidebar_label: Document Tree Protocol
sidebar_position: 1
---

# Document Tree Protocol Design (v4)

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

This document specifies the "Document Tree" architecture for the next generation Morphir toolchain (v4). It enables a polyglot ecosystem where a Core Daemon orchestrates compilation and refactoring across language-agnostic backends.

For detailed protocol specifications, see [Protocol Details](./protocol.md).

### Design Principles

- **Immutability First**: All IR transformations are modeled as immutable state transitions.
- **Document Tree-Centric**: The Morphir Distribution is modeled as a hierarchical file system, accessible to standard shell tools.
- **Graceful Degradation**: Support for "Best Effort" code generation during incremental refactoring.
- **Transactional Integrity**: Multi-module refactors are handled via a Propose-Commit lifecycle.
- **Dual Mode**: Support both classic single-blob distribution and discrete Document Tree file layout.

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
| **Document Tree** | `.morphir-dist/` directory tree | Large projects, shell-tool integration, incremental updates |

## Document Tree Granularity

The Document Tree mode supports two levels of granularity for modules:

1.  **Granular (Preferred)**: One file per definition.
    -   `User.type.json` contains only the `User` type definition
    -   `login.value.json` contains only the `login` value definition
    -   `module.json` contains only module metadata and exports

2.  **Hybrid / Inline**: `module.json` contains definitions inline.
    -   Useful for small modules or when generating code where file proliferation is undesirable.
    -   `module.json` contains `types` and `values` maps directly (similar to Classic mode).

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

## Detailed Specifications

-   **[Use Cases & Workflows](./workflows.md)** (TODO)
-   **[Protocol Specification](./protocol.md)** - JSON-RPC 2.0 methods and notifications
-   **[Schema Architecture](../../../spec/draft/schemas.md)** - Validation schemas for Document Tree nodes
