<!-- Copyright 2026 FINOS; SPDX-License-Identifier: Apache-2.0 -->
# Proposal

## Why

Morphir's pinned OpenSpec bundle predates the published narrative authoring
guidance. A contributor following design instructions should receive that
guidance together with Morphir's concrete examples and contract rules.

## What Changes

- Adopt the released Mission Control tools 0.1.2 binary through mise and regenerate
  its managed html-design bundle and ownership lock with the released installer.
- Add the approved Morphir authoring rules in `openspec/config.yaml` and document
  narrative designs and the released guidance in the developer guide.

## Capabilities

### New Capabilities

None. This is a docs/tooling adoption with `skip_specs: true`.

### Modified Capabilities

None. Morphir runtime behavior and versioned contracts are unchanged.

## Tracking

Change: `adopt-openspec-narrative-guidance`.
[Adoption PR #1145](https://github.com/finos/morphir/pull/1145) records the verification and scope. Beads task creation is
deferred because the shared Dolt database rejected the transaction with an
existing merge conflict; no issue identifier was allocated.

## Impact

Only the Mission Control tools pin, installer-owned bundle and lock, project
authoring policy, this change record and `docs/developers/openspec.md` are affected.
The source release is
[`tools-v0.1.2`](https://github.com/moonrockz/mission-control/releases/tag/tools-v0.1.2)
at `17305df4d80f01d0db3e584976ee0423a2cc3574`.
The main CLI, ecosystem pins and other proposals are outside this adoption.
