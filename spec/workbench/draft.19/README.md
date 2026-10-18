# Immutable capability selection for executions

Exact Workbench MCK `0.1.0-draft.19` defines `run-capability-executions`, JSON only,
using the existing shared Rust runner and independent report checker. Its
[fixed corpus](../mck/draft.19/README.md) exercises the real in-memory Scheme execution
owner, immutable selected planning and actual bounded evaluator. It adds a
separate [execution-plan projection](../execution-plan/0.2.0-draft.1/README.md); all earlier MCK
kits, executions receipts, terminal envelopes and HTTP/native protocols remain frozen.

The test adapter must call the production execution owner and selected evaluator. It
must not fabricate plans, infer visibility from supplied manifests, dispatch by
case ID, calculate expected results or implement a parallel execution reducer. The
runner sends no expectations or case IDs and links no implementation decoder,
planner or evaluator.

This kit establishes scoped in-memory behavior. Actual isolated worker/process
qualification must additionally show that the retained selection reaches the
worker and controls its evaluation. Neither an offline trace nor supplied terminal
publication alone establishes that. No UI, HTTP/native offer, generated target,
external binding or packaged-platform capability follows from this kit.

## Negotiation and closed inputs

Capabilities contain suite `workbench`, exact version `0.1.0-draft.19`, formats
`["json"]`, and operations exactly `["run-capability-executions"]` or `[]`. A missing
claim produces MCK `unsupported` without executing the case. Adjacent drafts,
build suffixes, different operations and Ion transport reject. JSON transport can
carry opaque JSON or Ion argument/completion source text.

An input has exactly `offer`, `submission`, `actions`. The offer uses the frozen
executions profile and binds the real owner to one host/session/provider. It is test
fixture authority, not proof of authentication. The submission has the draft.12
`model`, ordered `calls`, `runtime`, optional `admission`, and required `extensions`
shape, without draft.12's optional `completion`. Omission resolves once to strict.
There is no caller manifest or accepted boundary in a submission.

Source and argument text remain opaque to the Rust runner. The production adapter
uses existing bounded decoding, selected planning and invocation validation. All
global structure, identity, visibility, complete selected type closure, argument,
scalar and resource checks remain mandatory before execution acceptance. A startup
refusal creates no accepted execution and runs no trace actions.

All action syntax is validated before submission. Actions are closed and limited
to 32. At most three `replan` operations may occur syntactically, including failed
attempts, so at most four accepted execution histories can exist even after release.
`execution` is a zero-based accepted-execution index, 0–3. The initial submission is index zero;
each successful replan appends the next index. Selection has exactly
`planId`, `runtime`, `policy`, `providerId`, each a bounded nonempty string.

## Actions and actual effects

| Action | Additional exact members | Production operation |
| --- | --- | --- |
| `inspect` | `execution` | Describe the actual accepted plan and query its receipt. |
| `query` | `execution` | Query the actual receipt without execution. |
| `cancel` | `execution` | Request actual owner cancellation acknowledgement. |
| `release` | `execution` | Release a terminal execution; retain its last actual plan/receipt for reporting. |
| `claim` | `execution`, `selection` | Claim once, inspect the returned plan's actual policy/boundary and leave it running without evaluation. |
| `run` | `execution`, `selection` | Claim once, evaluate the real returned Scheme plan, then publish through the real owner's captured-context completion validator. |
| `replan` | `execution`, `selection` | Clone only retained source/suite/policy into a new execution/snapshot/plan identity. |
| `complete` | `execution`, `outcomes` | Decode supplied terminal evidence and pass it to the real completion validator; do not evaluate source. |
| `mutate-caller` | `policy` | Physically clear the caller's decoded IR module map and invocation arrays, and change its local policy default. Accepted state must remain unchanged. |
| `mutate-plan-view` | `execution` | Physically clear a returned boundary projection; a fresh actual description must retain the accepted context. |
| `claim-lost-reply` | `execution`, `selection` | Claim through the owner and discard the returned plan. The owner remains running and a repeated claim rejects. |
| `query-lost-reply` | `execution` | Query and discard the reply; authoritative state does not advance. |
| `transport-gap` | None | Perform no owner operation. Do not fabricate a receipt, reconnect authority, terminal or replacement claim. |

`outcomes` has exactly `format: "json" | "ion-text"` and `source`, bounded as in
draft.12. `mutate-caller.policy` is `strict` or `permissive`. The mapping's unknown
execution index and unknown runtime/policy selection refusals use
`workbench.host_unknown_execution` and `workbench.host_selection_mismatch` before the
typed owner can be called. These are adapter binding checks, not proof that the
core runtime enum has another supported value. Valid provider/plan/policy
mismatches call the real typed owner. Released known indices reach its real lookup.

Owner lookup and execution kind checks precede exact selection checks; selection checks
precede the submitted-state guard. Thus a wrong selection after a successful
claim still uses `workbench.host_selection_mismatch`; an exact duplicate claim
uses `workbench.host_already_claimed`. Replan accepts retained submitted, running
or terminal sources without changing the original. Failed operations retain the
previous state and do not allocate an accepted execution.

`run` samples the real cancellation acknowledgement through the evaluator callback.
A cancellation acknowledged before run qualifies controlled cooperative
pre-cancellation only. Synchronous trace actions cannot establish an in-flight
process cancellation race. Actual process cancellation, cleanup, lost replies and
same-session transport recovery require separate provider/worker evidence.

## Closed observations

A valid infrastructure request yields `{"status":"ok","value":...}`. The
projection has exactly `executions`, `observations`, `failure`.

Successful traces have one to four executions, one observation per action and null
failure. Each execution has exactly `plan`, `receipt`, `released`. The plan is the fresh
structured execution-plan projection and the receipt is the final actual frozen receipt.
Released executions retain their actual plan and terminal receipt captured immediately
before release; this retained view does not imply the owner still holds the execution.
Full plans and terminal values appear once per execution, not in every action view.

An action observation is exactly:

```json
{"op":"inspect","execution":0,"status":"ok","code":null,"view":{"planId":"plan-1","policy":"permissive","runtime":"scheme","sequence":0,"state":"submitted","cancelRequested":false}}
```

Status is `ok`, `invalid` or `reply-lost`. Only invalid adds a nonnull bounded
stable code; other statuses use null. View is the fresh actual plan selection and
receipt state, or null if no execution was addressed or the owner cannot look it up.
Success replan addresses the new index and view; failure addresses its original
index. Mutation and transport-gap actions have null execution/view. Release reports
its final actual pre-release view; later released-execution operations have null views.
For reply-lost actions, the operation reply is physically discarded first. A
separate trusted test observer then calls the real owner query/describe APIs to
obtain the post-action view. That view is instrumentation, not data received by
the simulated client. It establishes no reconnect authority, recovered delivery
or client knowledge of the lost reply.

Claim/run policy and boundary come from detached observations of the actual
returned plan accessors; identity/plan/runtime come from the owner descriptor. No requested
selection or predicted transition substitutes for retained actual state.

Startup refusal has empty executions/observations and failure
`{stage:"startup",code:...}`. No owner acceptance or action occurred. Per-action
refusals remain ordered invalid observations, not startup failures. A run that
claims successfully but then cannot publish leaves its actual execution running;
reporting must not roll that state back or describe it as an unaccepted startup.

If the final projection exceeds 1 MiB, the binding returns empty executions/observations
and failure `{stage:"projection",code:"workbench.projection_limit"}`. This means
the evidence view is unavailable after actual operations. It does not mean an
empty owner, a rollback, or that those operations did not execute. At most four
individually bounded plans/receipts and 32 small views limit intermediate reporting
data; this is not a hard allocator quota. A legitimate fixed case qualifies this
report-publication refusal with four individually valid large terminal receipts.

## Bounds, comparison and evidence

Compact input and retained projection are each at most 1 MiB. Model/argument/
completion string, source/typed-value and runtime limits remain those of draft.12.
The owner uses at most four live executions for this mapping and retains its existing
serialized capacity budget. Identity, plan ID and diagnostic semantic bounds use
UTF-16 units; JSON schema string lengths use Unicode code points. Existing bounded
transport, 16 MiB aggregate observations and 32 MiB report limits apply.

Literal schemas and duplicate-member checks precede typed infrastructure
conversion, including JSON-library marker objects. The runner validates accepted
plan/receipt shape, matching plan/receipt identities, unique accepted plan/execution
identities, canonical nested terminal values and bounded codes. Structured boundary
object member order is insignificant; declaration, constructor, invocation,
terminal and extension-byte order remain significant. The runner does not validate
an IR model or recreate capability selection or owner transitions.

Independent report checking reloads exact corpus bytes and recomputes SHA-256,
ordered case/operation/format inventory, capabilities, observation validity,
verdicts and qualification. Forging a runtime, policy, evaluator, boundary,
identity, plan ID, receipt, action view or qualification bit rejects. Replayed
fixed responses qualify runner/checker infrastructure only.

```sh
morphir mck workbench run --kit spec/workbench/mck/draft.19 \
  --adapter /path/to/capability-executions-adapter --report report.json
morphir mck workbench check --kit spec/workbench/mck/draft.19 --report report.json
```

The fixed source fixtures qualify Library distributions with the bounded Scheme
runtime. This does not qualify generated targets, other frontends or distribution
kinds. Opaque SDK allocations/internal loops and worker process isolation retain
the [draft.12 evidence limits](../draft.12/README.md). Live UI, desktop and connected
adoption remain subsequent work.
