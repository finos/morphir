# Host-owned Workbench executions

`finos/morphir-engine/execution/executions` owns bounded in-memory execution state for a
composing host. It uses the exact `morphir/workbench/executions` `0.2.0-draft.1`
profile and the shipped receipt cursor. It adds no wire methods or capability
advertisement. Connected protocol v1 remains unchanged.

Create one `Session` for each host/session/provider authority, using the offer
that the host will authenticate. Session identities must be fresh across owner
replacement. The composing host serializes access, authenticates callers, enforces
provider grants and dispatches work. This synchronous component performs no I/O
and does not authenticate an offer or establish provider trust.

## Ownership and execution

1. `submit(unit, suite)` captures the full rich unit as an Ion binary checkpoint
   and the suite through the bounded invocation codec. Planning validates public
   entries and arguments before the host accepts the execution. The initial receipt
   binds host/session/provider plus new execution and snapshot IDs. These snapshot
   handles denote retained input, not a path or content hash.
2. `claim(identity)` reconstructs an independent execution plan and publishes a
   running revision. Only one claim succeeds. The worker can use the existing
   execution provider or evaluator against this plan. Losing the worker connection
   does not authorize another execution claim.
3. `query(identity)` returns a fresh copy of the authoritative receipt. Every
   operation checks the entire identity, including the snapshot.
4. `cancel(identity)` acknowledges a request if the composing host offered
   cancellation. Workers must query this acknowledgement at their cancellation
   points. Repeated acknowledgement and queries do not advance the revision.
   Acknowledgement does not terminate work or replace returned data. Query-only
   offers reject cancellation while work remains pending.
5. After the worker and cleanup finish, `complete(identity, outcomes)` reconstructs
   the submitted public declarations and validates all terminal outputs before
   publication. A worker cannot widen output types by editing its plan. Ordinary
`Result.Err` remains returned data; SDK errors, failures, cancellation and
   cleanup retain their separate variants. Completion may occur before a claim
   for a host policy rejection or cancellation. An identical terminal is an
   idempotent replay; a different terminal rejects.
6. `release(identity)` explicitly frees terminal storage. Pending work cannot be
   released, and capacity pressure never evicts another execution. Released identities
   become unknown, and subsequent submissions do not reuse their IDs.

Cancellation is cooperative. The host must only offer it when its worker can
observe requests. `complete` is a trusted host publication API, not an endpoint
for an untrusted worker to assert that cleanup finished. The component validates
the evidence shape and declared types, not whether an external provider told the
truth. Disconnect and transport timeout have no receipt-producing API.

## Bounds

Defaults allow eight retained executions and 16 MiB of serialized retained evidence.
Configuration allows 1 to 64 executions and 1 to 64 MiB. Each submission reserves the
checkpoint bytes, encoded suite bytes and a full 1 MiB receipt allowance. This
keeps terminal publication independent of later submissions. The existing data
boundary limits each checkpoint to 4 MiB, and invocation and receipt codecs each
limit their encoded payloads to 1 MiB. Quotas describe retained serialized data,
not allocator overhead or temporary planning allocations. A quota too small for
one validated snapshot simply refuses submissions.

Validation, capacity and transition failures leave retained work unchanged.
IDs advance only on successful submissions and never wrap. State survives a
client disconnect only while the composing host retains this owner. There is no
durable storage, restart recovery, retry lease, deduplicated submission or
exactly-once execution guarantee.

## Scheme runtime and capability checking policy

The parallel `submit_scheme(unit, suite, policy=...)` route captures the bounded
Library Scheme runtime and its shared SDK. Omitted policy resolves to `Strict`
once, at acceptance. Explicit `Permissive` uses the qualified reached-only
capability checks. The legacy `submit` and `claim` methods keep their existing
compiled-plan validation; claims cannot cross between these routes.

`describe_scheme(identity)` returns a fresh domain projection containing the full
execution identity, opaque `plan_id`, runtime, effective policy and selected boundary.
It adds no fields to the frozen receipt or offer. A composing adapter supplies
its own exact negotiated projection and authenticates the provider.

`claim_scheme(identity, plan_id, provider_id, runtime, policy)` requires every
selection component to match the accepted execution before advancing its cursor. It
returns the immutable `SchemePlan` once. `SchemePlan.unit()` and `.suite()` decode
fresh copies for an isolated worker; edits to these copies, the original input
or a projection cannot change accepted source, arguments, policy or boundary.
Completion reconstructs from retained bytes and policy, compares the selected
boundary, then validates every terminal against that context. Retained boundary
bytes count toward the session quota alongside the source, suite and reserved
terminal space.

`replan_scheme(identity, plan_id, provider_id, runtime, policy)` reconstructs only
the original accepted inputs. It preserves policy and allocates fresh execution,
snapshot and plan identities. It never claims or schedules either execution and leaves
the original history and once-only eligibility unchanged. Editing source or
arguments requires a new submission. An incompatible replacement selection
rejects explicitly; it cannot downgrade policy or silently switch a provider.

Query, cancellation, completion replay and release use the same receipt cursor
for both routes. These core methods do not authenticate a worker, establish
cleanup truth, advertise native or HTTP support, or grant execution authority.

## Validation and remaining integration

Tests run on JS, native, Wasm and Wasm GC. They exercise actual bounded Scheme
evaluation, exact arithmetic, returned errors, SDK errors, mutation isolation,
all identity dimensions, cancellation races, replay/conflicts, terminal cleanup,
validation failures and retention quotas. The unchanged receipt reducer has shared
MCK draft.6 qualification. These producer tests do not independently qualify an
authenticated host adapter.

The existing Workbench execution bridge and native owner compose this core with their
own transport and scheduling. Policy-aware UI, native and HTTP capability offers
still require separate integration and qualification. Generated browser execution
and durable recovery remain separate work. This package does not automatically
use metadata host grants or advertise trusted naming providers.
