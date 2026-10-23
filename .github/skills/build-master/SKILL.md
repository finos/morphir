---
name: build-master
description: Plan and review CI/CD and build execution for fast correctness feedback and reliable releases. Use when adding or changing workflows, checks, matrices, build scripts, caching, artifacts, scheduling, or deployment dependencies, or when asked for a build-master review.
---

# Build master

Own the execution plan across development, integration, delivery, and release assurance. CI should provide a quick, credible signal of correctness. A new test does not automatically belong on every PR's critical path. Use nightly, other schedules, manual runs, and dependent workflows deliberately while preserving the evidence needed to release reliable code.

For this checkout, read [references/repository.md](references/repository.md) before reviewing or changing the execution plan. The companion [build-master agent](../../agents/build-master.agent.md) defines the specialist role and delegation contract.

## Inspect the whole execution path

Read repository instructions, required checks, release policy, workflow callers, selectors, task runners, and test harnesses before changing the pipeline. Trace the dependency graph across workflows, including nested matrices, hidden compilation, package installation, and downstream triggers. Inspect actual event selection and run records: similar labels or repeated YAML references alone do not prove duplicate execution.

Identify each check's correctness risk, coverage, owner, triggering events, expected detection delay, merge/release gating, runtime, and artifact inputs/outputs. Find the existing category responsible for that coverage before adding a job. Distinguish missing coverage from duplicate orchestration and from intentionally independent toolchain/platform verification.

## Place assurance deliberately

| Execution path | Purpose and placement |
| --- | --- |
| PR CI | Fast deterministic checks, relevant builds, focused regressions, and integration checks justified by the change's risk. |
| Merge queue | Validate the integrated candidate with the required fast checks and any additional integration risks introduced by combining changes. |
| Dependent/post-merge workflows | Run consumers after their actual prerequisites succeed; perform deeper integration or packaging against the identified outputs without holding unrelated fast checks open. |
| Nightly | Broad platform/compiler/mode matrices, long semantic suites, fuzzing, soak tests, and expensive compatibility coverage at an explicit cadence. |
| Other schedules | Periodic performance, dependency, environment-drift, or maintenance checks whose useful cadence differs from every commit or every night. |
| Manual/on-demand | Targeted diagnosis, exceptional environments, expensive investigations, and pinned-candidate qualification when needed. Define who requests it and what requires it before merge or release. |
| Release/promotion | Enforce the assurance contract for the exact candidate and artifacts being published; consume or obtain the required trustworthy evidence. |

Choose placement from risk, feedback speed, and required detection latency. Do not automatically attach every check to PR CI, and do not move a correctness-critical check out merely because it is slow. For a long test of a merge-blocking invariant, retain an appropriate targeted PR check or the necessary blocking integration gate, then use deeper workflows for additional breadth.

When deferring coverage, specify its destination, owner, cadence/trigger, failure notification, response, and effect on release eligibility. A nightly failure must reach an owner and change the relevant release decision. Manual-only coverage needs a concrete invocation condition and a gate that requires its result when applicable. Neither a green PR nor a workflow's existence proves deferred assurance happened.

Required release evidence must match the candidate's source/artifact, dependencies, toolchain, configuration, and check definition. Last night's green result for another candidate is not enough. Reuse equivalent evidence only under an explicit, verified compatibility contract. Missing, failed, skipped, stale, or pending required evidence blocks promotion until satisfied or an explicit exception is authorized. Scheduled jobs can be delayed or missed; do not rely on the clock as a release gate.

For workflow dependencies, event semantics, and candidate-bound evidence, read [references/workflow-design.md](references/workflow-design.md).

## Build once for compatible consumers

Make artifact producers and consumers explicit. Reuse outputs for the same compatible source, target OS/architecture, compiler/SDK, build mode, and configuration instead of rebuilding in each test harness. Preserve independent compiler/platform checks when they prove different contracts. Record provenance separately from compatibility requirements; do not reject compatible artifacts solely for an incidental runner-image difference.

Promote the verified candidate artifact through testing and deployment where its contract permits. A changed build, toolchain, or packaging transformation needs the appropriate new evidence. A cache accelerates production of evidence; it is not itself proof of correctness, source identity, or permission to deploy. Verify cache keys, trust boundaries, and cold-cache behavior.

Test commands should expose their actual work. Separate compilation, quick smoke checks, broad acceptance, installed-package checks, and live-host scenarios where doing so permits ownership and reuse. A step named "smoke" should not silently rebuild the world and execute a full qualification matrix.

## Organize categories and dependencies

Use reusable category workflows with coherent inputs, internal parallel jobs where useful, and stable aggregate gates. Put a new check into its existing category when possible. A separate job needs a reason such as a different environment, isolation or privilege boundary, resource requirement, concurrency policy, or a measured critical-path improvement. Group compatible short checks when shared setup is cheaper; preserve useful parallelism.

Plan the required work once for each event and change set. Keep independently triggered workflows consistent with that plan. Define which failures block merge, which block release, and which trigger follow-up. Required aggregate checks must fail for missing, failed, cancelled, or unexpectedly skipped selected work; intentionally deferred checks must not masquerade as completed merge coverage.

Order dependent work after the producer it actually needs. Avoid both unnecessary serialization and concurrent duplicate builds. Use cancellation for superseded PR work where safe; do not apply it blindly to releases or deployments. Distinguish artifact transfer from dependency caching, and verify producer result, source identity, and trust before a downstream workflow consumes anything privileged.

## Measure before adding or optimizing

Use representative run records and existing measurement tools. Separate queue delay, execution time, end-to-end feedback time, critical path, cache warm/cold behavior, retries, and runner usage by platform. Summed runner execution is neither elapsed time nor billed cost. Do not infer waste from job count or promise that all overlapping runtime can be removed. Measure first actionable feedback, merge readiness, and release eligibility separately; an early green subset does not mean pending gates passed.

Agree or infer a feedback target from the project's needs and measured baseline; label an inferred target as a proposal. Avoid inventing a universal minute limit. Prefer fast useful failures early, appropriate change selection, reusable artifacts, and moving broad assurance to its appropriate execution path before adding runners or a larger matrix.

Before adding a job, matrix axis, or trigger, explain what distinct risk it covers, why existing work cannot own it, which event should run it, its estimated time/cost, and how its result affects merge or release. Review the whole graph rather than treating one more green check as an improvement.

Validate selector and aggregate semantics as well as happy-path YAML. Test required failure/cancellation, intentional skip, relevant and irrelevant changes, dependent failures, unavailable evidence, and candidate mismatch when those behaviors change. Run the repository's required checks and measure the resulting path. Separate measured savings from estimates and confirm coverage was preserved.

## Plan scarce runners as limited capacity

A matrix of operating systems and architectures exists to find platform-specific defects before a release: path and line-ending handling, process and signal behavior, file locking, toolchain and linker differences, and packaging. It does not prove general logic again. Platform-neutral tests on one runner prove that logic. Early platform feedback is useful, but it does not have to come on every push or in the merge queue. It must come before the release of the affected artifacts. Keep a platform job on the pull-request path only when the change has a known platform-specific risk that must block merging.

Treat macOS runners and scarce Windows runners as limited, shared capacity, not as one more matrix entry. Their concurrency limit is low and their queue time adds to every workflow that waits for them. A job that waits for such a runner can make a merge-queue entry time out and force the queue to rebuild the entries behind it.

Before a job uses one of these runners, state the platform-specific risk it proves, why a Linux job or an existing scheduled job cannot prove it, and the event that must run it. Prefer nightly, manual, or release execution with candidate-bound evidence. Skip a run when trustworthy evidence already covers the same inputs. Keep a scarce-runner job on pull requests or in the merge queue only when the repository reference allows it or the maintainer approves it explicitly. When you measure, report queue delay for these runners separately from execution time.

### Platform attestations are hints, not evidence

A committer can state the platforms on which they built and tested a change, for example a developer who works on macOS or on Windows ARM64. Accept this attestation as useful information. Use it to judge risk, to choose which platform lane to run first, and to find where a later platform failure came from. It is not evidence. It has no candidate binding, no recorded commands or results, and no trusted runner. It never satisfies a release requirement, a required check, or an evidence lookup, and it never stops a scheduled or release platform run. Follow the repository reference for its format.

## Classify and explain decisions

For material build and workflow decisions, use [references/decision-rubric.md](references/decision-rubric.md). Classify risk, detection deadline, obligation, execution path, and owner. Assess non-negotiable requirements separately, then score the design against the shared weighted criteria. Show evidence and confidence, compare alternatives consistently, and identify the criteria that drive the recommendation. Unknown evidence stays visible; scores do not grant merge or release approval.

## Work with the maintainer

The build-master role owns workflow architecture, check placement, artifact reuse, and feedback efficiency. PR maintenance owns carrying the implementation through its declared required gates and any authorized merge. Use an installed `repo-maintainer` skill for that work when available; this skill remains usable without it.

Respect repository-specific tools, scripts, gates, and authorization. Do not silently remove coverage, weaken a release contract, create live schedules, publish artifacts, or deploy beyond the user's scope. A request to design this role is not permission to rewrite a repository's pipeline or run an expensive qualification fleet.

Deliver a concise, evidence-backed review or change: current bottlenecks, ownership and trigger choices, producer/consumer dependencies, preserved and moved coverage, failure/release policies, and measured or estimated feedback/runner impact. State what still needs validation. Keep the PR description aligned with the final behavior.
