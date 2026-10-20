# Build-master decision rubric

Use this rubric for material workflow, check-placement, artifact, gate, and build-optimization decisions. Score the current design and proposed alternatives against the same scope and criteria. A routine test run needs its result, not a new scorecard.

The rubric is a team decision aid. Its weights and bands are defaults, not measured probabilities, universal engineering standards, or repository policy. State any project-specific adjustments and their reason before comparing alternatives. Never change weights to make a preferred option win.

## Define scope and classify the work

Name the candidate/diff, affected component, event, environments, and decision being assessed. Distinguish a workflow design review from a particular candidate's merge or release readiness. A design can score well while a candidate still has failed required checks.

For each material check or category, record:

| Classification | Criteria to communicate |
| --- | --- |
| Failure impact | Low: localized, easily reversible defect. Moderate: meaningful feature or compatibility failure. High: broad outage, broken integration, or difficult recovery. Critical: security breach, data loss, or compromised publication. State the concrete failure, not just the label. |
| Likelihood and evidence | Known regression, plausible changed path, or exploratory coverage. Cite evidence; use unknown when likelihood is not established. Do not invent a numerical probability. |
| Detection deadline | Before merge, before promotion, or within an explicit post-merge interval. Explain the consequence of detecting it later. |
| Obligation | Merge-required, release-required, or follow-up assurance. More than one can apply. Derive this from policy and risk, not job names or runtime alone. |
| Execution and owner | PR, merge queue, dependent, nightly, other schedule, manual, or release; include category, prerequisites, responder, and failure action. |

Use impact, exposure, likelihood evidence, and detection deadline together. A critical failure does not require every broad suite on every PR when credible targeted protection and enforced release assurance cover the risk. Conversely, a slow sole detector of a merge-critical regression stays blocking until equivalent protection is established.

## Check requirements before scoring preferences

Mark each applicable requirement **pass**, **fail**, or **unknown**, with evidence and the affected merge/release/deployment boundary:

- Required regression coverage and selected aggregate gates remain enforced, including failure, cancellation, missing results, and unexpected skips.
- Required release evidence binds the candidate and delivered artifacts, or a verified equivalence/transformation contract applies. Deferred coverage has enforceable release effects when required.
- Producer trust, permissions, and artifact compatibility are preserved across workflow boundaries.
- Deferred work has a real destination, owner, trigger/deadline, visible failure response, and invocation enforcement when manual execution is required.

Mark an inapplicable requirement N/A with a reason. A known violation prevents recommending the affected action even if its weighted score is high. A consequential unknown requires investigation or an explicitly conditional proposal. A proposal awaiting validation is not approved implementation or release evidence. These labels do not add new merge gates to unrelated work; apply repository policy and the stated decision scope.

## Score the design

Use integer ratings from 0 to 4. A higher rating is better. The criterion-specific anchors below define 0, 2, and 4; use 1 or 3 only when evidence supports an intermediate state and explain why. Use U for unknown, and N/A only when the criterion does not apply to the stated scope. Missing evidence is U, not 0 or N/A.

| Criterion | Weight | 0: deficient | 2: partial | 4: strong |
| --- | ---: | --- | --- | --- |
| Risk and coverage fit | 25 | Needed failure detection is missing or selection is unsound. | Main risks covered; a relevant boundary or selection case remains weak. | Distinct risks and detection deadlines mapped to appropriate checks; relevant boundaries and selection behavior validated. |
| Feedback and placement | 20 | Broad work burdens PR feedback without justification, or necessary feedback arrives too late. | Useful early signal exists but avoidable critical-path work or cadence mismatch remains. | Fast credible PR feedback meets the stated target; deeper work has justified placement and detection latency. |
| Release evidence and trust | 20 | Required candidate/artifact identity or trust is unenforced. | Intended contract exists but producer, transformation, retention, or refusal behavior has a gap. | Candidate-bound evidence, compatible consumption, trust, and refusal of unavailable/invalid evidence are verified for the scope. |
| Execution efficiency | 15 | Demonstrated redundant work or needless serialization dominates the path. | Some setup/artifacts reused, with known avoidable repetition or a partially measured path. | Compatible builds reused; independent verification preserved; parallelism, cache misses, and downstream compute accounted for with measurements. |
| Ownership and structure | 10 | Checks accumulate without coherent categories, dependencies, or responders. | Categories and owners exist but overlap or handoffs remain ambiguous. | Clear category ownership, justified job boundaries, explicit dependencies, and stable gates. |
| Operability and recovery | 10 | Failures disappear or recovery depends on an undefined manual action. | Alerts and recovery exist but a relevant cancellation, retry, missing-run, or stale-evidence case is untested. | Failure routing, diagnosis, retry/cancellation, missed schedules, and recovery paths are defined and validated where applicable. |

For fully assessed applicable criteria, calculate `100 × Σ(weight × rating / 4) / Σ(applicable weights)`. Round only the displayed total to a whole number. Show every rating and weight so another team member can reproduce it. Do not average hard requirements into this score.

If a criterion is genuinely N/A, state why and show the reduced denominator for all compared options. Keep applicability consistent across alternatives with the same scope. If a criterion is U, withhold a final total. Show the unknown weight and, if useful, the possible score range by letting unknown ratings vary from 0 to 4. Do not silently drop unknowns or normalize a tiny assessed subset into a high score.

State confidence separately for each material judgment: high for relevant repeatable measurements or verified behavior, medium for partial observations and inspected contracts, low for estimates or indirect evidence. A proposal's estimate is not a measured improvement. Report candidate, run IDs, sample size, platforms, warm/cold state, queue delay, and elapsed versus runner time as relevant. Do not infer confidence from the numeric score.

## Turn the assessment into a decision

Apply requirement results first. For a fully assessed design, apply these default bands to the unrounded score:

| Result | Recommendation |
| --- | --- |
| At least 80 with every applicable rating at least 2 | Sound within scope. Recommend adoption or retention, subject to stated validation and authorization. |
| At least 60 but below 80; also 80 or more if any applicable rating is below 2 | Revise the weak criteria before recommending the design as sound. Identify the exact change needed. |
| Below 60 | Rework the execution design and compare alternatives. |
| Consequential unknowns | Provisional decision. Name the evidence needed, responsible person/role, and the affected decision that must wait. |

The weakest-dimension rule prevents a good average from concealing a major deficiency. These bands prioritize design work, not people or teams. They are not automatic merge, release, or deployment approvals. Repository requirements and maintainer authority still apply.

When options are close relative to uncertain measurements, explain the tradeoff rather than claiming a one-point winner. Prefer the simplest option that meets the actual requirements. If a different recommendation is justified, state the reason and any authorized exception; keep the original score and failed requirements visible.

## Communicate a reproducible decision

Lead with the recommendation and its decisive reason. Include a compact scorecard in the coordinator/team handoff:

```text
Decision scope: <candidate/diff, event, environments, design vs readiness>
Classification: <risk, detection deadline, obligation, execution path, owner>
Requirements: <pass/fail/unknown/N/A, evidence, affected boundary>
Scorecard: <criterion | weight | current | proposed | evidence | confidence>
Total: <current/proposed and denominator, or withheld for U>
Decision: <retain/adopt/revise/rework/provisional, reason, relevant band>
Tradeoff: <why this option; coverage, latency, runner use, complexity>
Next actions: <validation or changes, owner, completion evidence>
```

Use file/line references, run links, or artifact receipts for evidence. State which criteria drove the outcome, what would change the recommendation, and any disagreement or accepted tradeoff. Reassess after implementation with measured results; do not present an expected score as an achieved score. For a small decision, a short table and a few sentences can carry the same information.

## Calibration examples

These are hypothetical ratings to illustrate the rubric, not findings about this repository.

An all-PR 40-minute fuzz matrix already has credible focused regressions and candidate-bound release protection. Ratings in table order of `4, 1, 4, 1, 3, 3` yield 69/100 and a revise recommendation. An alternative with focused PR checks and owned nightly/on-demand qualification has expected ratings `4, 4, 4, 3, 4, 3`, yielding an estimated 94/100. The recommendation depends on verifying placement, enforcement, and expected runtime; it is not a claim of measured savings. If those runtime facts are unavailable, mark the relevant criteria U and withhold the final total.

A nightly receipt for candidate X cannot satisfy a release requirement for different candidate Y without a verified equivalence contract. Mark that release requirement fail and do not recommend promoting Y, regardless of the other ratings. Keep the design assessment separate from this candidate-readiness result.
