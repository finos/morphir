---
title: "Historical: WASM extension components"
sidebar_label: "Historical: WASM extensions"
sidebar_position: 99
status: historical
draft: true
---

# Historical WASM extension components

> **Historical design, not a supported extension contract.** This page records
> rationale from an earlier WIT and WebAssembly Component Model proposal. The
> current implementation uses Extism plus MEP JSON-RPC envelopes. The CLI
> installs extensions by ID from a controlled index. Do not use this page as an
> implementation or installation guide.

Use these documents for the current contract:

- [WASM extension runtime and Avro backend](../../design/proposals/wasm-extension-runtime-and-avro-backend.md)
- [Morphir Extension Protocol](../../design/draft/extensions/protocol.md)
- [Extension distribution and acquisition](../../design/draft/extensions/distribution-and-acquisition.md)
- [Generate Apache Avro](../../generate/avro.md)

## Historical rationale

The earlier proposal represented Morphir IR and extension operations as WIT
types. Components would export separate frontend, backend, validator, transform,
and workspace interfaces. Composed worlds would grant explicit virtual
filesystem imports.

The design explored portable guests with no ambient filesystem or network
access, stable representations for Morphir names and types, optional capability
discovery, and host-controlled workspace access. Those concerns remain relevant
to the current extension system.

## Current answer

MEP keeps the protocol independent from the runtime engine. Process and WASM
extensions negotiate the same typed capabilities and use the same JSON-RPC
lifecycle. Extism is the current WASM engine. The guest SDK translates between
Extism calls and MEP requests without introducing a second WIT operation
contract.

Current WASM guests have no direct filesystem or network access. A backend
receives `GenerateRequest { ir, options }` and returns artifacts. The host
validates relative artifact paths and writes the files. Process extensions use
the same operation contract but retain the ambient rights of the user who
starts Morphir.

## Choices retained as design input

| Concern | Historical choice | Current relevance |
|---|---|---|
| Morphir names | Canonical string forms for names, paths, QNames, and FQNames | MEP payloads still need stable identity spellings. |
| Attributes | A JSON-like document value because WIT has no generics | MEP uses JSON values directly. |
| Files | Explicit virtual filesystem imports | WASM guests now return artifacts for the host to validate and write. |
| Capabilities | Separate optional interfaces and composed worlds | Initialization now negotiates typed capability records. |
| Isolation | No implicit filesystem, network, or environment access | This remains the current WASM guest boundary. |

The detailed WIT package trees, bindings, component manifests, raw file
discovery rules, archive format, and installation commands were never released.
They have been removed so this archived rationale cannot be mistaken for the
current extension API.
