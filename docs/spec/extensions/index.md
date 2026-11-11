---
title: Extension contracts
---

# Extension contracts

Read [WASM execution and host qualification](./wasm-hosts.md) for the two execution
profiles, import/result tables, sandbox policy and evidence needed to qualify an
offering/platform. The process-based F# delivery has its own qualification path.

The parent repository owns the [identity](./identity.md), [package](./packages.md), shared-file definitions and frozen cases. The .NET runner executes their behavior through host adapters. See the [distribution contract](../../design/draft/extensions/distribution-and-acquisition.md#shared-extension-state-contract) for member tables, the [approval-time publication audit](./publication-audit.md) for the selected version, and the [protocol](../../design/draft/extensions/protocol.md) for MEP. The MEP 0.2 line and toolchain contracts retain their own authorities.
