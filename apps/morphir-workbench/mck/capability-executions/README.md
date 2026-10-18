# Immutable Scheme execution trace adapter

This explicit offline witness implements JSON `run-capability-executions` at exact
Workbench `0.1.0-draft.19`. The parent Morphir specification owns the schemas,
independent fixed corpus and sole Rust compatibility runner/checker. This adapter
receives only trace inputs. It contains no fixture expectations or verdict logic.
Historical adapters and their exact contracts are separate.

Each trace creates the production engine executions `Session` from the offered frozen
executions authority, decodes the actual Library IR and invocation suite, and calls
`submit_scheme`. Omitted policy resolves to strict once. Plan projections observe
`describe_scheme`; receipt projections observe the unchanged production receipt.
The structured selected boundary comes from the immutable accepted plan. After
successful `claim` or `run`, the full plan's policy and boundary are detached
observations from the actual returned `SchemePlan.policy()` and `boundary_json()`;
identity, plan ID and runtime still come from the actual owner description. The
binding does not compare or repair that claimed context. `claim-lost-reply`
discards its plan, so its final context remains an owner description rather than
claimed-plan execution evidence.

- `claim` calls the actual once-only `claim_scheme` and observes its returned
  plan's policy. It does not execute. `run` claims once, calls that real plan's
  `evaluate_outcomes`, then publishes through `Session.complete`.
- `complete` only decodes and validates supplied JSON/Ion terminal evidence. It
  never executes the model and proves neither provider execution nor cancellation.
- `mutate-caller` physically clears the caller's decoded Library module map and
  suite arguments/calls, and changes its local default policy. `mutate-plan-view`
  clears a fresh `describe_scheme` boundary object. Accepted state is observed
  afresh afterwards; neither action edits retained Session state.
- `replan` reconstructs from the accepted source, suite and policy into a new
  independent execution, snapshot and plan. Its successful observation names the newly
  appended execution index. The original execution remains independent.
- Query, cancel, release and repeated claims call the production Session methods.
  A released execution retains the last real plan and terminal receipt captured before
  release; later operations still call the owner and receive its unknown-execution
  refusal. Failed actions observe the remaining actual state without rollback.
- Lost-reply actions perform the real query/claim and discard the response. The
  action view then comes from separate trusted owner query/describe instrumentation.
  It is not the lost client reply, client knowledge, successful delivery or
  reconnect authority. A transport gap performs no owner operation. These controls
  do not establish real process loss, reconnection, authentication, worker exit or
  cleanup.

Unknown runtime or policy strings are binding refusals with
`workbench.host_selection_mismatch` before an owner call: the production enums
cannot represent those strings. An index with no accepted execution is likewise a
binding `workbench.host_unknown_execution`; an existing released identity reaches the
actual owner. Valid selections, including wrong plan/provider/policy combinations,
are checked by the real Session. No selection is silently coerced or downgraded.

The trace is synchronous. `run` samples the actual accepted execution's cancel request
and passes it to the production evaluator's cooperative cancellation callback.
This covers controlled cancellation before execution, not cancellation of an
independent running process. Primary/cleanup distinctions and actual output
validation remain production behavior.

Input and retained projection are each at most 1 MiB, with at most 32 actions.
The infrastructure permits at most three syntactic replan actions, so accepted
history contains at most four executions even after release. Session capacity is four
live executions. Source, selected-type, value and interpreter budgets remain production
limits; fuel is not a hard CPU or allocation quota over opaque SDK internals.

If the full final projection exceeds its byte budget, the explicit
`projection/workbench.projection_limit` refusal means the bounded view is
unavailable **after** the operations. Empty execution/observation arrays in that refusal
are not an assertion that the owner was empty, that execution did not occur or
that effects were rolled back. Unexpected failure to re-observe a retained live
execution fails the adapter instead of fabricating an owner observation.

The portable handler has Node, native and Chromium entry points. Chromium uses
`globalThis.morphirCapabilityMck` as the private carrier alias from the same
compiled MoonBit component. Each kit loads an independent page/artifact; the
carrier forwards NDJSON only and makes no operation or compatibility decision.
NDJSON transport rejects oversized/incomplete lines and invalid UTF-8. This
witness does not advertise UI, native/HTTP provider or packaged-platform support.
Real worker/process propagation requires separate composing-host acceptance.
