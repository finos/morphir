# MEP guest kit report

A guest kit report records one run of the generic JSON Library guest kit,
[`guest-generic-json.json`](guest-generic-json.json), profile
`generic-json-library-v1`, against one guest through one host. This document
fixes what a report holds, how a report check rebuilds the run's plan, how the
verdict is computed and when a report check refuses a report. The requirements
it serves are in `openspec/specs/mep/generic-guest-profile/spec.md` and the
change `drop-generic-guest-legacy-tier`, which gives the kit one session on MEP
`0.2.0-draft.1`.

A report is a document of the MEP guest kit family, version `0.1.0-draft.1`.
Its first member is `$schema`, with the value
`https://morphir.finos.org/schemas/mep-guest-kit/0.1.0-draft.1/report.schema.json`.
The schema is published from
[`website/static/schemas/mep-guest-kit/0.1.0-draft.1/`](../../../website/static/schemas/mep-guest-kit/0.1.0-draft.1/report.schema.json).
The Rust `morphir mck mep guest-run` writes an earlier, unversioned report for
the two-tier plan; no check reads it under this contract.

A WASM host's qualification report cites a passing guest kit report by its
digest. That report is defined separately, in
[`wasm-host-report.md`](wasm-host-report.md).

## What a report holds

| Member | Content |
| --- | --- |
| `suite` | The kit file's path, its profile and contract version, and its SHA-256. |
| `runner` | The runner's name and version. |
| `host` | The executable the runner started, its SHA-256 and its arguments. A host that runs a WASM guest also records its `offering` and `platform`. |
| `artifacts` | At least one pinned file with its SHA-256: the guest module, the guest executable, or another file the run depends on. |
| `plan` | The language and the IR versions the recorded `describe` observation selects, or `null` when it selects nothing. |
| `cases` | One entry for each planned case, in plan order. |
| `unmatched` | Every message the runner read that answers no request of the case during which it arrived, with that case's id. Empty when there is none. |
| `totals` | The number of cases and the count of each outcome. |
| `verdict` | Whether the guest qualified, and every reason it did not. |

A case entry holds the `caseId`, the `outcome`, the `request` the runner sent
and what it `observed`. It may hold a `failure` message. A case that was not
run has `request` and `observed` both `null`.

An observation is one of four kinds:

| Kind | Members | When |
| --- | --- | --- |
| `response` | `message`, the complete JSON-RPC response | A request was answered |
| `silent` | none | A notification gave no output before the runner went on |
| `exit` | `exitCode`, `stdoutClosed` | The guest process ended after `morphir.exit` |
| `incomplete` | `reason`, one of `timeout`, `end-of-stream`, `invalid-frame` and `process-exited`; optionally `detail` | Nothing complete arrived |

The `request` is the JSON-RPC message as the runner sent it, and `message` is
the response the runner correlated with it by the operation it submitted, never
by searching for a matching id. A report records the parsed JSON values, not the
framed bytes, because a host may parse and write a message again. A message that
answers no request of its case goes to `unmatched` and never stands in for a
response.

A notification case that ran also records its `delivery`:

| Delivery | Meaning |
| --- | --- |
| `delivered` | The host passed the notification to the guest: a process host wrote it to the guest's stdin, or a WASM host called `handle` with it. |
| `withheld` | The host did not pass it on, as its contract requires. A WASM host withholds every notification from an Extism guest whose `model-initialize` result does not set `capabilities.notificationDelivery` to `call`. |
| `unknown` | The runner cannot tell. |

A silent result after a withheld notification shows only that the host followed
its contract, which is all the case can show for such a guest.

## The plan

The report check rebuilds the plan from the recorded `describe` observation
alone. The selection follows the profile's requirements:

1. The claim must list `0.2.0-draft.1` in `protocolVersions`. Another listed
   version, such as `0.1`, is not read.
2. The language is the first kit language, in lexical order of its id, that
   the claim names both as a frontend language and as a backend target.
3. An IR version of `3.0.0` and `4.0.0` is selected when the frontend and the
   backend both claim it (`3` and `3.0.0` are the same claim), and the claim's
   `modelTransport.tuples` hold the `morphir.frontend.compileModel` and
   `morphir.backend.generateModel` tuples with profile `morphir-ir`, codec
   `morphir-json`, envelope `0.1.0-draft.1` and that IR version.

When the claim selects no language or no IR version, `plan` is `null` and the
plan is the single case `describe`, which fails.

Otherwise the plan has 11 fixed cases and 5 for each selected IR version, in
this order:

1. `describe`, `model-initialize`, `model-initialized-silent`,
   `unknown-notification-silent`.
2. For each selected IR version, `3.0.0` before `4.0.0`: `compile-model`,
   `generate-model`, `roundtrip-model`, `generate-model-independent` and
   `roundtrip-model-independent`, each with the suffix `-vthree` or `-vfour`.
3. `bad-digest`, `malformed-source`, `unknown-method`, `describe-immutable`,
   `model-shutdown`, `after-shutdown`, `model-exit`.

A guest that selects both IR versions has 21 cases, and one that selects one
has 16. A case whose id ends in `-silent` expects a `silent` observation,
`model-exit` expects `exit`, and every other case expects `response`.

## Outcomes

A case is `passed`, `failed` or `not_run`.

- The runner computes `passed` or `failed` from the case's comparison, as the
  profile's requirements state it. An observation of another kind than the case
  expects, or an `incomplete` one, is `failed`.
- A runner may stop after a failed case. Every later planned case is then
  `not_run`. A runner may also go on, and a later case keeps its own outcome.
- A runner never stops otherwise, so a `not_run` case comes after a failed one,
  and only `not_run` cases follow it.
- A notification case passes only when its notification was `delivered`, or
  `withheld` from a guest that did not ask for `call` delivery. A notification
  withheld from a guest that asked for it, or of `unknown` delivery, fails the
  case.
- A case during which an `unmatched` message arrived fails.

## The verdict

`verdict.qualified` is true exactly when `verdict.reasons` is empty. The
reasons are, in plan order, one for each case that did not pass:

| Reason | When |
| --- | --- |
| `case_failed` | The case's outcome is `failed`. |
| `case_not_run` | The case's outcome is `not_run`. |

Each carries the `caseId`. A guest that selects nothing is not qualified,
because its `describe` case fails.

## When a report is refused

A report check computes the verdict only for a report it accepts. It refuses a
report, without a verdict, for any of these, and reports every refusal that
applies in this order:

| Refusal | When |
| --- | --- |
| `identity_missing` | The runner's name or version, or the host's executable or digest, is absent or empty, or no artifact is pinned. |
| `kit_mismatch` | `suite.sha256` differs from the kit file the report is checked against. |
| `plan_mismatch` | `plan` differs from what the recorded `describe` observation selects. |
| `case_inventory` | The cases are not exactly the planned cases, once each, in plan order. A report that holds a case of the removed legacy tier, such as `initialize` or `compile-vthree`, is refused here. |
| `outcome_inconsistent` | An outcome breaks a rule above that needs no comparison: a case that ran after a `not_run` case, a `not_run` case with no failed case before it, a case recorded with no observation that is not `not_run`, a passed case whose observation is of the wrong kind, a passed `describe` that selects nothing, a passed notification case whose delivery does not allow it, or a passed case named by an `unmatched` entry. |
| `totals_mismatch` | `totals` differs from the counts of the recorded outcomes. |
| `verdict_mismatch` | The recorded verdict differs from the computed one, in `qualified`, in a reason or in their order. |

A runner's report check also has three refusals that need the run's own data,
in this order after `identity_missing`:

| Refusal | When |
| --- | --- |
| `artifact_changed` | The host executable or a pinned artifact no longer has its recorded digest. |
| `request_mismatch` | A recorded request differs from the one the runner builds for that case from the kit and the observations before it. Request ids are numbers counted from 1. |
| `comparison_mismatch` | A recorded outcome differs from the one the runner computes from the recorded observation. |

An edited claim is refused through the plan: a changed `describe` observation
selects another plan, which no longer agrees with `plan` and the recorded
cases. An edit that leaves the plan the same is refused through the
comparisons, because `describe-immutable` compares the second `describe` with
the first.

## Fixed controls

[`guest-report.controls.json`](guest-report.controls.json) holds the controls a
report check must satisfy. Its schema is
`https://morphir.finos.org/schemas/mep-guest-kit/0.1.0-draft.1/report-controls.schema.json`.
The file states the plan's case lists, the reasons and refusals, and one base
run: a constructed claim with the JSON tuple pair at both IR versions, in which
every case passes. Each control says how its report differs from the base and
gives the verdict and case count, or the refusals.

| Member | Effect |
| --- | --- |
| `claimPatch` | A JSON merge patch (RFC 7386) on the claim the guest made. The plan follows it. |
| `editRecordedClaim` | A merge patch on the stored `describe` observation only, after the plan was built. |
| `recordedPlan` | Record this `plan` in place of the selected one. |
| `runner`, `host` | Replace the named members. `null` removes one. |
| `suiteSha256` | Record this kit digest. |
| `outcomes` | Record these outcomes. A `not_run` case has no observation. |
| `stopAfter` | Fail the named case and record every later case as `not_run`. |
| `removeCases`, `addCases`, `swapCases` | Leave out, insert after a named case, or exchange cases. |
| `storedTotals`, `storedVerdict` | Record these in place of the computed totals or verdict. |
| `advertisesCall` | The guest's `model-initialize` result asks for `call` delivery, so its notifications are `delivered`. Without it they are `withheld`. |
| `deliveries` | Record these deliveries for the named notification cases. |
| `unmatched` | Record an unmatched message during each named case. |

Every reason, refusal and scenario the file names has exactly one control.
`mise run spec:mep-guest-report-check` checks that, and checks each control
against a reference implementation of the plan and outcome rules in
[`tools/check-guest-report.ts`](../../../tools/check-guest-report.ts). The
reference does not build requests or run comparisons. A runner adopts the
controls by building a report in this format for each one and requiring its
report check to give the control's result, and it tests the three runner
refusals with fixed observations of its own.

[`fixtures/reports/guest-abridged.report.json`](fixtures/reports/guest-abridged.report.json)
shows the members on a guest that selects nothing. It validates against the
schema.
