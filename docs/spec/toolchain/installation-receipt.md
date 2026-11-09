---
title: Toolchain installation receipt 0.1.0-draft.1
sidebar_label: Installation receipt
status: draft
---

# Toolchain installation receipt 0.1.0-draft.1

A receipt describes one installed toolchain generation on one machine. It lives under `MORPHIR_HOME/toolchains/generations/<id>/` and is never checked in. It binds the SHA-256 of the exact lock bytes, the platform and every installed object identity, and records local launch paths, ownership, authentication, claim-check status and readiness evidence. Version authority: this page. Schema: [toolchain-receipt-0.1.0-draft.1.schema.json](/schemas/toolchain-receipt-0.1.0-draft.1.schema.json).

## Members

| Member | Meaning |
| --- | --- |
| `generationId` | A local opaque token. It is not a release version |
| `platform` | The platform the generation was installed for |
| `lockSha256` | SHA-256 of the exact lock bytes |
| `recipe` | The lock's recipe reference, repeated |
| `host` | The installed host |
| `providers` | One installed provider per locked provider, in lock order |
| `readiness`, `checks` | Generation readiness and its one workflow check |

`host` has:

- `identity`: `implementation`, `version`, `deployment`, `target`, `sha256`, equal to the lock's host and the platform closure's `hostTarget` and `hostSha256`;
- `execution`: `mode` (`native-aot` or `jit`) and `runtime`, which is `{ "kind": "none" }` for Native AOT and `bundled` or `system` with the runtime `version` otherwise;
- `installation`, `readiness` and `checks`.

Each provider has `identity`, the lock's provider entry exactly, and `readiness` and `checks`. Every provider except a built-in also has `installation`; a built-in is part of the host and has none.

### Installation

| Member | Cases |
| --- | --- |
| `ownership.kind` | `manager-owned`; `direct-archive`; `dotnet-tool` with `packageId` and `scope` (`global`, `tool-path`, `local-manifest`); `system-package` with `manager` |
| `authentication.kind` | `repository-target` with `repositoryId` and `targetsVersion`; `recipe-digest` with `repositoryId`, `recipeTarget`, `recipeSha256`; `local-developer` with `policy: "developer"`; `external-owner` |
| `launch` | `program`, an absolute path for the receipt's platform, and fixed `args` |
| `claimCheck` (providers) | `probed` with `probeSource` (`describe` or `session-fallback`), or `unchecked` without one |

The manager updates or removes only `manager-owned` installations. For another owner it reports the owner's update mechanism.

Publisher authentication and the claim check are separate facts. `authentication` says how the bytes were authenticated: directly by TUF target metadata, by a digest in an authenticated recipe, by nothing (an unsigned developer artifact admitted by explicit developer policy), or not by the manager at all (an external owner). `claimCheck` says whether the installed artifact was run to compare its capability claims. A probed developer artifact is still unauthenticated, and an authenticated artifact installed with `--no-probe` is still `unchecked`. A developer artifact is admitted only into manager-owned storage, and a manager-owned installation always says how the manager authenticated it.

### Readiness

Readiness is ordered: `acquired`, `integrity-verified`, `capability-checked`, `workflow-qualified`. A component records exactly one `integrity` and one `capability` check. A generation records exactly one `workflow` check, naming its `workflow`. A check's `status` is `passed`, `failed`, `skipped` or `unsupported`; anything other than `passed` states its `reason`, so a skipped or unsupported check stays visible.

Readiness is derived, never asserted:

- a component is `integrity-verified` when its integrity check passed and `capability-checked` when both checks passed;
- a generation is `workflow-qualified` when every component is `capability-checked` and the workflow check passed, and otherwise has the lowest component readiness.

A receipt whose `readiness` differs from the derived value is `inconsistent_document`. A valid archive whose frontend shares no tuple with its host is therefore `integrity-verified`, installed but not ready.

Understood critical paths: `schemaVersion`, `critical`, `generationId`, `platform`, `lockSha256`, `recipe`, `host`, `host.identity`, `host.execution`, `host.installation`, `host.readiness`, `host.checks`, `providers`, `providers.identity`, `providers.installation`, `providers.readiness`, `providers.checks`, `readiness`, `checks`.

## Binding to the lock

Given the lock bytes, a receipt is refused with `lock_changed` when their SHA-256 differs from `lockSha256`, and with `receipt_lock_mismatch` when its recipe, host identity or any provider identity differs from the lock's closure for the receipt's platform.

## Fixtures

`fixtures/0.1.0-draft.1/receipt/` holds a workflow-qualified Windows generation bound to `lock/two-platforms-bound.json`, a generation whose frontend failed negotiation, a probed unsigned developer frontend, and an externally owned global .NET tool host with an unchecked frontend. `receipt/binding/` holds valid receipts whose provider artifact or host deployment differs from the lock. `receipt/negative/` covers a later draft, an unknown critical member, readiness above its checks, a qualified generation with a failed workflow, a provider without a claim check, a probe source on an unchecked claim set, relative and wrong-platform launch paths, an unknown owner, a built-in with an installation, a developer artifact outside manager-owned storage, a credential member, an invalid generation id and an unknown readiness state.
