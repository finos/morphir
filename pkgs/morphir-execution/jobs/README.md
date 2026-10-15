# Snapshot-bound Workbench jobs

This portable package admits the exact `morphir/workbench/jobs`
`0.1.0-draft.1` profile. The normative profile is contributed to finos/morphir at
`spec/workbench/jobs/draft.1/`. Existing terminal outcomes retain draft.5.

`Identity`, `Offer` and `Receipt` parse closed JSON shapes. `Cursor::start`
binds an authenticated offer, caller-owned expected identity, ordered call IDs
and the initial submission receipt. `observe` returns a new immutable cursor and
`Advanced`, `Replay` or `Stale`. Conflicts, identity mismatches, running-state
regressions, acknowledgement reversals and any changed terminal reject.
Query replies may skip revisions. The sequence is bounded by 2147483647 so it
has the same range on every supported target.

`cancel_action` selects a client action without modifying host evidence.
Acknowledgement does not mean cancellation completed; returned data can win that
race. `disconnect` retains the last receipt, and `reconnect` requires the same
authenticated host/session/provider and operation set. No terminal is invented
for timeout, disconnect, a local Cancel click or an RPC failure.

The cursor stores canonical private evidence and copies the call inventory.
Returned receipt copies and caller-owned arrays cannot mutate accepted history.
Only the latest receipt is retained; there is no growing event log.

The caller must cap raw framing at 1 MiB, reject duplicate JSON members, obtain
authority from authenticated submission and admit outputs against the submitted
public manifest. This package enforces receipt shape, bounded identities,
draft.5 payload admission, ordered terminal inventory and state consistency.
It does not establish host authenticity, snapshot provenance, durable recovery
or declared output types on its own.

Portable semantic tests cover cancellation races, stale/replayed/conflicting
receipts, monotonic revisions, disconnected observation, same-session reconnect,
all five identity dimensions, inventory checks, mutation isolation, UTF-16 and
sequence bounds, and separate primary/cleanup failures. This is contract work;
the current Workbench and connected host do not advertise live jobs. The shared
MCK draft.6 independently qualifies the existing reducer. The engine's
`finos/morphir-engine/execution/jobs` package adds a bounded host owner for
captured input, execution claims, cancellation acknowledgement and validated
terminal publication. Authenticated query/cancel transports and UI adoption
remain separate work.
