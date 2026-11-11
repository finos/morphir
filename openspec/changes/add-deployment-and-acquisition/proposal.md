# Proposal

## Why

Users should be able to acquire Morphir and its language tools without assembling runtimes, extension packages and configuration by hand. Four .NET delivery options need one predictable setup experience that also leaves room for other hosts and independently released extensions.

## What Changes

> **User-approved delivery priority, 11 November 2026.** The next user-facing
> milestone is a real local Windows x64 journey through the actual native
> morphirup manager and official self-contained managed Morphir folder. An
> explicitly supplied, digest-pinned local developer candidate is installed,
> selected and explained, then compiles the fixed F# package and generates the
> frozen F# output. The installed selection repeats offline with system .NET
> unavailable. Deliver the candidate and a short exact-command walkthrough for
> user feedback before extending breadth. The local provenance delta is the
> separately versioned [local candidate contract](../../../docs/spec/toolchain/local-developer-candidate.md).
> It never fabricates an authenticated recipe or production release. External
> providers, exact portable-lock CI restore and recovery extend this same
> working path next. All four offerings, platforms and final security and
> acceptance requirements remain; WASM completion is not a prerequisite for
> this managed slice. No release version, tag or production publication is
> authorized by this sequencing change.

Follow a developer who installs Morphir on a machine without .NET, selects the F# toolset, compiles a small package and generates F#. A colleague restores the checked-in toolchain selection in CI, offline after acquisition, with the same providers and exact artifact identities.

```text
bootstrap morphirup -> select host + deployment + toolset
                   -> verify and stage artifacts -> activate locked toolchain
                   -> morphir compile -> model -> morphir generate
```

- Define the .NET offerings: Native AOT `morphir`, self-contained managed `morphir`, framework-dependent `morphir`, and the existing managed `Morphir.Tool` package exposing `dotnet-morphir`. Separate deployment, acquisition channel and toolset selection.
- Propose a standalone, runtime-independent `morphirup` manager with bootstrap, setup plans, side-by-side installation, project selection, locked restore, explicit updates, rollback and diagnostics. Its first managed toolchain implementation is .NET; the identity model also accommodates MoonBit and future hosts without making their delivery a gate here.
- Coordinate existing tool and extension acquisition contracts rather than introducing a parallel extension repository or MEP installer. Keep direct archives, .NET tools and package-manager installations supported and record who owns updates.
- Make F# the first complete setup preset. Preserve the built-in F# backend, acquire the F# frontend process guest when needed, and publish an independently acquirable F# backend process delivery for hosts that need it. Package compiler services with the frontend; require neither an SDK nor a system runtime for the standalone F# path.
- Add a project toolchain request, an exact portable lock, platform artifact selection, offline execution and transactional activation. Keep toolchain state in Morphir Home and build artifacts in the configurable workspace out root.
- Publish narrative diagrams, proposed command examples, recovery journeys and release qualification for Windows, macOS and Linux. Qualify extension hosting separately from installation success.

## Capabilities

### New Capabilities

- `deployment/dotnet-profiles`: the supported .NET deployment offerings, capabilities, prerequisite reporting and release identity.
- `acquisition/toolchain-management`: bootstrap, acquisition ownership, side-by-side lifecycle and safe activation through `morphirup`.
- `acquisition/project-toolchains`: project requests, exact locks, selection precedence and reproducible offline restore/run behavior.
- `extensions/toolset-setup`: capability-based extension setup, F# frontend/backend delivery and verifiable readiness.

### Modified Capabilities

None in this planning repository. Existing MEP guest requirements remain unchanged. Adoption must update morphir-dotnet's host availability and delivery reporting in its own `extension-registry` spec; executable names alone will no longer identify a deployment profile.

> **Note added 10 November 2026, after approval.** The maintainer later decided (9 November 2026, recorded on finos/morphir#1146) that MEP `0.1` is not supported and that the whole MEP 0.2 line is: every prerelease of `0.2.0` and every final `0.2.x`. So the sentence "Existing MEP guest requirements remain unchanged" no longer holds for a guest that speaks only MEP `0.1`: no recipe can bind it. The toolchain contracts state the rule in `docs/spec/toolchain/index.md#mep-versions`. The approved text above is left as approved.

## Tracking

> **Selection decisions, 11 November 2026.** The maintainer approved portable project/workspace extension pins resolved from local inventory, a `MORPHIR_EXTENSION_OVERLAY` above those pins, and explicit `extension_id`/`id` configuration members that preserve existing path-string meanings. The parent owns their schema URLs, member tables, paths and fixed cases; neither implementation creates an unversioned private replacement. Explicit local-source installation or explicitly enabling staged mode supplies unsigned developer consent. An absent setting that inherits `auto` does not. Global staged/file installs record a generated one-release local repository and a `local-developer` label, which is not publisher authentication. These decisions refine the selection and acquisition requirements below; they do not mark implementation or qualification complete.

> **Configuration boundary, 11 November 2026.** Extension table keys retain their identity role, so an explicit `id` must match the key. Installed identities and existing launch-source members are mutually exclusive: refuse `id` with `path`/`url`/`command`, or frontend `extension_id` with `extension`, before selection or launch. There is no alias or implicit source precedence. The candidate's fixed TOML cases cover these refinements; implementation and full-family cutover remain gated.

> **Implementation correction, 10 November 2026.** The maintainer directed removal of the parent Rust reference crate and use of the .NET implementation for acquisition contract checks. Specifications, schemas, case manifests, fixed fixtures and expected results stay in finos/morphir. Parent CI invokes the conformance tests in a pinned finos/morphir-dotnet checkout against the current parent corpus. No second reader or resolver is maintained here, and source-test success is not release or platform qualification. This note does not change the approved task wording or contract versions.

> **Integration note, 11 November 2026.** Merged #1147 supplies that .NET corpus job and its metadata-only gates. Its contract-test pin, `f89dda45` in `.config/toolchain-contract-tests.json`, is separate from the CLI delivery tuple, now the merged #590 commit `0885f172` and still a marked release candidate. Merged #1152's family-version policy permits any valid SemVer prerelease label; it does not renumber these fixed acquisition fixtures. Merged #1151's extension package decisions remain controlling: VERIFY-B checks structure at launch and hashes fully at install/on request; LAUNCH-A launches from the shared store under a process-tree lease and collects explicitly. This note changes neither the approved narrative and decision identifiers nor qualification status.

- Approval: the user approved this proposal and its narrative design on 9 November 2026. Implementation tasks remain unstarted.
- OpenSpec change: `openspec/changes/add-deployment-and-acquisition/`.
- Origin: this deployment/acquisition discussion, following [discussion #214](https://github.com/finos/morphir/discussions/214). This does not claim #214 is a deployment specification.
- Related change: `add-bounded-model-access`. Its WASM generation path requires a qualified host; bounded readers and name compaction do not depend on this manager.
- Separate prerequisite: the agreed .NET WASM-host change still needs its own proposal and tracking. This change specifies acquisition and profile qualification, not the WASM engine implementation.
- Beads/GitHub owning links are pending. The preceding planning work encountered a shared Dolt merge conflict and obtained no issue id. Read-only inspection on 9 November confirmed one conflict in `issues`. Do not overwrite that conflict or invent links; create the owning epic and repository-specific tasks once the shared tracker is writable. Do not run `bd dolt push` under the Windows restriction in AGENTS.md.

## Impact

The parent repository owns shared acquisition contracts, fixed examples and qualification expectations. morphir-dotnet owns its publish profiles, `morphirup` executable, managed entry points and F# packages. MoonBit adoption is a follow-up using the same contracts. No submodule pin or implementation changes are part of this proposal.

> **Note added 10 November 2026, after approval.** The maintainer authorized moving official CLI delivery to finos/morphir (finos/morphir#1153, following Decisions 15 and modified 16A on #1146). morphir-dotnet still owns the CLI source, its publish profiles, `morphirup`, the managed entry points and the F# packages. finos/morphir now also owns the official CLI builds and their orchestration, acquired-artifact qualification, releases, installation docs and FINOS registry and channel governance, and pins the source as `ecosystem/morphir-dotnet`; the Rust CLI is deleted. That change is `openspec/changes/move-cli-delivery-to-umbrella/`. The approved text above is left as approved.

New toolset recipe, toolchain request, lock, installation receipt and manager result contracts start at `0.1.0-draft.1`, with exact draft support. Reuse existing tool/extension document contracts at their actual versions; do not rename their numeric or draft versions in place. Any extension to a released descriptor uses a separately reviewed compatible addition or next-major draft. MEP and IR versions are independent.

First delivery covers six native platform pairs: Windows x64/ARM64, macOS x64/ARM64 and Linux glibc x64/ARM64. Unsupported artifacts are reported explicitly. Linux musl, additional package-manager integrations and managing an external SDK installation follow later. The initial public acquisition paths are direct archives/bootstrap and the existing .NET tool channel.
