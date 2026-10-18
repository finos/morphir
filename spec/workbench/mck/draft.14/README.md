# Execution transition corpus

This standalone offline kit selects exact Workbench MCK `0.1.0-draft.14`:
`reduce-execution`, JSON only. Its 170 fixed independent cases qualify the unchanged
`morphir/workbench/executions` `0.1.0-draft.1` receipt profile. Historical drafts.1–.5
remain unchanged and qualify separately; no historical cases are copied here.
Expectations belong to finos/morphir and never reach the adapter.

Cases cover scope binding at startup and on stale receipts; exact offers and
operation sets; UTF-16 identity/call boundaries; initial and maximum revisions;
replay, conflict, revision skips and unchanged-revision rejection; acknowledgement
monotonicity; ordered invocation inventory; all four terminal variants with
independent cleanup; terminal immutability; offline rejection, retained state and
same-session reconnect; malformed root/action/receipt/offer shapes; action,
invocation and projection budgets. A malformed nested Ion metadata payload
rejects only its observe action as `workbench.codec_failure`; the following
cancel-action still reads the retained submitted cursor.

`output-budget-retains-no-partial-projection` has a compact 1,041,450-byte input
and an independently specified 1,048,897-byte success projection, requiring
`workbench.execution_limit`. Over-budget input frames are tested at the runner/adapter
boundary, since the runner cannot accept one as a corpus input.

See [the exact contract](../../draft.14/README.md) for transport, error precedence,
projection details, limits and the distinction between offline qualification and
live host capability. Test helpers may assemble these fixed JSON objects; they
must not calculate expected transitions by invoking the implementation under test.
