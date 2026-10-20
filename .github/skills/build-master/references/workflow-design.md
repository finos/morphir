# Workflow placement and assurance contracts

Read this when deciding whether work belongs in CI, a scheduled/manual path, a dependent workflow, or a release gate. Apply the host's current documented semantics; the GitHub notes below are examples, not a requirement to use GitHub.

## Record a coverage decision

For each moved or added check, capture enough information to assess the tradeoff:

| Field | Decision to record |
| --- | --- |
| Risk and coverage | What failure it detects, and what relevant coverage already exists. |
| Owner/category | The maintained category and responder responsible for its result. |
| Execution | Trigger, selected paths/dependencies, platform/toolchain/mode, and prerequisites. |
| Feedback | Expected runtime and maximum acceptable detection delay; identify measurements versus estimates. |
| Gate | Whether it blocks merge, release, deployment, or requires follow-up. |
| Deferred result | Destination, alert/notification, response policy, and how absent or stale results are handled. |
| Evidence | Candidate/source, artifact digests, dependency/toolchain/configuration/check identity, and retention. |

For example, a quick parser regression can protect a PR while a larger fuzz campaign runs nightly. If the fuzz campaign is release-required, candidate qualification or a verified equivalence contract must connect its result to the release candidate. A manual button alone does not enforce that requirement.

Risk can justify a longer merge-blocking check: changes to transactions, migrations, authentication, build provenance, or pipeline policy may need focused integration before merge. Optimize the producer/consumer path and select the relevant coverage rather than moving the only regression detector to a later workflow.

## Dependency and artifact design

Draw the graph across all entry workflows and scripts. A reusable workflow groups jobs but does not automatically share a filesystem or build output. Composite setup actions reduce configuration duplication; they do not make repeated compilation disappear. Account for actual selected branches and mode flags before counting duplicate work.

Prefer explicit production of a named, verifiable artifact followed by compatible consumers. Share one artifact when identities match; keep separate builds for genuinely distinct environments or independent compiler verification. Include package creation and any signing/transformation in the assurance contract. Retention must support the consumers and release window.

Promoting an artifact is different from rebuilding its source. Rebuilding after tests can change the delivered bytes. Verify the exact published output, or explicitly validate the transformation from tested input to published output. Avoid using "latest successful" without verifying the required candidate and producer identity.

## GitHub event behavior

- `needs` expresses dependencies inside a workflow; reusable workflows can contain category-level job graphs. Use these for a coherent execution plan and stable aggregates. See [reusable workflows](https://docs.github.com/en/actions/concepts/workflows-and-actions/reusing-workflow-configurations).
- `workflow_run` completion is not proof of predecessor success. Check the upstream conclusion and bind the upstream repository, source SHA, run/attempt, and artifact identity. Do not accidentally use the downstream workflow's default-branch checkout as if it were the tested candidate. Treat outputs from untrusted runs as untrusted input, particularly across privilege boundaries. See [trigger events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run) and [secure use](https://docs.github.com/en/actions/reference/security/secure-use).
- Scheduled runs use default-branch context and can be delayed or dropped. Observe actual completion, retain candidate-bound evidence, and provide an on-demand qualification path when release assurance cannot wait. Schedule explicit work at the useful cadence rather than assuming every expensive test belongs on every push. See [scheduled events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).
- Artifacts carry job outputs; caches accelerate reusable dependencies or intermediates. Verify artifacts before downstream consumption, and design for cache misses. See [workflow artifacts](https://docs.github.com/en/actions/concepts/workflows-and-actions/workflow-artifacts).

Dependent workflows need explicit handling of predecessor failure, cancellation, missing artifacts, stale candidate evidence, permissions, and reruns. Preserve failure visibility across workflows; a fast aggregate must describe its own coverage rather than implying that deferred suites passed.

## Review the tradeoff

Compare representative before/after runs for feedback time and runner execution by platform, with queue time and retries separate. Include the cost of downstream work when moving it off the PR path. Moving work changes latency and scheduling; it does not necessarily reduce total compute.

When changing gate placement, verify expected selected work, required skip/failure behavior, changed-path rules, candidate equivalence, and release refusal when required evidence is missing. A lower PR duration with an unenforced release check is not a completed optimization.
