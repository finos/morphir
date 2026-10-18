# Snapshot-bound Workbench execution receipts

This transport-neutral profile is exactly `0.2.0-draft.1`, named
`morphir/workbench/executions`. It is a new contract namespace, separate from value and
terminal validation drafts. Its terminal payload references the frozen
`0.1.0-draft.5` outcome envelope without changing it.

This contribution defines receipt validation and client reduction. It does not
add JSON-RPC methods, authenticate hosts, perform evaluations or advertise support in
the existing connected host. Connected `protocolVersion: 1`, generated-driver
v1 and the five offline Workbench MCK drafts remain unchanged. A host adapter
must implement and qualify the profile before a client enables live controls.

This pre-1.0 contract replaces the published job terminology through a breaking
change. Old job-based identities, operation names and routes are not aliases.
The previous published schemas and qualification records are historical evidence.

## Authority and negotiation

An authenticated host offers exactly:

```json
{"profile":"morphir/workbench/executions","contractVersion":"0.2.0-draft.1","hostId":"host","sessionId":"session","providerId":"provider","operations":["query","cancel"]}
```

`query` is required; `cancel` is optional. Operations are a unique set. Unknown
operations, members, profile names, versions and version build suffixes reject.
Only this exact prerelease is supported. No generic SemVer comparison is needed
for this fixed draft; a reader with version ranges must use a SemVer library.
An offline schema fixture is not a live capability advertisement.

The caller obtains the expected binding from authenticated submission, never
from the receipt it is about to validate. The identity contains exactly
`hostId`, `sessionId`, `providerId`, `executionId` and `snapshotId`. Each contains
1 to 128 UTF-16 code units. The offer's first three fields must match. Provider
and snapshot are immutable for the execution, including while reconnecting. A new
session or provider cannot borrow the old execution's authority. A snapshot handle
denotes immutable execution input; it is not a local path or a content hash
unless a separately qualified host contract says so.

Host authentication, provider trust, public-entry validation and snapshot
creation remain host responsibilities. The reducer checks binding and receipt
consistency, not cryptographic provenance. New project-scoped metadata bindings
must remain scoped when a host translates a planned engine execution into this identity.

## Receipts

A receipt has exactly these six fields:

```json
{"contractVersion":"0.2.0-draft.1","identity":{"hostId":"host","sessionId":"session","providerId":"provider","executionId":"execution","snapshotId":"snapshot"},"sequence":0,"state":"submitted","cancelRequested":false,"outcomes":null}
```

| State | Outcomes | Meaning |
| --- | --- | --- |
| `submitted` | `null` | Host accepted this exact execution and snapshot. |
| `running` | `null` | Host reports execution in progress. |
| `terminal` | Exact draft.5 envelope | Primary outcomes and separate cleanup are final. |

Sequence numbers range from 0 through 2147483647 on every target. The initial
submission receipt is sequence 0, submitted, with `cancelRequested: false`.
Running and terminal receipts have positive sequences. Host revisions advance
for a state change or cancellation acknowledgement, not merely because a query
was issued. Polling may skip revisions; it does not require a complete event log.

The client captures a nonempty ordered inventory of at most 1,000 invocation
call IDs at submission. IDs contain 1 to 128 UTF-16 units and are unique. A
terminal must have exactly that inventory, in order. Typed values retain the
draft.5 bounds and shape; the host must also validate every output against the
submitted manifest. This receipt reducer alone cannot establish output types.
`Result.Err` remains returned data. SDK errors, primary failures, cancellation
and cleanup keep their distinct variants. Cleanup never changes primary status.

## Reduction and cancellation races

Validate the entire supplied receipt and its identity before sequence handling.
Malformed or wrongly bound stale evidence rejects. With the exact binding:

- A lower sequence is stale and leaves the cursor unchanged.
- An equal sequence and identical validated payload is an idempotent replay.
- An equal sequence with conflicting payload rejects.
- A higher sequence can move submitted to running or directly to terminal.
  Running cannot move back to submitted. Terminal is immutable.
- Cancellation acknowledgement can change false to true while submitted or
  running. Once acknowledged it cannot return to false. It requires a negotiated
  cancellation operation. The same state and acknowledgement cannot acquire a
  new revision without a change.

`cancelRequested` means the host acknowledged a request. It does not mean any
call terminated. Sending a client cancellation request changes no authoritative
receipt. A host may finish with returned values or failures after acknowledgement.
The host may also cancel by its own policy without a client request. The primary
terminal payload decides each call's outcome.

If cancellation is unavailable, the client must not send it. If the execution is
terminal, use the retained terminal rather than sending another request. If
disconnected, the client retains the last receipt and reports unavailable
transport. Disconnect and timeout are never synthesized as failed or cancelled
execution receipts. A timeout can leave the host running.

## Disconnect and reconnect

Connection availability is client state, separate from submitted/running/terminal.
An offline cursor cannot adopt incoming receipts. Reconnect requires a newly
authenticated offer with the exact previous host, session, provider, draft and
operation set. It restores transport availability and permits a fresh query of
the existing identity. The ordinary stale/replay/advance rules validate that reply.

This qualifies in-memory same-session reconciliation only. It does not promise
durable execution retention, recovery after host restart, transferable sessions,
exactly-once submission or an authenticated transport implementation. A changed
session requires explicit host recovery support, not a fresh label on old evidence.

## Bounds and qualification

Raw receipt framing must be capped at 1 MiB before JSON parsing. JSON parsers at
the host boundary must reject duplicate members. Closed parsed shapes then feed
the portable reducer. No Ion receipt mapping is defined in this first execution draft;
existing JSON and Ion evaluation inputs and outcome codecs remain supported.

The schemas check shape, discriminants, closed members, versions and numeric
bounds. Schema string lengths count code points; the reducer enforces UTF-16
identity limits. Sequence transitions, authority equality, call inventory,
acknowledgement monotonicity and authentication are semantic requirements, not
established by schema validation.

Structural fixtures run through the existing `workbench:schema-check` task.
The MoonBit implementation has portable semantic tests on JS, native, Wasm and
Wasm GC. These are implementation tests, not a shared MCK adapter qualification
or evidence that the Rust connected host implements execution execution. A future
shared MCK slice must add parent-owned transition goldens to the existing runner,
then qualify host adapters and bind query/cancel transport methods.

## Independent offline transition kit

[Workbench MCK draft.14](../../draft.14/README.md) now specifies the independent
`reduce-execution` JSON trace mapping and its [parent-owned fixed cases](../../mck/draft.14/README.md).
It selects this exact execution profile and the frozen draft.5 terminal envelope.
Its offline capability claim does not enable live query or cancellation controls;
those require a separately qualified host adapter and authenticated transport.

## Authenticated HTTP mapping

[Host draft.1](../../host/0.2.0-draft.1/README.md) maps this unchanged receipt profile
to an opt-in same-origin loopback HTTP gateway. Each request authenticates
through the existing connected v1 session. The mapping adds immutable model
submission and explicit terminal release, with one fixed invocation inventory,
while retaining query/cancellation receipts and same-session reconnect rules.
Its separate descriptor is required before enabling live connected controls.
