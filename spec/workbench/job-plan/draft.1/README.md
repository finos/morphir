# Immutable Scheme job plans

Profile `morphir/workbench/job-plan`, exact version `0.1.0-draft.1`, identifies a
job's accepted runtime capability selection and public boundary. It is separate
from the frozen [`morphir/workbench/jobs` receipt profile](../../jobs/draft.1/README.md).
Job identities and receipts gain no fields. The existing `admission` member and
`morphir/workbench/admission` policy identifier keep their compatibility spelling.

This profile defines an accepted plan projection, expected claim selection and
submission response wrapper. It defines no public HTTP/native endpoint or UI
offer. Those mappings require their own exact negotiation and qualification.
The private host/worker integration can use the projection without extending a
frozen transport. The exact [draft.13 compatibility kit](../../draft.13/README.md)
checks the in-memory owner separately from actual isolated-worker qualification.

## Accepted context

The [plan schema](schemas/plan.schema.json) has exactly these members:

| Member | Meaning |
| --- | --- |
| `profile`, `contractVersion` | Exactly `morphir/workbench/job-plan` and `0.1.0-draft.1`. |
| `identity` | The accepted frozen five-field job identity, including its authenticated provider and immutable snapshot handle. |
| `planId` | A new owner-scoped plan identity, `plan-N` for the same monotonic allocation number used by its new job and snapshot. It is not a source hash or transferable authority. |
| `runtime` | Exactly `scheme`. |
| `evaluator` | Exactly `scheme-portable-v1/shared-sdk/bounded`. This selection does not introduce native binding or provider authority. |
| `admission` | The fully resolved exact policy selection, including profile, contract version and `strict` or `permissive`. |
| `boundary` | A fresh structured JSON object containing the accepted selected public entries and complete custom-type closure. It uses the existing manifest declaration shape, derived from actual retained IR rather than supplied by a renderer. |

Resolve omitted policy once, to strict, before accepting the job. Preserve an
explicit policy without fallback. Capture original source, ordered calls,
arguments, extensions, effective policy, selected boundary and provider/runtime
selection. Later caller edits, UI defaults, refreshed provider claims or transport
loss cannot mutate accepted work. Fresh projections and source/suite getters must
not expose mutable references into the owner.

The [submission projection](schemas/submission.schema.json) contains exactly
`identity`, `calls`, `receipt`, `plan`. The identity matches the nested plan and
receipt, and calls are the accepted ordered invocation IDs. The initial receipt
remains sequence zero, submitted and cancellation unacknowledged. The plan is an
additional response projection, not a member added to that frozen receipt.

## Claim and execution

An expected [claim selection](schemas/selection.schema.json) has exactly
`planId`, `runtime`, `policy`, `providerId`. The owner validates identity and job
kind, then exact selection, before changing state. Mismatch uses
`workbench.host_selection_mismatch` and leaves the job unchanged. A matching
selection does not grant a second claim: only submitted work can move to running.
A duplicate or stale claim uses `workbench.host_already_claimed`, including after
a lost worker reply. There is no lease or automatic execution retry.

The real worker receives source, suite and the effective exact selection from the
claimed retained plan. The worker must use that selection in actual planning and
evaluation. Echoing it in a descriptor or replaying a controlled receipt alone is
insufficient evidence. Completion reconstructs the source and selection from owner
state, checks that the public boundary still matches its accepted context, and
validates every returned value and terminal against that context. A worker's
edited plan, boundary or argument object cannot widen completion authority.

Typed outcomes retain the unchanged draft.5 codec, ordered call inventory, exact
extension echo and separate cleanup cause. Trusted host policy publication can
complete before a worker claim, for example cancellation or a host refusal.
Supplied completion does not prove execution or cleanup. Query and cancellation
acknowledgement do not execute, replan or rewrite the captured selection.

## Explicit replanning

A replan checks the same expected selection and creates a new job, snapshot and
plan identity on the same owner. It copies only retained source, suite and policy.
It does not accept new model text, arguments or defaults. Those changes require a
new submission. An incompatible provider/runtime/policy request rejects, with no
automatic downgrade and no partially accepted new job.

The original job remains independently valid in its existing submitted, running
or terminal state. Replanning does not reset its claim, cancel it or change its
receipt. Explicitly creating a new job does not authorize another execution of
the original. A released identity is unknown and cannot be a replan source.
Owner/session/provider replacement cannot adopt an old job by copying its plan ID.

## Bounds and evidence

Retain the existing owner capacities, source/invocation/receipt budgets, selected
boundary limits and exact scalar codecs. Plan IDs contain 1–128 UTF-16 units;
identities retain their frozen bounds. The complete plan and submission projection
must fit the mapping's encoded-byte budget. Interpreter fuel/depth/frame and
value/publication budgets do not bound all opaque SDK internal allocations or
loops. The [runtime policy qualification limits](../../draft.12/README.md) apply.

Schemas establish closed shapes and scalar bounds. They do not authenticate the
provider, establish source provenance, prove once-only worker execution, compare
an expected selection to retained state or qualify a host process. Independent
fixed job-state observations and actual worker/process evidence are both required.
