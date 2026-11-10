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
| `authentication.kind` | How the manager authenticated the installed bytes: `repository-target` with `repositoryId` and `targetsVersion`; `recipe-digest` with `repositoryId`, `recipeTarget`, `recipeSha256`, which must equal the receipt's own `recipe` (otherwise `inconsistent_document` at the authentication member); or `external-owner`. `local-developer` is refused with `inconsistent_document` at the authentication member (see below) |
| `launch` | `program`, an absolute [local path](./index.md#local-paths) in the receipt platform's syntax, and fixed `args` |
| `claimCheck` (providers) | `probed` with `probeSource` (`describe` or `session-fallback`), or `unchecked` without one |

The manager updates or removes only `manager-owned` installations. For another owner it reports the owner's update mechanism.

Publisher authentication and the claim check are separate facts. `authentication` says how the manager authenticated the bytes: directly by TUF target metadata, by a digest in an authenticated recipe, or not at all, because an external owner installed them. `claimCheck` says whether the installed artifact was run to compare its capability claims. An authenticated artifact installed with `--no-probe` is still `unchecked`, and a manager-owned installation always says how the manager authenticated it.

**Developer artifacts are never part of a generation.** A receipt always binds a lock, and a lock names only artifacts that an authenticated recipe binds by digest. So bytes whose digest equals a locked digest were authenticated by that recipe digest, and are labelled `recipe-digest`, whoever built them. An unsigned developer artifact cannot equal a locked digest, so it is never part of a toolchain generation. It is installed outside generations, under the extension installer's explicit developer policy, and a receipt that labels a provider `local-developer` is refused (`receipt/negative/developer-artifact-in-generation.json`).
### Readiness

Readiness is ordered: `acquired`, `integrity-verified`, `capability-checked`, `workflow-qualified`. A component records exactly one `integrity` and one `capability` check. A generation records exactly one `workflow` check, naming its `workflow`. A check's `status` is `passed`, `failed`, `skipped` or `unsupported`; anything other than `passed` states its `reason`, so a skipped or unsupported check stays visible.

Only a workflow check names a `workflow`. A built-in provider is part of the host's bytes, so its integrity check has the same outcome as the host's; a different outcome is `inconsistent_document` at the provider's `checks`.

The capability check differs by delivery:

- **A process, WASM or .NET tool provider.** The host starts a session with it, and the check passes when the session agrees with its locked protocol and model.
- **A built-in, which has no session of its own.** The staged host runs `extension list --json`, and the check passes when that list reports the built-in with the locked `extensionId` and `version`, the operation's language or target, and the IR version of its locked `modelInput` or `modelOutput`.
- **The host itself.** The check passes when it speaks the MEP versions its recipe offering lists.

All three run the staged host with the user's rights, which is why the plan's host component has `probe` `process-with-user-rights` ([manager result](./manager-result.md#plans)).

> **Maintainer question M5: what readiness must a staged generation reach before setup activates it?** **Recommended default:** no check `failed`, and every component `capability-checked`. A `skipped` or `unsupported` workflow check is allowed, `show` and `doctor` report it, and the generation is never called qualified. While the readiness workflow's generate step is pending (M1), every workflow check is `skipped`, so this default is what lets setup activate anything. The activation rule is **provisional** until M5 is answered: setup publishes a staged generation only when no check failed and every component is `capability-checked`.

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
| Every `repository-target` authentication, of the host and then of each provider in index order, names the lock's `recipe.repositoryId` | `repository_mismatch` | `host.installation.authentication.repositoryId`, `providers[i].installation.authentication.repositoryId` | `receipt-lock-repository` |
| The lock records a closure for the receipt's `platform` | `platform_not_locked` | `platforms` | `receipt-lock-platform` |
| `host.identity` has the lock's host `implementation`, `version` and `deployment`, and the closure's `hostTarget` and `hostSha256` as `target` and `sha256` | `receipt_lock_mismatch` | `host.identity` | `receipt-lock-host` |
| `providers` has as many entries as the closure's `providers` | `receipt_lock_mismatch` | `providers` | `receipt-lock-provider-count` |
| Each provider's `identity`, in index order, equals the closure's provider at the same index | `receipt_lock_mismatch` | `providers[i].identity` | `receipt-lock-provider` |

The repository row applies the [one repository per binding check](./toolset-recipe.md#one-repository-per-binding-check) rule: bytes the receipt says a repository authenticated came from the lock's repository. A `recipe-digest` authentication already names the receipt's own recipe, and `external-owner` names no repository.

A [manager result](./manager-result.md#diagnostics) reports `lock_changed` and `receipt_lock_mismatch` with `document` `receipt`, and `platform_not_locked` with `document` `lock`. `repository_mismatch` is a `trust-failure` diagnostic, whose `repositoryId` names the repository the check ran against.

## Launch and rollback against learned revocations

Before `run` launches a generation, and before `rollback` selects one, the manager checks the generation's lock against the trust state it has learned from the repository. That state is durable: Morphir Home's trust state records every learned revocation, and it survives a failed metadata refresh and offline use. So a revocation, once learned, keeps refusing even when the repository cannot be reached. The checks, in this order:

| Check | Code | Path | Cases |
| --- | --- | --- | --- |
| The lock's `recipe.repositoryId` is the repository the trust state belongs to | `repository_mismatch` | `recipe.repositoryId` | `generation-repository` |
| The lock's recipe target has no learned revocation | `release_revoked` | `recipe.target` | `generation-recipe-revoked` |
| The lock's host release has no learned revocation (a `tool-release` offering) | `release_revoked` | `host.version` | `generation-host-revoked` |

A provider has no version 1 release status, so revoking the recipe that binds it is how a provider is revoked. A learned recipe revocation therefore refuses every generation bound to that recipe, whatever its offering, as the `recipeRevocation` metadata set of the signed fixtures shows. Paths name the lock's members; a result reports these as `trust-failure` diagnostics.

## Fixtures

`fixtures/0.1.0-draft.1/receipt/` holds a workflow-qualified Windows generation bound to `lock/two-platforms-bound.json`, a generation whose frontend failed negotiation, and an externally owned global .NET tool host bound to `lock/dotnet-tool-host.json`. `receipt/binding/` holds valid receipts that do not bind their lock: a substituted provider artifact, a substituted host release, a platform the lock does not record, another recipe, a missing provider, a host authenticated by another repository, and another recipe together with another host release, which is refused at `recipe` because the recipe is compared first. `receipt/negative/` covers:

- a later draft and an unknown critical member;
- readiness above its checks, a qualified generation with a failed workflow, an unknown readiness state, a non-passed check without a reason, a workflow name on a component check, two workflow checks, and a built-in whose integrity differs from its host's;
- a provider without a claim check and a probe source on an unchecked claim set;
- a process provider without `installation`, and a provider identity without its `modelTuple`;
- Native AOT with a bundled runtime, and a deployment whose execution disagrees;
- an unknown owner, a built-in with an installation, a provider labelled `local-developer` although it binds the locked digest, an external owner for a manager-owned installation, and `recipe-digest` authentication naming another recipe;
- relative, wrong-platform, traversing and drive-root launch paths;
- credential members (`authorization`, `apiKey`) and an invalid generation id.