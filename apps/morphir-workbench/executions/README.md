# Private Workbench execution bridge

The existing host submission and execution receipts retain their exact draft.1 shapes.
The following private operations add the qualified Library Scheme execution path:

| Operation | Retained behavior |
| --- | --- |
| `submit-scheme` | Accept model, entry, JSON/Ion inputs, explicit Scheme runtime and provider. Resolve omitted checking policy to strict once. Return the unchanged submission fields plus a separate exact `morphir/workbench/execution-plan` draft.1 projection. |
| `plan-scheme` | Inspect a fresh projection of accepted runtime, policy, provider, plan identity and selected boundary. |
| `claim-scheme` | Require the accepted plan ID, provider, runtime and policy before the once-only claim. Build a private worker request from retained rich Ion checkpoint and invocation suite. |
| `replan-scheme` | Copy retained inputs and policy into new execution, snapshot and plan identities. Preserve the original execution and its history. Changing source or arguments requires a new submission. |

Query, cancellation, completion and terminal release retain their existing
receipt shapes. Completion reconstructs the accepted boundary from retained
source; a worker cannot widen output types with its own declarations.

The isolated worker reconstructs the captured rich unit, verifies the selected
boundary and evaluates with the accepted policy. It returns the plan projection
beside terminal outcomes. The Node provider checks this echo against its own
captured copy. A first mismatched plan remains a failure even if the worker later
sends a matching frame. Terminal publication waits for the actual worker exit;
cleanup failures stay distinct from returned values.

The legacy worker response cap remains 1 MiB. Policy-execution responses allow 3 MiB
for separately bounded 1 MiB terminal outcomes, a 1 MiB selected boundary and
fixed plan metadata. This bounds encoded messages, not process allocation.
The echo is a consistency check within the composing host, not authentication
of a worker's execution claim.

`createExecutionProvider().schemeCommand` is a private entry point. Existing HTTP and
native descriptors and server routes do not advertise or accept these new
operations. UI controls and native/HTTP capability mappings remain separate
integration tasks. The historical `admission` wire spelling is retained.

`scripts/capability-execution.test.ts` exercises actual isolated Node workers and
mutation, strict omission, reached operations, incompatible selection, independent
replans and mismatched worker frames. The separate draft.13 MCK adapter qualifies
controlled production Session traces; its supplied-completion cases do not prove
execution or worker cleanup.
