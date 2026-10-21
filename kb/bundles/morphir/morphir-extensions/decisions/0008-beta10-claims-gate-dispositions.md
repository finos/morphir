---
type: Decision Record
title: Beta.10 keeps the claims drafts and current probe boundaries
description: Beta.10 records parsed-value claim comparison and WASM probe limits, defers signatures and process sandboxing, and retains the draft formats.
state: Accepted
decided: 2026-10-21
tags: [extensions, capabilities, distribution, compatibility, release]
status: stable
sources:
  - id: spec
    resource: https://github.com/finos/morphir/discussions/921
    title: Capability claims working specification
  - id: host
    resource: https://github.com/finos/morphir/tree/8c12619d54104fc09a1aad9b01ad8db0a953485e
    title: Parent host baseline
  - id: rust
    resource: https://github.com/finos/morphir-rust/tree/6cc141cf2095b5d61badb97a2b6f1442534188ca
    title: Pinned Rust implementation baseline
---

# Beta.10 keeps the claims drafts and current probe boundaries

For `0.4.0-beta.10`, the five claims release gates have these dispositions. They preserve current behavior and close the release decision, including explicit postponements.
The [capability claims design](/design/capability-claims.md) remains the narrative home.

| Gate | Disposition on 2026-10-21 |
| --- | --- |
| `morphir-o4qc.1`, #921 Q1 | Compare parsed claim values. Object key order and whitespace do not matter; arrays retain order. Do not add a canonical byte encoding or numeric normalization rule. |
| `morphir-o4qc.2`, #921 Q2 | Keep WASM publication and installation unprobed, with `claimCheck: unchecked`. Packaging reads claims from the exact guest bytes it ships. |
| `morphir-o4qc.3`, #921 Q3 | Postpone signing claim sets until publisher-authenticity policy defines the signed subject and verification rules. |
| `morphir-o4qc.4`, #921 Q4 | Postpone an operating-system sandbox for process probes. Keep the current launch controls and disclose the process's ambient user rights. |
| `morphir-o4qc.5`, format stability | Keep `claimsVersion: 0.1.0-draft.2` and descriptor, index and catalog `schemaVersion: 2.0.0-draft.2`. Require a separate adoption and stability review before promotion. |

## Summary

The release needs an accurate account of the implemented checks. A probe confirms agreement with guest-reported claims; it does not establish publisher identity or prove capability correctness. Neither deferred security mechanism is required to use the existing MCK runner.

| Option | Outcome | Why |
| --- | --- | --- |
| Record parsed-value comparison | Chosen | Matches the host and SDK |
| Introduce canonical JSON bytes or broader numeric equivalence now | Rejected | Neither is implemented by the comparison code |
| Keep WASM publish and install unchecked | Chosen | Packaging already describes the shipped bytes; the host does not probe WASM here |
| Require a new WASM publication probe for beta.10 | Rejected | Changes the runtime boundary without a demonstrated release prerequisite |
| Defer signatures until publisher-authenticity policy exists | Chosen | A digest alone does not identify a publisher |
| Add claim signatures independently now | Rejected | There is no agreed signing or verification policy |
| Defer process sandboxing with the current limitation disclosed | Chosen | Cross-platform confinement requires its own design and tests |
| Require a new process sandbox for beta.10 | Rejected | Existing launch controls do not implement confinement |
| Retain the exact draft formats | Chosen | A CLI beta does not establish contract stability |
| Promote the claims and record formats now | Rejected | Adoption and compatibility review remain separate work |

## Why

### Parsed values, without a new canonical encoding

The SDK's [`CapabilityClaimSet::check_claims`](https://github.com/finos/morphir-rust/blob/6cc141cf2095b5d61badb97a2b6f1442534188ca/crates/morphir-extension-sdk/src/claims/agreement.rs) serializes parsed claim sets to `serde_json::Value`. It compares object members recursively and uses value equality for arrays and scalars. Distribution's [`claims_differences`](https://github.com/finos/morphir-rust/blob/6cc141cf2095b5d61badb97a2b6f1442534188ca/crates/morphir-distribution/src/repository_authoring/process.rs) uses the same approach. [`ClaimsRecord::check_described`](https://github.com/finos/morphir-rust/blob/6cc141cf2095b5d61badb97a2b6f1442534188ca/crates/morphir-distribution/src/extension_format/claims.rs) delegates to the SDK for supplied claims. Converted version-1 declarations retain their narrower session-agreement rules.

Object key order is immaterial. Arrays remain ordered, including lists whose names suggest sets. Numbers follow `serde_json::Value` equality after parsing; this decision does not promise that every alternate number spelling compares equal. In particular, consumers must not assume integer and floating-point representations such as `1` and `1.0` are interchangeable. No canonical JSON bytes are defined for hashing or signing.

The existing SDK test [`direct_claim_sets_must_match_in_both_directions`](https://github.com/finos/morphir-rust/blob/6cc141cf2095b5d61badb97a2b6f1442534188ca/crates/morphir-extension-sdk/src/claims/agreement/tests.rs) covers complete-claim mismatches. Session agreement remains a different operation and can accept a subset of claimed capabilities.

### WASM claims remain unchecked at publication and installation

Distribution's [`process::verify`](https://github.com/finos/morphir-rust/blob/6cc141cf2095b5d61badb97a2b6f1442534188ca/crates/morphir-distribution/src/repository_authoring/process.rs) initializes records as unchecked and probes only process artifacts for the current platform. The parent [`install probe`](https://github.com/finos/morphir/blob/8c12619d54104fc09a1aad9b01ad8db0a953485e/crates/morphir/src/commands/extension/probe.rs) also returns the unchecked record for WASM. Its regression test is [`wasm_keeps_claims_unchecked`](https://github.com/finos/morphir/blob/8c12619d54104fc09a1aad9b01ad8db0a953485e/crates/morphir/tests/cli_integration/extension_probe.rs).

WASM packaging's [`read_claims`](https://github.com/finos/morphir-rust/blob/6cc141cf2095b5d61badb97a2b6f1442534188ca/scripts/extension_packaging/claims.py) writes a private snapshot of the exact supplied guest bytes, then runs `extension-claims` against that snapshot. The [`extension-claims` helper](https://github.com/finos/morphir-rust/blob/6cc141cf2095b5d61badb97a2b6f1442534188ca/crates/morphir-host-native/src/bin/extension-claims/main.rs) calls `describe`, validates the answer and preserves its original JSON members. This packaging check is distinct from a publisher or installer probing an artifact. Digests still protect artifact integrity; sessions still check agreement.

### Security work remains explicit follow-up work

The distribution design leaves [publisher authenticity](https://github.com/finos/morphir/blob/8c12619d54104fc09a1aad9b01ad8db0a953485e/docs/design/draft/extensions/distribution-and-acquisition.md#open-questions) open. A signature needs a subject, trusted signer identities and verification policy. Choosing coverage for claims before those decisions would imply an authenticity guarantee the current release cannot make. Q3 is formally postponed until that work begins.

The [protocol security rules](https://github.com/finos/morphir/blob/8c12619d54104fc09a1aad9b01ad8db0a953485e/docs/design/draft/extensions/protocol.md#security-and-permissions) already disclose the absence of a strong process sandbox. Environment filtering, an explicit working directory, timeouts and process cleanup do not confine filesystem or network access. Process probes run with the user's rights; `--no-probe` skips the install probe. Q4 is formally postponed until a platform-specific confinement design can be qualified.

### Draft status remains independent of the CLI release

Decision [0007](/decisions/0007-extensions-make-capability-claims.md) establishes the draft.2 spelling and draft.1 conversion. This release preserves those rules and supported legacy records. Releasing another CLI beta is insufficient evidence that extension authors can rely on a stable claim vocabulary, agreement rule and signing policy. The stability review must assess adoption and supported-reader compatibility before selecting released contract versions.

## Consequences

These dispositions resolve the beta.10 decision gates without adding runtime behavior. They do not advertise signatures, a process sandbox or a WASM publication/install probe. The released contracts remain exact drafts. The MCK, MEP model transport, workspace discovery and Workbench profiles keep their own versions and qualification requirements.

## Revisit when

| Gate | Reopen condition |
| --- | --- |
| Q1 | A cross-language comparison mismatch or signing design requires canonical bytes or a wider numeric-equivalence rule; specify fixtures before changing comparison. |
| Q2 | A consumer needs installation/publication-time WASM execution evidence beyond packaging and session checks; define runtime permissions, bounds and provenance first. |
| Q3 | Publisher-authenticity work defines signing subjects, trust roots and verification; decide claim coverage in that design. |
| Q4 | An operating-system sandbox is proposed with supported-platform behavior and tests; preserve a clear account of unsupported platforms. |
| Stability | Third-party adoption or a proposal to promise released compatibility warrants an explicit format-stability review, including old-record and guest compatibility evidence. |
