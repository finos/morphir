# Offline execution transition qualification

Workbench MCK `0.1.0-draft.14` qualifies the single offline operation
`reduce-execution` with JSON inputs. It adds parent-owned traces for the existing
[`morphir/workbench/executions` `0.2.0-draft.1`](../executions/0.2.0-draft.1/README.md)
receipt profile. Neither that execution profile nor its nested
[draft.5 terminal outcomes](../draft.5/README.md) changes.

This kit is separate from the historical value/validation kits. Drafts.1–.5
remain byte-identical and must be qualified separately. An adapter advertises
exactly `operations: ["reduce-execution"]`, `formats: ["json"]` for draft.14. The
capability message describes an offline reducer; it does not advertise a live
host, submission, query or cancellation endpoint. No Ion execution mapping is defined.

## Trace input

A request uses the existing correlated JSON-lines adapter transport:

```json
{"id":1,"op":"reduce-execution","suite":"workbench","contractVersion":"0.1.0-draft.14","format":"json","input":{"offer":{"profile":"morphir/workbench/executions","contractVersion":"0.2.0-draft.1","hostId":"host","sessionId":"session","providerId":"provider","operations":["query","cancel"]},"identity":{"hostId":"host","sessionId":"session","providerId":"provider","executionId":"execution","snapshotId":"snapshot"},"calls":["call"],"initial":{"contractVersion":"0.2.0-draft.1","identity":{"hostId":"host","sessionId":"session","providerId":"provider","executionId":"execution","snapshotId":"snapshot"},"sequence":0,"state":"submitted","cancelRequested":false,"outcomes":null},"actions":[{"op":"cancel-action"}]}}
```

The input has exactly `offer`, `identity`, `calls`, `initial`, `actions`.
`identity` and the ordered `calls` inventory are caller-owned expectations;
they must never be inferred from a received terminal. The initial receipt must
be sequence 0, submitted, cancellation unacknowledged. Construction checks the
offer, identity, call array and initial receipt before starting the cursor.
The offer and identity use the frozen execution profile, including exact prerelease
versions and host/session/provider scope. A reordered operation set is the same
set; a changed operation set is not the same offer.

Actions are closed shapes:

| Action | Exact members | Meaning |
| --- | --- | --- |
| Observe | `op: "observe"`, `receipt` | Validate one host receipt. |
| Disconnect | `op: "disconnect"` | Retain receipt; mark local transport offline. |
| Reconnect | `op: "reconnect"`, `offer` | Validate a fresh offer for the same authority and operation set. |
| Cancel action | `op: "cancel-action"` | Read the permissible client action; do not acknowledge or terminate anything. |

The adapter validates **all action syntax before executing any action**. Missing,
extra or unknown action members, unknown operation tags, a non-object trace,
non-array `calls` or `actions`, and missing/extra root fields reject the whole
trace as `workbench.invalid_execution_trace`. Receipt and offer payloads remain
unconstrained at this syntax stage so malformed evidence can be tested. Their
ordinary profile rejection is recorded as a per-action invalid observation;
the cursor and retained receipt stay unchanged. A malformed observe payload is
decoded before the cursor's connectivity check; a well-formed receipt supplied
offline rejects as `workbench.execution_disconnected`.

The frozen reducer validates complete receipts before stale/replay handling.
Wrongly bound or malformed stale evidence cannot become an accepted stale
observation. Equal sequence plus equal validated payload is replay; equal sequence
plus different payload is `workbench.execution_conflict`. Greater sequences require
an actual state or acknowledgement change. Running cannot regress, cancellation
acknowledgement cannot reverse, and terminal evidence is immutable. A valid
older receipt remains stale after terminal completion. Polling can skip revisions.

## Projection and rejection

A successful response is exactly `id`, `status: "ok"`, and `value`.
`value` has exactly:

- `identity`: the original expected five-field identity;
- `receipt`: the final validated full execution receipt, including exact draft.5 outcomes;
- `connected`: final local transport availability;
- `cancelAction`: `send`, `pending`, `already-terminal`, `unavailable` or `disconnected`;
- `observations`: one ordered bounded view per action.

Each observation is exactly `{op,status,view}`, with `code` added only for
`status: "invalid"`. An observe status is `advanced`, `replay`, `stale` or
`invalid`; reconnect is `local` or `invalid`; disconnect and cancel-action are
`local`. Each view has exactly `sequence`, `state`, `cancelRequested`,
`connected`, `cancelAction`. No intermediate view repeats terminal values,
cleanup, identities or complete receipts. The final full receipt appears once.

Cancellation action priority is terminal (`already-terminal`), offline
(`disconnected`), missing cancellation capability (`unavailable`), host
acknowledgement (`pending`), then `send`. The `cancel-action` action has no side
effect on receipts. Acknowledgement can race with a returned value, model error,
primary failure or cancellation. Cleanup failure remains separate in every case.
Disconnect preserves the last receipt; same-session reconnect restores access
without inventing a new execution or accepting a different snapshot.

A whole-trace rejection is `{id,status:"invalid",code}`. Startup retains the
portable profile's error codes: `workbench.execution_negotiation` for unsupported
profile/version/operations; `workbench.execution_authority` for offer binding mismatch;
`workbench.execution_identity` for invalid identities, receipt binding or malformed
call IDs; `execution.call_identity` for duplicate invocation IDs;
`workbench.execution_transition` for a non-initial startup receipt. Nested terminal
rejections retain draft.5 codes. Per-action invalid observations use these same
codes, plus conflict, transition and disconnection codes, without a partial
state update. Nested decoder errors outside the portable error union normalize to
`workbench.codec_failure` at the action boundary. They also retain the cursor
and allow later actions to run. Error messages are not qualification data.

## Bounds and schema scope

The shared runner retains literal JSON object kinds and exact decimal tokens
before schema checks or typed decoding. Negative trace inputs remain opaque and
are sent without numeric normalization or reinterpretation of JSON library private
marker maps. Those maps cannot impersonate scalar fields or successful projections
in corpus expectations, live observations or saved reports.


| Item | Bound |
| --- | --- |
| Compact UTF-8 input before decoding or trace execution | 1 MiB; `workbench.input_limit` |
| Actions | 0–64; excess is `workbench.execution_limit` |
| Ordered invocation inventory | 1–1,000; empty/excess is `workbench.execution_limit` |
| Identity and invocation ID | 1–128 UTF-16 code units |
| Receipt revision | Integer 0–2,147,483,647 |
| Compact UTF-8 success projection | 1 MiB; excess is whole-trace `workbench.execution_limit` |
| Observation views | Exactly one per action, at most 64 |

Outer framing must reject duplicate JSON members and over-budget requests.
The fixed corpus itself only contains inputs within the 1 MiB runner budget;
oversized framing belongs to adapter/runner boundary tests. The corpus includes
a valid in-budget input whose retained value plus bounded views exceeds the
output limit, requiring rejection without returning a partial projection.

Schemas are closed and operation-specific. They reference the frozen execution
identity/receipt resources, which in turn reference draft.5 terminal outcomes
and the original value schema. Schema string length counts code points;
portable semantic validation checks UTF-16 units. Schemas also cannot prove
receipt/identity equality, transition order, current-view equality, authority
provenance or nested output type validation. The shared runner binds projections
to operation context, validates canonical nested outcome shape, and recomputes
qualification against the exact corpus hash. A report's own `qualified` flag is
not evidence by itself.

## Independent evidence and remaining work

The [fixed corpus](../mck/draft.14/cases.json) contains 170 parent-owned cases,
with explicit expected projections and rejection codes. Expectations were
authored from the published profile, never captured from MoonBit execution.
The 46 structural schema fixtures test transport, capabilities, corpus,
projection, observation and report closure. Neither a schema pass nor offline
qualification establishes an authenticated or executing host.

Live integration follows separately: bind qualified daemon submission, query and
cancel operations; capture immutable snapshots; reconcile the same session;
show connection state and cancellation acknowledgement without manufacturing
terminal status. Host restart recovery, durable retention, transferable sessions
and exactly-once submission remain outside this profile.
