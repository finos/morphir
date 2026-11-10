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
- `execution`: `mode` (`native-aot` or `jit`) and `runtime`. Native AOT has `{ "kind": "none" }`; JIT has `bundled` or `system` with the runtime `version`. Any other combination is `inconsistent_document` at `host.execution.runtime`. For the `dotnet` implementation the deployment fixes the execution, and a mismatch is `inconsistent_document` at `host.execution`:

  | Deployment | Execution |
  | --- | --- |
  | `native-aot` | `native-aot`, runtime `none` |
  | `self-contained` | `jit`, runtime `bundled` |
  | `framework-dependent`, `dotnet-tool` | `jit`, runtime `system` |

- `installation`, `readiness` and `checks`.

Each provider has `identity`, the lock's provider entry exactly, and `readiness` and `checks`. Every provider except a built-in also has `installation`; a built-in is part of the host and has none.

### Installation

| Member | Cases |
| --- | --- |
| `ownership.kind` | `manager-owned`; `direct-archive`; `dotnet-tool` with `packageId` and `scope` (`global`, `tool-path`, `local-manifest`); `system-package` with `manager` |
| `authentication.kind` | `repository-target` with `repositoryId` and `targetsVersion`; `recipe-digest` with `repositoryId`, `recipeTarget`, `recipeSha256`, which must equal the receipt's own `recipe` (otherwise `inconsistent_document` at the authentication member); `local-developer` with `policy: "developer"`; `external-owner` |
| `launch` | `program`, an absolute [local path](./index.md#local-paths) in the receipt platform's syntax, and fixed `args` |
| `claimCheck` (providers) | `probed` with `probeSource` (`describe` or `session-fallback`), or `unchecked` without one |

The manager updates or removes only `manager-owned` installations. For another owner it reports the owner's update mechanism.

Publisher authentication and the claim check are separate facts. `authentication` says how the bytes were authenticated: directly by TUF target metadata, by a digest in an authenticated recipe, by nothing (an unsigned developer artifact admitted by explicit developer policy), or not by the manager at all (an external owner). `claimCheck` says whether the installed artifact was run to compare its capability claims. A probed developer artifact is still unauthenticated, and an authenticated artifact installed with `--no-probe` is still `unchecked`. A developer artifact is admitted only into manager-owned storage, and a manager-owned installation always says how the manager authenticated it.

### Readiness

Readiness is ordered: `acquired`, `integrity-verified`, `capability-checked`, `workflow-qualified`. A component records exactly one `integrity` and one `capability` check. A generation records exactly one `workflow` check, naming its `workflow`. A check's `status` is `passed`, `failed`, `skipped` or `unsupported`; anything other than `passed` states its `reason`, so a skipped or unsupported check stays visible.

A component records exactly one `integrity` and one `capability` check, and only a workflow check names a `workflow`. A built-in provider is part of the host's bytes, so its integrity check has the same outcome as the host's; a different outcome is `inconsistent_document` at the provider's `checks`.

Readiness is derived, never asserted:

- a component is `integrity-verified` when its integrity check passed and `capability-checked` when both checks passed;
- a generation is `workflow-qualified` when every component is `capability-checked` and the workflow check passed, and otherwise has the lowest component readiness.

For the `fsharp` preset the workflow is `fsharp-compile-generate`, the fixed case described in [F# readiness workflow case](./readiness-workflow.md).

A receipt whose `readiness` differs from the derived value is `inconsistent_document`. A valid archive whose frontend shares no tuple with its host is therefore `integrity-verified`, installed but not ready.

Understood critical paths: `schemaVersion`, `critical`, `generationId`, `platform`, `lockSha256`, `recipe`, `host`, `host.identity`, `host.execution`, `host.installation`, `host.readiness`, `host.checks`, `providers`, `providers.identity`, `providers.installation`, `providers.readiness`, `providers.checks`, `readiness`, `checks`.

## Binding to the lock

Given the lock bytes and the lock they read as, a receipt is checked in this order and refused at the first failure. Every path names a member of the receipt, except `platforms`, which names the lock's member, as it does in frozen restore:

| Check | Code | Path | Cases |
| --- | --- | --- | --- |
| The SHA-256 of the lock bytes equals `lockSha256` | `lock_changed` | `lockSha256` | `receipt-lock-bytes` |
| `recipe` equals the lock's `recipe` (`repositoryId`, `target`, `sha256`) | `receipt_lock_mismatch` | `recipe` | `receipt-lock-recipe` |
| The lock records a closure for the receipt's `platform` | `platform_not_locked` | `platforms` | `receipt-lock-platform` |
| `host.identity` has the lock's host `implementation`, `version` and `deployment`, and the closure's `hostTarget` and `hostSha256` as `target` and `sha256` | `receipt_lock_mismatch` | `host.identity` | `receipt-lock-host` |
| `providers` has as many entries as the closure's `providers` | `receipt_lock_mismatch` | `providers` | `receipt-lock-provider-count` |
| Each provider's `identity`, in index order, equals the closure's provider at the same index | `receipt_lock_mismatch` | `providers[i].identity` | `receipt-lock-provider` |

A [manager result](./manager-result.md#diagnostics) reports `lock_changed` and `receipt_lock_mismatch` with `document` `receipt`, and `platform_not_locked` with `document` `lock`.

## Fixtures

`fixtures/0.1.0-draft.1/receipt/` holds a workflow-qualified Windows generation bound to `lock/two-platforms-bound.json`, a generation whose frontend failed negotiation, a probed unsigned developer frontend, and an externally owned global .NET tool host bound to `lock/dotnet-tool-host.json`. `receipt/binding/` holds valid receipts that do not bind their lock: a substituted provider artifact, a substituted host release, a platform the lock does not record, another recipe, a missing provider, and another recipe together with another host release, which is refused at `recipe` because the recipe is compared first. `receipt/negative/` covers:

- a later draft and an unknown critical member;
- readiness above its checks, a qualified generation with a failed workflow, an unknown readiness state, a non-passed check without a reason, a workflow name on a component check, two workflow checks, and a built-in whose integrity differs from its host's;
- a provider without a claim check and a probe source on an unchecked claim set;
- Native AOT with a bundled runtime, and a deployment whose execution disagrees;
- an unknown owner, a built-in with an installation, a developer artifact outside manager-owned storage, a developer policy other than `developer`, an external owner for a manager-owned installation, and `recipe-digest` authentication naming another recipe;
- relative, wrong-platform, traversing and drive-root launch paths;
- credential members (`authorization`, `apiKey`) and an invalid generation id.