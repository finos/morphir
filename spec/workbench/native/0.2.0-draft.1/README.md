# Native Workbench mapping

This opt-in profile is named `morphir/workbench/native` and supports exactly
`0.2.0-draft.1`. It maps page-bound desktop IPC to immutable evaluation executions and
read-only workspace grants. Publication does not advertise an implementation or
qualify a packaged platform. The initial implementation source is
[Morphir MoonBit PR #97](https://github.com/finos/morphir-moonbit/pull/97), merged
at `eac87d65bce627cbf387fce50c5757d904c57c78`. Its bootstrap is private and does
not implement this public mapping yet.

Connected v1, the [HTTP host](../../host/0.2.0-draft.1/README.md),
[executions](../../executions/0.2.0-draft.1/README.md) `0.2.0-draft.1` and
[terminal outcomes](../../draft.5/README.md) `0.1.0-draft.5` remain unchanged.
The native descriptor contains an execution offer directly. It never advertises the
HTTP host profile, HTTP status codes, cookies or an invented HTTP session.

This pre-1.0 contract replaces the published job terminology through a breaking
change. Old job-based identities, operation names and routes are not aliases.
The previous published schemas and qualification records are historical evidence.

## Trusted caller and session lifetime

The desktop owner validates every command using framework-supplied window,
bundled-origin and page-instance identity. These values come from trusted native
context, outside the JSON request. Renderer-supplied URLs, page labels, session
IDs, grant IDs and execution IDs are never credentials. A command from a remote page,
iframe, different window or retired page fails before it creates authority. The
binding must distinguish the authorized top-level page from its frames.

Only a qualified bundled application page can open a session. The owner issues
a fresh opaque session ID when a different page instance opens. Repeated open
from the same live page returns the same descriptor. Check revalidates that page
and session; it grants no new capabilities. Operations stay fixed for a session.
Close revokes its grants and waits for confirmed child-worker exit before
returning success. It cannot close a newer session.

Navigation, reload, bridge failure, renderer termination and window close revoke
the old page even when its close command never arrives. An old asynchronous
reply cannot reconstitute authority. The host checks the captured caller and
session again after an OS picker or other asynchronous authority boundary and
before publishing success. Clients discard replies after disposal or a session
change. New execution is blocked until old-page children have exited; failure
to confirm cleanup prevents a new execution claim and successful shutdown.
Application shutdown revokes all pages and waits for children independently of
renderer cooperation.

## Negotiation

The native binding accepts one raw UTF-8 JSON request per invocation. Framework
command names and CEF/Proton internals are binding details; the portable operation
names and JSON envelopes below are the contract. No renderer-chosen path, URL,
executable, environment or native command name is dispatched.

```json
{"profile":"morphir/workbench/native","contractVersion":"0.2.0-draft.1","operation":"session.open"}
```

Every subsequent request adds the issued `sessionId`. All requests carry the
same exact profile and version. `session.check` and `session.close` have no
payload. Success has exactly `ok`, `operation` and `value`. The client must
correlate each completion to its exact originating invocation through the native
binding, including concurrent requests with the same operation. It also checks
the operation; a structurally valid reply for a different operation is rejected.
Open and check return this descriptor in value:

```json
{
  "profile": "morphir/workbench/native",
  "contractVersion": "0.2.0-draft.1",
  "sessionId": "native-session",
  "operations": ["executions", "workspace"],
  "offer": {
    "profile": "morphir/workbench/executions",
    "contractVersion": "0.2.0-draft.1",
    "hostId": "native-host",
    "sessionId": "native-session",
    "providerId": "scheme",
    "operations": ["query", "cancel"]
  }
}
```

`operations` is exactly one of `[]`, `["executions"]`, `["workspace"]`,
`["executions","workspace"]`. The sorted list is closed, unique and stable.
`offer` is required exactly when `executions` is present and is the frozen executions offer.
Its session ID must equal the native session ID. The owner issues a new host ID
on startup and binds the provider independently. No offer authorizes executable
source or a provider selected by renderer data. A native client validates this
descriptor into the same executions-offer domain as an authenticated HTTP client;
transport-specific descriptor validation precedes the shared receipt cursor.

Native session, grant and project IDs contain 1 to 128 ASCII letters, digits,
underscores, periods or hyphens. Nested execution identities retain their existing
1 to 128 UTF-16-unit bounds. Unknown fields, profiles, versions, build suffixes
and operations reject. Version selection by range uses an established SemVer
library; this draft matches only literally `0.2.0-draft.1`.

## Executions over IPC

`execution.submit`, `execution.query`, `execution.cancel` and `execution.release` require the negotiated
executions capability. Cancel additionally requires `cancel` in the nested offer.
Their `payload` reuses the frozen HTTP mapping's document shapes, without its
HTTP envelope or authentication mechanism:

| Operation | Payload | Success value |
| --- | --- | --- |
| `execution.submit` | [Submission](../../host/0.2.0-draft.1/schemas/submission.schema.json) | [Initial submission reply](../../host/0.2.0-draft.1/schemas/submission-reply.schema.json) |
| `execution.query` | [Identity request](../../host/0.2.0-draft.1/schemas/identity-request.schema.json) | Frozen executions receipt |
| `execution.cancel` | Same identity request | Frozen executions receipt |
| `execution.release` | Same identity request | `{"released":true}` |

The reused payload's own `contractVersion` remains required. Submission contains
Morphir IR JSON source text, a public entry, and one JSON-tagged or Ion-text
argument list. Validate the IR revision, entry, types and argument bounds, and
check runtime/provider capabilities and limits before accepting execution. Model and argument source are data, never
paths or executable authority. The accepted snapshot is immutable. UI edits,
workspace changes, query and reconnect cannot alter it or execute it twice.
The fixed call inventory is `["workbench"]`; bind all five returned identity
fields and the initial sequence-zero submitted receipt before opening a cursor.

Every execution operation checks the trusted page and exact retained session, host,
provider, execution and snapshot. Query does not advance sequence merely because it
was polled. Cancellation acknowledges a request separately from termination;
terminal evidence follows confirmed execution exit and cleanup. A committed
result may win a cancellation race. Terminal release cannot terminate running
work. Capacity rejection cannot silently evict retained executions. Source, terminal,
SDK model error, primary failure and separate cleanup evidence retain their
existing meanings and validation rules.

A lost transport leaves the last validated receipt intact. Reconciliation needs a
fresh native check and the exact same host, session, provider, version and
operations. Only then may the client query the old identity with its existing
cursor. Reload creates a different page authority, so it cannot adopt the old
execution. There is no cross-session recovery, persistence or submission discovery.

## Read-only workspace grants

The workspace capability permits only the operations below. Only the native OS
directory picker supplies an absolute root. The renderer cannot request a path,
construct a grant from a string or turn a read grant into a write grant. Save
dialogs for explicit file exports are separate host policy, outside this grant.

| Operation | Payload | Success value |
| --- | --- | --- |
| `workspace.choose` | Absent | `{"cancelled":true}` or a fresh grant offer |
| `workspace.cancel-picker` | Absent | `{}` |
| `workspace.revoke` | `{"grantId":"grant"}` | `{}` |
| `workspace.open` | `{"grantId":"grant","projectId":"project","sequence":1}` | Capture metadata |
| `workspace.read` | `{"grantId":"grant","sequence":1,"offset":0}` | One original-byte chunk |
| `workspace.release` | `{"grantId":"grant","sequence":1}` | `{}` |

Choose permits at most one pending picker. Cancelling or declining it preserves
the existing grant. Success atomically replaces that grant only after discovery
and page revalidation. Each picker has an owner-held generation. Completion and
error cleanup for a retired picker must not cancel a newer picker. Revocation
invalidates pending picker results as well as captures. Framework picker latency
has no protocol deadline; a client timeout does not authorize a late result.

A grant offer contains exactly `cancelled:false`, `grantId`, `projects` and
`warnings`. Each project row has `id`, display `name`, `available` and display
`message`. IDs are opaque and belong only to that grant. Display labels and
warnings are plain text and grant no authority. The owner issues unique project
IDs within each grant. While validating an offer, the client rejects repeated
IDs even if their display metadata differs. It never opens an ambiguous token.
Unavailable rows cannot open.
At most 128 project/model rows and 128 warning strings are returned; labels and
messages contain at most 1,024 Unicode code points. Offers occupy at most
524,288 UTF-8 bytes including their reply envelope.

Discovery is a bounded observation, not an atomic filesystem snapshot. The
implementation uses Morphir configuration/member discovery and only saved
model checkpoints, with no scripts, compilation, watch or persistence. It
holds the picked root through native filesystem authority, checks each component
relative to it, and rejects traversal, symlinks, hard-linked files, special files,
changed ancestor/file identities and root replacement. Descriptor handles cannot
leak into child workers. If a target cannot enforce these rules it does not
advertise workspace support. Limits are 4,096 entries, 256 directories, depth 16,
262,144 bytes per configuration and 2,097,152 aggregate configuration bytes.
Prune `.git`, `node_modules`, `_build`, `.mooncakes`, `.idea` and `.vscode`.
The selected filesystem can still impose latency outside these count limits.

Open captures at most 16,777,216 original bytes, rechecking discovery
and file identity before and after reading. It returns `sequence`, `size`,
`format` and a display-only basename `filename`. Format is `morphir-json`,
`ion-text` or `ion-binary`; an Ion binary version marker determines binary
encoding for ambiguous `.ion`/`.10n` names. The capture is immutable. Preserve
original bytes, IR revision and rich Ion metadata; parsing business numbers in
JavaScript is not a required intermediate step.

Capture sequence is an integer from 1 through 2,147,483,647, increasing within a
grant. The client reserves it before sending open. Release retires that sequence
even if it arrives before a delayed open, preventing that open from restoring it. It clears
only a matching active capture. A stale release cannot clear a newer capture.
The client confirms release before starting another capture. Failure to confirm
release blocks capture reuse until cleanup is reconciled or the grant is revoked.

Read requires the exact current sequence and next byte offset. Its value has
`sequence`, `offset`, canonical padded `content` base64 and `done`. Decode at most
196,608 bytes per chunk, at most 262,144 base64 characters. Offsets count bytes;
the returned offset equals the request's offset, and the next offset advances by
decoded length. `done` agrees with the validated total size; empty content is
valid only at end. The host advances its cursor on read. A lost read reply cannot
be retried as an idempotent read: release and reopen with a fresh sequence.
Do not inspect or publish a partial model as success.

## Closed errors and raw framing

Failure has exactly this shape, with no success operation or value:

```json
{"ok":false,"error":{"code":"conflict","effect":"unknown","message":"The request effect could not be established"}}
```

| Code | Meaning |
| --- | --- |
| `invalid_request` | Invalid shape, version, source codec or declared-call validation |
| `unauthorized` | Trusted caller or page/session check failed |
| `unavailable` | Operation absent or required service/cleanup unavailable |
| `not_found` | Unknown/released execution, project or capture |
| `conflict` | Invalid transition, stale grant or exhausted retained-execution capacity |
| `limit` | Byte, depth, count or resource budget exceeded |

`effect:"none"` means the owner confirms this request caused no new effect.
It does not deny effects of earlier requests. `effect:"unknown"` means the owner
cannot establish this request's effect. Error category alone cannot imply
rejection before request acceptance. Only an authoritative `none` reply confirms a
submission was rejected; it still never triggers automatic retry. Timeout, lost
or malformed reply, a changed session and failure after request acceptance leave submission
effects unknown. A new explicit submission must not masquerade as recovery.
Errors never fabricate terminal execution evidence or confirmed capture cleanup.
Messages contain 1 to 512 code points and must omit model/argument source,
credentials, filesystem paths, stderr and stacks. Render messages as plain text.

Every complete request or response is at most 1,048,576 bytes of raw UTF-8,
including this profile's wrappers. Workspace commands additionally fit 4,096
bytes; grant offers have the smaller limit above. The existing payload schemas'
string maxima do not reserve wrapper bytes. Reject oversized frames before
parsing and reserve wrapper space before publication. Never truncate a receipt.

Reject malformed UTF-8, multiple JSON values and duplicate object members at
every depth, including escaped-equivalent names. Apply duplicate rejection again
inside model JSON and JSON argument source strings. Enforce bounded parsing
before recursive allocation: maximum JSON depth 64, at most 100,000 aggregate
nodes and at most 1,048,576 decoded string code units per outer frame. The reused value codec's
own per-call budgets also apply. No native paths or credentials are accepted in
place of source documents. A bridge that first performs lossy JSON parsing
cannot claim raw duplicate or encoding qualification without an earlier checked
boundary.

## Evidence and adoption

Run `mise run workbench:schema-check` for the three closed schemas and independent
positive/negative structural tests. Shared identities, offers and later receipts
reference the existing frozen schemas. The exact frozen submission and initial
reply shapes are expanded within the native schemas to avoid validator optimizer
instability when those references sit beneath operation conditionals. The
normative payloads above remain unchanged. There is no new compatibility runner.
These schemas cannot establish per-grant project-ID uniqueness, nested identity
equality, UTF-16 execution limits, canonical base64, raw-byte budgets, duplicate keys,
trusted caller identity, filesystem races, state transitions or confirmed exit.
Structurally valid mismatched identity/source fixtures deliberately preserve
those runtime obligations.

[Raw fixtures and lifecycle traces](fixtures/README.md) record fixed expectations
for the next shared Rust MCK/adapter contribution. They are not executed by the
schema task and are not qualification results. Keep those results separate from
actual packaged native context tests. Synthetic caller objects cannot establish
framework origin/page provenance or OS picker authority.

Public adoption must replace the private bootstrap and HTTP-shaped internal
native offer, validate this descriptor without weakening HTTP authentication, and
retain the shared executions cursor. Then qualify actual bundled executions, caller rejection,
navigation/reload revocation, picker races, capture release, cancellation and
shutdown against the published contract. Rerun standalone browser and real
connected v1/gateway acceptance. Record each packaged OS/architecture separately;
macOS Apple Silicon evidence does not qualify Linux or Windows GUI builds, and
CEF-free filesystem/process acceptance does not qualify a packaged desktop.
Until those gates pass, the public native profile remains unadvertised.
