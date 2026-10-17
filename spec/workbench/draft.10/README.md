# Native owner qualification

Exact offline Workbench MCK `0.1.0-draft.10` adds the JSON-only
`run-native-owner` operation to the existing shared Rust runner. Historical MCK
drafts.1 through .9 and the live `morphir/workbench/native` `0.1.0-draft.1`
contract are unchanged.

```sh
morphir mck workbench run --kit spec/workbench/mck/draft.10 \
  --adapter /path/to/owner-adapter --report report.json
morphir mck workbench check --kit spec/workbench/mck/draft.10 --report report.json
```

Capabilities require exactly `operations: ["run-native-owner"]`,
`formats: ["json"]`, `suite: "workbench"`, and
`contractVersion: "0.1.0-draft.10"`. Adjacent drafts and build suffixes reject.
The existing bounded NDJSON transport and positive safe-integer request IDs apply.
The adapter receives only case inputs, never case IDs or expected results.

## Controlled inputs

The [schemas](schemas/) define closed infrastructure shapes. Every asset is
inline in `cases.json`; its original-byte hash covers the complete fixture.

- `context` contains window and origin strings of at most 128 Unicode code
  points and a nullable page string of at most 256. This controls an out-of-band
  host input. It does not authenticate OS caller provenance.
- `services` selects jobs as `enabled`, `disabled`, or `unavailable`, and a
  boolean workspace availability flag.
- `evaluation` contains the complete model source, entry, and JSON or Ion
  argument source under the draft.9 limits. JSON arguments must be one complete,
  duplicate-free array. The runner leaves model and Ion source opaque.
- `roots` declares up to eight fixture roots, each with a unique ASCII token,
  complete `morphir.json` manifest source, and up to four uniquely named files.
  File names are `morphir-ir.json`, `morphir-ir.ion`, `morphir-ir.10n`, or
  `morphir-ir.ionb`. Encoding is `utf8` or canonical padded `base64`.
- `pickers` declares ordered picker dependencies with a unique boundary ID,
  `held` and `fail` booleans, and a declared root ID or null for cancellation.
- `cleanups` declares ordered cleanup dependencies with a unique boundary ID,
  session alias, `held`, and `success`. There is at most one cleanup declaration
  per session alias. Its settled success or failure is shared by all shutdown
  waiters; a second cleanup cannot overtake a held confirmation.
- `actions` contains at most 32 explicit steps. `call` starts a native operation
  with an attempt ID and its operation-specific session, job, grant, project,
  sequence, or offset fields. Job submission uses `evaluation`. `context`
  changes the trusted host input. `revoke` and `close` revoke or close the owner.
  `shutdown` starts a shutdown attempt. `deliver` releases one declared held
  picker or cleanup. `complete` supplies an opaque outcomes object to the
  controlled production job host. `replace` changes an existing root/file
  checkpoint; it is fixture host I/O, never a renderer write capability.

Attempt IDs are unique across calls and shutdowns. Boundary IDs are unique across
pickers and cleanups, with at most 128 combined declarations. Deliveries name a
held boundary at most once; a declared boundary not entered by the implementation
is observed as unavailable. Replacement roots and files must already be declared.
Workspace sequences use the native range 1 through 2,147,483,647; read offsets use
0 through 16,777,216. IDs contain 1–128 characters from `[A-Za-z0-9_.-]`.

Manifest source is at most 16,384 code points. Each file source is at most 393,216
code points and 262,144 decoded bytes. Model source is at most 262,144 code points,
entry 512, and argument source 16,384. The compact encoded input is at most
491,520 UTF-8 bytes. Literal shapes and duplicate members are checked before typed
conversion, including JSON library private marker objects. Opaque completion
objects remain subject to those infrastructure guards. Frozen draft.5 outcome
validation belongs to the production `jobs.Host`, not the runner.

Aliases refer to prior returned identities. An unresolved request alias produces
an observed rejected result with `reply: null`, `cleanup: null`, and
`failure: "reference"`, without invoking the owner or dependencies. It never
constructs a guessed native token. An unresolved completion job yields
`completion: "unavailable"`.

## Observations and fixed expectations

Every scenario with valid fixture infrastructure returns `{"status":"ok","value":...}`. Domain refusals
are native replies in the projection. This operation has no domain-invalid
observation. Malformed infrastructure or observations are runner errors.

The closed projection contains ordered `steps`, final `results`, actual
ordered dependency `calls`, and used/unused picker and cleanup counts. Each step
records its action, ordered attempt IDs and states, call count, delivery result,
and completion result. Delivery is null, `delivered`, `unavailable`, or
`already-delivered`. Completion is null, `unavailable`, or canonical JSON text.

Results retain attempt ID, state, reply, cleanup, and failure. Pending results
have null reply, cleanup, and failure. Returned requests contain a success reply
with the operation and canonical JSON value text, or an error reply with one of
the six portable native codes and effect `none` or `unknown`. Returned shutdowns
have null reply and cleanup true; rejected shutdowns have cleanup false. Ordinary
results use failure null; unresolved request aliases use `"reference"`.

Success values, completion results, and dependency calls are canonical JSON
strings with recursively sorted object keys. Array order and opaque text remain
unchanged. Only known identity positions are canonicalized by the adapter,
retaining consistent identity, freshness, equality, and stale-reference behavior.
The runner does not decode these strings or implement owner transitions.

Expected error effects may be an exact string or a fixed, nonempty, unique array
of permitted effects, such as `["none", "unknown"]`. Use a set only where the
accepted native contract allows either precise no-effect rejection or a
conservative unknown rejection. Keep exact effects where uncertainty or
rejection with no new effect is established. The Rust runner owns set membership.
Actual observations and saved reports always contain one string effect and
reject effect arrays. All other projected fields compare exactly.

Each projection is bounded to 1 MiB. Existing aggregate observation, transport,
and 32 MiB report bounds apply. A well-formed mismatch is a compatibility failure;
an invalid observation is an exchange error. The checker reloads the original
corpus, verifies its hash, inventory, capabilities and observations, and recomputes
verdicts and qualification. Truthful unqualified reports remain checkable and
produce a nonzero CLI exit status.

## Production boundary

The adapter exercises actual production `bridge.Owner`, session authority,
`workspace.Service`, and `jobs.Host`, with trusted controlled factories and
in-memory root bytes. Explicit completion and cleanup gates control scheduling.
Cooperative task boundaries settle callbacks; wall-clock sleeps never decide a
verdict. Teardown happens after the final snapshot, suppresses recording, revokes
the owner, and releases controlled gates.

Transcript tests qualify runner evidence handling only. Owner MCK does not
establish authenticated OS provenance, filesystem race or containment behavior,
real worker execution or exit, or packaged OS/architecture conformance. Production
native services and packaged acceptance retain their separate evidence.

## Dependency event contract

Each dependency call is one canonical JSON string whose object includes `event`
and exactly the fields in this table. Calls appear in actual invocation order.
They are observations, never verdicts.

| Event | Fields besides `event` | Meaning |
| --- | --- | --- |
| `jobs.create` | `session` | Trusted jobs factory entry, recorded before a possible factory failure |
| `jobs.offer` | `session` | Actual offer request on the retained production job host |
| `jobs.request` | `session`, `operation`, `payload` | Actual jobs service request; payload is canonical normalized payload JSON text |
| `jobs.claim` | `session`, `job`, `request` | Actual production claim; request is the canonical actual claim value text with only `source` removed |
| `jobs.close` | `session` | Actual owner invocation of the retained service close port |
| `cleanup.begin` | `session`, `id` | Actual cleanup waiter entry; ID is a declared boundary or null |
| `cleanup.result` | `session`, `id`, `success` | Actual waiter result, including a cached result |
| `picker.begin` | `id` | Picker entry; ID is a fixture boundary or null |
| `picker.result` | `id`, `root`, `failed` | Picker result; root is a fixture root or null |
| `root.open` | `root` | Actual root open |
| `root.current` | `root` | Actual current-root check |
| `root.snapshot` | `root` | Actual snapshot request |
| `root.read` | `root`, `name`, `size` | Actual checkpoint read; size is byte length and contents are not duplicated |
| `root.close` | `root` | Actual root close |

A missing picker returns cancellation, records begin/result with null IDs, and
consumes no fixture. Completion appears only in the action step's `completion`,
without a duplicate call event. `shutdown` does not itself call the close port;
`jobs.close` records only an actual owner invocation.

`jobs.claim.request` removes only the generated claim's `source` field before
canonicalization. This avoids fixing incidental generated-model JSON
serialization in the shared expectation. All other claim fields remain observed.
`jobs.request.payload` already retains the exact immutable input model text, and a
separate production importer/evaluator gate proves the concrete asset evaluates
to Int 42. Model text remains opaque to the runner.

Cleanup begin/result events are per actual waiter, including a cached result.
`usedCleanups` counts only the first entry to each declared gate. A missing cleanup
is immediately confirmed success with a null boundary ID. A declared cleanup's
settled success or failure is memoized per retained service and shared by every
waiter. Repeated shutdowns cannot create an independent cleanup that overtakes a
held confirmation or changes its settled result.

## Identity allocation and reverse references

There are six disjoint alias domains: `session`, `host`, `grant`, `project`,
`job`, and `snapshot`. Each allocates `<domain>-N` starting at 1, in semantic
encounter order, with one trace-wide bijection per domain and scope.

| Domain | Identity scope |
| --- | --- |
| Session | Entire trace |
| Host | Actual session |
| Grant | Retained workspace service lifetime |
| Project | Actual grant |
| Job | Actual host/session/provider tuple |
| Snapshot | Actual host/session/provider tuple |

Repeated identity fields retain equality. Distinct unexpected identities never
merge. Allocation visits descriptors as session, then offer host/session; receipt
identity as host/session/job/snapshot; and workspace offers as grant, then projects
in their array order. Dependency calls and replies share the same maps. JSON
member order never changes allocation.

Only known native identity positions are normalized. Opaque model source, typed
values, terminal outcomes, JSON/Ion arguments, and checkpoint bytes retain their
contents even when text resembles an identity. Previously encountered stale
aliases reverse-resolve to the original actual identity. An unobserved input
alias rejects with `failure: "reference"` and null reply/cleanup, without any
owner invocation. No guessed token is sent to native authority checks.

A known retained job identity is always forwarded to production `jobs.Host` by
`complete`, including after terminal completion, release, or service close. The
adapter must not fabricate receipts or silently discard a transition. An unknown
job alias alone produces completion `"unavailable"`.

## Cooperative quiescence

Before recording each action snapshot, settle at cooperative task boundaries
until every launched attempt and every background cleanup reserved by an actual
close callback has either returned or reached an entered held gate. Pending work
is classified through those explicit states. Neither a fixed yield count nor
elapsed time may classify an attempt as pending or determine a verdict.

An entered held gate decrements the runnable-work count while blocked and
restores it before broadcasting delivery. Only explicit `deliver` and `complete`
actions advance held effects. Delivery before the actual boundary entry observes
`unavailable`; declared fixture availability never simulates a dependency call.
After the final snapshot, teardown suppresses further event recording, revokes the
owner, and releases all controlled gates.

The controlled job provider is exactly `moonbit-scheme`. This fixture constant is never aliased or advertised as an additional runtime provider. The fixed corpus has 43 owner traces. Release-before-open traces establish sequence retirement for that request ordering; they do not represent asynchronous filesystem IO races.
