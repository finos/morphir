# Tasks

This is the OpenSpec implementation breakdown. Beads remains the task tracker. No bead exists yet: the shared database rejects writes with a Dolt merge conflict. Create the bead and link it here after the conflict is resolved and before claiming a task.

Dependencies: #1148 merged on 10 November 2026 as `ac4ec5fc8`, so decision record 0004 making finos/morphir-dotnet the runner's home is now on `main`. Group 1 changes documentation only and can start once this proposal is approved. Group 2 is in finos/morphir-dotnet and needs that repository's own approved OpenSpec change. Group 3 needs group 2's evidence.

## 1. Kit documentation, finos/morphir

- [ ] 1.1 Rewrite the section "Generic JSON Library profile" of `spec/mep/mck/README.md` for one session: the selection rule with the JSON tuple pair (design SEL-1), the 11 fixed cases and the five per IR version in the order of the design's table (TIER-1), and the request each of the five moved checks sends (LIFE-1). Remove the paragraph on the legacy tier. Verify that the case order in the README equals the design's table, and that `git grep -n -i "legacy" spec/mep/mck/README.md` shows no hit inside that section.
- [ ] 1.2 In the same section, name the conformance runner in finos/morphir-dotnet as the profile's runner, and state that the Rust `morphir mck mep guest-run` runs the earlier plan and that its reports fail the changed report check (design RUN-1). Replace the `guest-run` example with the .NET runner's command once task 2.3 has one. Verify that `git diff --stat main -- crates/ spec/mep/mck/guest-generic-json.json` is empty, so the kit file and the Rust runner are unchanged (KIT-1).
- [ ] 1.3 Record in the README which of the kit's first guests can qualify: Python `0.6.0` can; Python `0.4.2` and the SDK fixture of finos/morphir-moonbit speak only MEP `0.1` and cannot until they are rebuilt. For the Gleam `0.4.0` guest, read its `describe` result and state whether it claims `0.2.0-draft.1` with the JSON tuple pair. Add a CHANGELOG entry for the breaking change. Verify `openspec validate drop-generic-guest-legacy-tier --strict` and `mise run openspec:verify` pass.
- [x] 1.4 Define the report of a run in `spec/mep/mck/guest-report.md`, with a published schema in the MEP guest kit family `0.1.0-draft.1`: identities, the plan rebuilt from the recorded `describe` observation, one entry per planned case with the request sent and what was observed, notification delivery, unmatched messages, outcomes, the verdict and the named refusals. Verify `mise run spec:mep-guest-report-check`: every reason, refusal and scenario has exactly one fixed control in `spec/mep/mck/guest-report.controls.json`, including an edited claim, a removed or reordered case, legacy-tier cases and an edited verdict.

## 2. Runner, finos/morphir-dotnet

- [ ] 2.1 Adopt these requirements in a morphir-dotnet OpenSpec change, and there remove the statements that a run through the .NET host covers the model tier only and is not a complete run of the kit. Verify it validates strictly and links this change; tasks 2.2 to 2.4 do not start before it is approved.
- [ ] 2.2 Add failing tests for the one-session plan from fixed `describe` results, then build it in the guest kit code of `Morphir.Conformance`: selection, case order and the request of each case. Verify the plan for a guest with the JSON tuple pair at both IR versions (21 cases), at one version (16 cases) and at a version the backend does not claim; and that a guest which claims only `0.1`, and one with no tuple pair, fail the `describe` case. Verify no request carries `0.1` and that a claim with `frontend.compile` false still selects.
- [ ] 2.3 Add failing tests for the comparisons of the five moved cases, then implement them and expose the run and the report check as commands. Verify from fixed observations: a malformed source answered with a model fails; `-32601`, `-32014` and `-32602` are each required; a changed `describe` result fails; and the report check gives the result of every control in `spec/mep/mck/guest-report.controls.json`, and refuses with `artifact_changed`, `request_mismatch` and `comparison_mismatch` from fixed observations of its own. Document the commands in the contributor guide as internal and experimental.
- [ ] 2.4 Run the plan on the published Python `0.6.0` guest through the MoonBit native CLI's worker mode and through the .NET worker. Verify both reports pass the report check with the same 21 cases, and record them, with the host and module digests, as evidence. Record any case a guest answers differently in a `0.2.0-draft.1` session as a guest defect or a contract question before task 3.1.

## 3. Close the loop, finos/morphir

- [ ] 3.1 Cite the two reports of task 2.4 in `spec/mep/mck/README.md` and update `add-dotnet-wasm-extension-host` task 4.3 and its design, which say a .NET run covers the model tier only. Verify `mise run openspec:verify` and the documentation gates pass.

## Workflow follow-up

- These files capture a proposal for review. Do not begin implementation from this planning turn.
- The Python and MoonBit guest profiles and the model transport corpus still hold MEP `0.1` cases. Whether they drop them is a separate decision (design, open questions).
- The capability's Purpose and the requirement "Recheck from the recorded claim" name `morphir mck mep guest-run` and `report-check`. Align them in a later change if the .NET commands have other names.
- Follow AGENTS.md for review, spec synchronization, archive, tracker closure and release approval.
