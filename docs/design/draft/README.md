---
title: Design Drafts
sidebar_label: Overview
sidebar_position: 1
---

# Morphir v4 Design

This section contains the design documents for Morphir v4, organized into three primary themes.

## Themes

### [IR v4](./ir/README.md)

The intermediate representation format and data model.

**Scope:** Types, values, modules, packages, distributions, naming conventions, decorations, serialization formats.

**Key Documents:**
- [Naming Conventions](./ir/naming.md) - How names are encoded
- [Types & Values](./ir/types.md) - Core type system
- [Distributions](./ir/distributions.md) - Library, Specs, Application formats

---

### [Morphir Daemon](./daemon/README.md)

The long-running service for workspace management, builds, and IDE integration.

**Scope:** Workspace lifecycle, project management, dependency resolution, incremental builds, file watching, package publishing, JSON-RPC protocol.

**Key Documents:**
- [Workspace Lifecycle](./daemon/lifecycle.md) - Create, open, close
- [Dependencies](./daemon/dependencies.md) - Resolution and caching
- [Configuration](./daemon/configuration.md) - morphir.toml system

---

### [Extensions](./extensions/README.md)

The extension architecture for adding capabilities to Morphir.

**Scope:** WASM Component Model integration, task system, pre/post hooks, custom code generators.

**Key Documents:**
- [WASM Components](./extensions/wasm-component.md) - Plugin architecture
- [Tasks](./extensions/tasks.md) - Build automation and hooks

---

## Status Tracking

Each design document includes tracking metadata:

| Status | Description |
|--------|-------------|
| **Draft** | Initial design, under active development |
| **Review** | Design complete, awaiting review |
| **Approved** | Ready for implementation |
| **POC** | Proof of concept exists |
| **Partial** | Partially implemented |
| **Complete** | Fully implemented |

### Tracking Frontmatter

Documents use this frontmatter format for tracking:

```yaml
---
title: Document Title
status: draft
tracking:
  beads: [morphir-xxx]
  github_issues: [123]
  github_discussions: [45]
  implementation: "pkg/path/to/code"
---
```

---

## Quick Reference

### Active GitHub Issues

| Issue | Theme | Description |
|-------|-------|-------------|
| [#398](https://github.com/finos/morphir/issues/398) | IR | VFS core types |
| [#392](https://github.com/finos/morphir/issues/392) | Daemon | Pipeline core types |
| [#399](https://github.com/finos/morphir/issues/399) | Extensions | Task execution engine |
| [#401](https://github.com/finos/morphir/issues/401) | Daemon | Caching and incremental builds |
| [#400](https://github.com/finos/morphir/issues/400) | Daemon | Analyzer framework |

### Active Beads Issues

| Issue | Theme | Description |
|-------|-------|-------------|
| morphir-om0 | IR | Core decoration infrastructure |
| morphir-l75 | Daemon | Caching and incremental builds |
| morphir-go-772 | Extensions | Task execution engine |
| morphir-8fx | IR | VFS error types |
| morphir-369 | Daemon | SQLite-backed VFS backend |

### Related Discussions

| Discussion | Theme | Topic |
|------------|-------|-------|
| [#55](https://github.com/finos/morphir/discussions/55) | IR | Distributions, versioning, migrations |
| [#88](https://github.com/finos/morphir/discussions/88) | Daemon | Package manager |
| [#52](https://github.com/finos/morphir/discussions/52) | IR | Unique identifiers in IR |
| [#53](https://github.com/finos/morphir/discussions/53) | IR | Type encoding |

---

## Implementation Priorities

### Phase 1: Foundation (Active)

1. **IR v4 Core** - Types, values, naming
2. **Decorations** - Metadata infrastructure
3. **Pipeline** - Build system foundation

### Phase 2: Daemon (Planned)

1. **Workspace** - Multi-project support
2. **Dependencies** - Path and repository resolution
3. **Builds** - Incremental compilation

### Phase 3: Extensions (Future)

1. **WASM Components** - Plugin architecture
2. **Tasks** - Automation hooks
3. **Registry** - Package distribution
