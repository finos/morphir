<!-- Copyright 2026 FINOS; SPDX-License-Identifier: Apache-2.0 -->
# Tasks

## 1. Adopt the released guidance

- [x] 1.1 Pin tools 0.1.2, install its released binary with mise, regenerate the managed bundle and lock, and verify `mission-control-tools version --json`, all seven lock hashes and `mise run openspec:verify`.
- [x] 1.2 Add the approved Morphir narrative rules and developer guide, and verify proposal, specs and design instructions contain the shared guidance, local rules and unchanged project context.

## 2. Verify the scoped adoption

- [x] 2.1 Run formatting and whitespace checks, verify the instruction task state and review the changed-file list for ownership limits, unchanged CLI/ecosystem pins and exclusion of the parent proposals.

## Workflow follow-up

- Parent reviewed the scoped adoption and archived this completed record before landing. GitHub approval and CI requirements still gate the adoption PR.
- Record the change and adoption PR in Beads after the shared Dolt conflict is resolved by its owner; no task creation transaction succeeded here.
