# Proposal

## Why

A team that uses the .NET `morphir` host cannot run the extensions the rest of the ecosystem already publishes. The Python, Avro, OpenAPI and Rust bundles are Extism modules, and the Gleam and new Elm extensions are core WASM modules. The Rust CLI and the MoonBit CLI run them; the .NET host has no WASM runtime at all.

Two approved proposals already depend on that missing host. `add-bounded-model-access` needs a qualified .NET WASM generation path, and `add-deployment-and-acquisition` must be able to say whether an installed WASM extension is ready on each .NET offering.

## What Changes

Follow one module from disk to an answered request. A developer points the .NET host at the published Python extension, `morphir-python-binding`, a 4.7 MB Extism module:

```text
module bytes -> classify imports -> instantiate under limits -> one handle call per MEP message
                     |                      |                            |
              refuse unknown         256 MiB, deadline,           guest asks for a file or
              imports by name        instruction budget           the network: refused
```

- Give the two WASM ABI profiles a normative, host-neutral definition in this repository. `morphir-bytes-v1` and `extism-kernel-v1` are named in parent documents today, but their only definitions are code in MoonBit, Rust and Gleam. Those sources already disagree on one host-function signature.
- Add a WASM extension runtime to the .NET host that runs `morphir-bytes-v1` guests first and `extism-kernel-v1` guests second, on one engine with one set of limits.
- Give every guest the same sandbox: a memory ceiling, a call deadline, an instruction budget, and no file, network, environment or configuration access unless the profile's policy allows it.
- Ship the runtime in all four .NET offerings (`native-aot`, `self-contained`, `framework-dependent`, `dotnet-tool`) on the six supported platform pairs. An offering or platform without the engine reports the runtime as unavailable; it does not fail at first use.
- Add a stdio worker mode to the .NET host with the same shape as the MoonBit worker mode, so a conformance runner can drive a .NET-hosted guest over plain stdio, whichever host that runner ends up living in.
- Add a shared host-qualification corpus: small crafted modules for each refusal and limit, plus the published guests the generic guest profile already uses. .NET qualifies against it first; MoonBit already implements the behavior and can adopt the corpus without changing it.
- Record the Rust host's `morphir_get_workspace_info` signature difference as a known deviation. Fixing the Rust host is follow-up work and does not gate this change.

This change does not add product commands that select a WASM generator or analyzer, user-granted host capabilities, extension installation, or a persistent compiled-module cache. Those consume this runtime and are tracked separately.

## Capabilities

### New Capabilities

- `mep/wasm-execution-profiles`: the two WASM ABI profiles, how a host classifies a module, the byte-call framing of MEP messages, the host-function policy, the resource bounds and the failure codes every WASM host shares.
- `extensions/dotnet-wasm-host`: what the .NET host adds on top of the shared profiles: availability per offering and platform, loading from configuration, in-process execution and cancellation, the worker mode and packaging evidence.
- `mck/wasm-host-qualification`: the shared corpus and report that qualify a WASM host independently of the guests it runs.

### Modified Capabilities

None. `mep/generic-guest-profile` is unchanged: it qualifies a guest and says nothing about hosts. This change reuses its kit and fixed package as host evidence without altering its cases or results.

Adoption changes two morphir-dotnet specs in that repository's own change: `extension-registry`, whose delivery value is currently fixed to `built-in`, and `mep-protocol`, whose single-message dispatch exists only on the guest side.

## Tracking

- OpenSpec change: `openspec/changes/add-dotnet-wasm-extension-host/`.
- Prerequisite for: task 5.2 of `add-bounded-model-access` and group 7 of `add-deployment-and-acquisition`. Both name this change as the separate host proposal.
- Roadmap: morphir-dotnet's approved extension-model PRD, steps 2a (runtime part) and 5. That PRD approves no step for implementation until an OpenSpec change is approved, so morphir-dotnet needs a repository-local change that adopts these requirements.
- Related issues: [finos/morphir#965](https://github.com/finos/morphir/issues/965) (host qualification), [finos/morphir-dotnet#326](https://github.com/finos/morphir-dotnet/issues/326) (Extism integration design) and [finos/morphir-moonbit#297](https://github.com/finos/morphir-moonbit/issues/297) (public stdio host). This proposal does not claim to close any of them.
- Owning Beads epic: pending. The shared Dolt database still reports the merge conflict that blocked the two sibling proposals, and no issue id exists. Create the epic and repository-specific children once the tracker is writable. Do not run `bd dolt push` outside the guard script.

## Impact

This repository owns the profile contract, the crafted qualification modules and their fixed expectations. These are data and do not depend on where the conformance runner lives; that home (Rust today, the .NET or MoonBit host intended) is decided outside this change. morphir-dotnet owns the runtime, the worker mode and the packaging. No submodule pin or implementation changes are part of this proposal.

morphir-dotnet gains its first native dependency. The Wasmtime engine adds about 10.6 MB to the Native AOT executable, measured on macOS arm64 only, and `dotnet-morphir` changes from one platform-neutral tool package to a set of platform-specific packages. Both are user-visible and need release notes and updated installation guidance.

The profile contract starts at `0.1.0-draft.1`. It describes existing guest behavior and mints no new MEP or IR version. Published bundles need no change to run.

First delivery covers Windows x64/ARM64, macOS x64/ARM64 and Linux glibc x64/ARM64. Linux musl is reported as unsupported for the WASM runtime. Browser hosting, the Component Model and WIT are out of scope.
