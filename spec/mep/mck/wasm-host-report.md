# WASM host qualification report

A host qualification report records one run of the crafted corpus
[`wasm-host.cases.json`](wasm-host.cases.json) against one host executable on
one platform. This document fixes what a report holds, how its verdict is
computed and when a report check refuses a report. The requirements it serves
are in the `mck/wasm-host-qualification` spec of the change
`add-dotnet-wasm-extension-host`.

A report is one of the documents of the WASM host kit family, version
`0.1.0-draft.1`. Its first member is `$schema`, with the value
`https://morphir.finos.org/schemas/mep-wasm-host-kit/0.1.0-draft.1/report.schema.json`.
The schema is published from
[`website/static/schemas/mep-wasm-host-kit/0.1.0-draft.1/`](../../../website/static/schemas/mep-wasm-host-kit/0.1.0-draft.1/report.schema.json).
The corpus was written before the rule that a published schema carries a
family's version, and still names the kit and its version in its own members.

## What a report holds

| Member | Content |
| --- | --- |
| `suite` | The kit and its version, the profile contract's id and version, the SHA-256 of the corpus file and the kit's deadline margin in seconds. |
| `runner` | The runner's name and version. |
| `host` | The executable's path and SHA-256, the profiles the host declares, and its offering, platform and engine. |
| `bounds` | One entry for each of `memoryCeiling`, `instructionBudget` and `callDeadline`, in that order. |
| `guestKitCitations` | The generic guest kit runs cited as positive evidence, at most one for each declared profile. |
| `cases` | One entry for each case of the corpus, in the corpus order. |
| `totals` | The number of cases and the count of each outcome. |
| `verdict` | Whether the host is qualified, and every reason it is not. |

The runner is given the host's offering, platform and engine, because a worker
reports none of them. It is also given the profiles the host declares.
`extism-kernel-v1` is required of every host.

A bound's `declaration` is what the host's `started` events say about it:

- `enforced` or `not-enforced`, when every event that declares the bound says
  the same. A `not-enforced` entry also carries the host's `reason`.
- `inconsistent`, when the events disagree.
- `undeclared`, when no event declares the bound, for example because every
  module was refused before a worker started.

Each bound entry repeats, in `requiredForQualification`, whether the profile
contract requires the bound. The contract requires `memoryCeiling` and
`callDeadline`. `instructionBudget` is optional, because the budget unit is
engine-defined and an engine need not meter.

A case entry holds the case's `caseId`, `appliesTo` and `bounds` as the corpus
gives them, the module's recorded digest and the digest of the file the runner
used, the `outcome`, and the `runs` the runner observed. It may hold a
`deviation` with a tracking link and a note. This contract does not fix the
members of a run: they are whatever the runner needs to compute the outcome
again, and a report is checked by the runner that wrote it.

A runner may record members this document does not name. A report check
ignores them, except that it always computes `verdict` and `totals` itself.

[`fixtures/reports/abridged.report.json`](fixtures/reports/abridged.report.json)
shows the members on three cases. It validates against the schema. It is not a
report a check would accept, because a real report has every case of the
corpus and the observed runs of each.

## Outcomes

A case has one of six outcomes: `passed`, `failed`, `error`, `refused`,
`not_applicable` and `not_enforced`. The first of these steps that applies
gives it:

1. `not_applicable`: the host does not declare the case's `appliesTo` profile.
2. `error`: the module file is missing.
3. `refused`: the module file's digest differs from the corpus. The case is
   not run.
4. `error`: one of the case's bounds is `undeclared` or `inconsistent`.
5. `not_enforced`: the host declares one of the case's bounds not enforced.
6. `error`: the runner could not complete the case's runs, for example because
   a worker did not start.
7. `passed` or `failed`: the corpus conventions applied to the observed runs.

A deviation explains an outcome. It never changes one.

## The verdict

`verdict.qualified` is true exactly when `verdict.reasons` is empty. The
reasons are computed from the report's other members, in this order.

**Bounds**, in the order `memoryCeiling`, `instructionBudget`, `callDeadline`:

| Reason | When |
| --- | --- |
| `bound_undeclared` | The bound's declaration is `undeclared`. |
| `bound_inconsistent` | The bound's declaration is `inconsistent`. |
| `required_bound_not_enforced` | A required bound's declaration is `not-enforced`. |

Each carries the `bound`. An optional bound that is not enforced gives no
reason: its cases are `not_enforced` and the host can still qualify.

**Cases**, in the corpus order:

| Reason | When |
| --- | --- |
| `case_failed` | The case's outcome is `failed`. |
| `case_error` | The case's outcome is `error`. |
| `case_refused` | The case's outcome is `refused`. |

Each carries the `caseId`. The outcomes `passed`, `not_applicable` and
`not_enforced` give no reason.

**Guest kit runs**, for each profile the host declares, `extism-kernel-v1`
first:

| Reason | When |
| --- | --- |
| `guest_kit_missing` | No citation names the profile. |
| `guest_kit_host_mismatch` | The citation's `hostSha256` differs from `host.sha256`. |

Each carries the `profile`. A host does not qualify on crafted cases alone, and
a host that declares `morphir-bytes-v1` needs a published guest of that profile
as well.

A citation holds the path and SHA-256 of a generic guest kit report, the host
digest that report records and the digest of the guest module it ran. A runner
records a citation only for a report that passes the guest kit's own report
check. A report check that is given the cited file checks its digest and runs
that kit's check again.

## When a report is refused

A report check computes the verdict only for a report it accepts. It refuses a
report, without a verdict, for any of these:

| Refusal | When |
| --- | --- |
| `identity_missing` | The runner's name or version, the host's digest, offering, platform or engine is absent or empty. |
| `host_profiles` | The declared profiles are empty, repeated, unknown to the contract, or lack the required profile. |
| `corpus_mismatch` | `suite.corpus.sha256` differs from the corpus the report is checked against. |
| `case_inventory` | The report's cases are not exactly the corpus's cases, once each, in the corpus order. |
| `outcome_inconsistent` | A recorded outcome cannot follow from the declarations: for example `passed` for a case whose bound is not enforced, or `not_applicable` for a declared profile. |
| `totals_mismatch` | `totals` differs from the counts of the recorded outcomes. |
| `citation_invalid` | A citation names a profile the host does not declare, or two citations name one profile. |
| `verdict_mismatch` | The recorded verdict differs from the computed one, in `qualified`, in a reason or in the order of the reasons. |

A checker reports every refusal that applies, in the order of this table.

`outcome_inconsistent` is the part of the outcome rule that needs no
observation. A runner's report check also computes each outcome again from the
recorded runs and refuses a report whose recorded outcome differs. A report
check that is asked about a citation, for example by release metadata, also
refuses a report whose offering or platform is not the one it is cited for.

## Fixed controls

[`wasm-host-report.controls.json`](wasm-host-report.controls.json) holds the
controls a report check must satisfy. Its schema is
`https://morphir.finos.org/schemas/mep-wasm-host-kit/0.1.0-draft.1/report-controls.schema.json`.
The file names the rule's orders, reasons and refusals, describes one base
report, and lists the controls. Each control says how its report differs from
the base and gives either the verdict or the refusals.

The base is a host that declares only `extism-kernel-v1`, enforces all three
bounds and cites one guest kit run of the same executable. Every case of the
corpus has the outcome that follows when its module is intact and its runs
pass: `not_applicable`, `error` for an undeclared or inconsistent bound,
`not_enforced`, or `passed`. A control's `change` then replaces members:

| Member | Effect |
| --- | --- |
| `runner`, `host` | Replace the named members. `null` removes one. |
| `bounds` | Replace the named declarations. |
| `guestKitCitations` | Replace the list. |
| `corpusSha256` | Record this digest in place of the corpus's. |
| `outcomes` | Record these outcomes for the named cases. |
| `deviations` | Record a deviation on the named cases. |
| `removeCases`, `duplicateCases`, `swapCases` | Leave out, repeat or exchange the named cases. |
| `storedTotals`, `storedVerdict` | Record these in place of the computed totals or verdict. |

Every reason, every refusal and every scenario the rule names has exactly one
control that covers it. `mise run spec:mep-wasm-report-check` checks that, and
checks each control against a reference implementation of the rule in
[`tools/check-wasm-host-report.ts`](../../../tools/check-wasm-host-report.ts).
That reference exists to check the controls. A runner's report check is
implemented and tested in the runner's repository, against the same file.

A runner adopts the controls by building, for each control, a report in its own
format from the base and the change, and requiring its report check to give the
control's result. Two of the controls are the ones the qualification spec
names: an edited verdict (`verdict-edited`) and a required bound recorded as
not enforced (`deadline-not-enforced`).
