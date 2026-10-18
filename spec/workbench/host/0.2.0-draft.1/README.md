# Authenticated Workbench HTTP host

This opt-in HTTP profile is named `morphir/workbench/host` and supports exactly
`0.2.0-draft.1`. It binds the existing
[execution receipt profile](../../executions/0.2.0-draft.1/README.md) to authenticated submission,
query, cancellation and explicit terminal release. It preserves the exact executions
`0.2.0-draft.1` and terminal outcome `0.1.0-draft.5` contracts.

The gateway uses the real Rust connected v1 host's `/launch` exchange and
HttpOnly session cookie. Connected `protocolVersion: 1`, its session manifest and
JSON-RPC methods remain unchanged. The separate host descriptor below is the
only live advertisement of this extension. Offline MCK capabilities, a visible
Evaluate button, a provider name or successful compilation do not advertise it.
An absent or disabled host extension leaves connected evaluation unavailable.

This pre-1.0 contract replaces the published job terminology through a breaking
change. Old job-based identities, operation names and routes are not aliases.
The previous published schemas and qualification records are historical evidence.

## Authentication and origin

The gateway serves the UI and this extension at one loopback HTTP origin. It
proxies the connected v1 `/launch` exchange without exposing the token or cookie
to application JavaScript. It preserves the upstream cookie's HttpOnly and
SameSite protections. JavaScript sends only same-origin requests with that
cookie. A gateway does not invent an authenticated session or accept a caller's
session label as proof.

Every request under `/api/workbench/` requires a new successful authenticated
upstream `GET /api/session`, using that request's session cookie. This includes
query, cancellation and release. A cached successful descriptor is insufficient.
The gateway requires the exact expected connected v1 manifest shape and version;
it must not follow an upstream redirect to a different authority or forward the
cookie outside its configured loopback upstream. Authentication failure returns
401. An unreachable, timed-out or invalid upstream returns 503 and grants no
authority. A changed authenticated session cannot adopt a retained execution and
returns 409 for that identity.

All host endpoints require the configured loopback Host authority. A request
with an unexpected Host is rejected. Cross-site Fetch Metadata requests are
rejected. Every POST requires an explicit `Origin` exactly equal to the gateway's
HTTP origin, including scheme and port; missing, `null`, malformed, multiple or
different origins return 403. No CORS permission is granted. Mutating GET routes,
URL-carried execution identities and launch credentials in host request bodies are
not supported. Host responses use `Cache-Control: no-store` and JSON content
with a declared UTF-8 encoding; they must not be reused as authenticated offers.

The gateway owner creates a fresh opaque `hostId` at startup. It is not the
connected v1 `sessionId` or an execution `providerId`. The separately selected
provider is an explicit bounded Scheme execution provider for this first slice.
Provider selection does not grant metadata authority or reuse another provider's
identity. A process restart creates a different host authority, even if an
upstream session cookie survives.

## Negotiation

`GET /api/workbench/session` returns HTTP 200 and exactly:

```json
{
  "profile": "morphir/workbench/host",
  "contractVersion": "0.2.0-draft.1",
  "offer": {
    "profile": "morphir/workbench/executions",
    "contractVersion": "0.2.0-draft.1",
    "hostId": "host",
    "sessionId": "session",
    "providerId": "scheme",
    "operations": ["query", "cancel"]
  }
}
```

The offer's `sessionId` must equal the freshly authenticated v1 session ID.
`query` is required; `cancel` is optional. The operation list describes receipt
operations, so `submit` and `release` are not added to it. The host descriptor
implies the submission contract in this document. Cancellation remains disabled
unless the offer includes it. A disabled extension or unavailable cancellation
operation returns 404 rather than an invented successful receipt.

Unknown profile names, versions, build suffixes and members reject. This exact
prerelease does not accept a released `0.1.0` or a later draft. Implementations
that select versions through ranges must use an established SemVer library.
All five identity fields retain the executions profile's 1 to 128 UTF-16 unit limits.

## One immutable submission

`POST /api/workbench/submit` accepts exactly:

```json
{
  "contractVersion": "0.2.0-draft.1",
  "model": "{\"formatVersion\":3,\"distribution\":[\"Library\",[],[],{\"modules\":[]}]}",
  "entry": "sample:main#add",
  "inputs": {
    "format": "json",
    "source": "[{\"type\":\"int\",\"value\":\"2\"},{\"type\":\"int\",\"value\":\"3\"}]"
  }
}
```

The model field is Morphir IR JSON source text, not a filesystem path, URL,
workspace handle or executable source. The example illustrates the wire shape;
a runnable model also needs the selected public entry. The implementation must
validate the declared IR revision and may migrate a private copy to its execution
revision. It must reject unsupported or malformed IR before execution. It must
not read a path or fetch a URL found in either source field.

`entry` is a public fully qualified function name containing 1 to 1,024 UTF-16
units. The host validates the model, public entry, declared argument types,
constructor registry, and checks runtime/provider capabilities and limits before accepting
an execution claim. A caller cannot select a host, session, provider, snapshot, execution or call ID
through this body. The accepted immutable snapshot contains this exact validated
model, entry, arguments and provider binding. Subsequent UI edits cannot alter it.

`inputs` has exactly `format` and `source`:

| Format | Source document |
| --- | --- |
| `json` | One JSON array of zero to 64 tagged argument values from the [value codec](../../README.md#json-values). |
| `ion-text` | One unannotated Ion list of zero to 64 argument values using the [published Ion mapping](../../README.md#invocation-suites-and-ion). |

For example, JSON arguments `[{"type":"int","value":"2"}]` and Ion arguments
`[2]` denote the same one-argument list. Empty arguments are `[]` in both formats.
Ion Bool, Int and Decimal use their native scalar types; Unit is
`morphir_unit::null`; the remaining typed values use one `morphir_value`
annotation on their tagged struct. An Ion datagram containing several values,
Ion binary source, an invocation suite envelope or an untyped JSON number array
is not an argument-list document for this endpoint. Exactly one source value
must consume the entire input. Codec limits and declared-call validation still apply,
including depth 64, 100,000 aggregate value nodes/code units per call, numeric
bounds and unique record fields. The model and argument source are part of the
same HTTP body budget, not separate allowances. This endpoint has no extensions
metadata field.

Successful validation returns HTTP 200 and exactly:

```json
{
  "identity": {
    "hostId": "host", "sessionId": "session", "providerId": "scheme",
    "executionId": "execution", "snapshotId": "snapshot"
  },
  "calls": ["workbench"],
  "receipt": {
    "contractVersion": "0.2.0-draft.1",
    "identity": {
      "hostId": "host", "sessionId": "session", "providerId": "scheme",
      "executionId": "execution", "snapshotId": "snapshot"
    },
    "sequence": 0, "state": "submitted", "cancelRequested": false,
    "outcomes": null
  }
}
```

The caller captures the top-level identity and fixed inventory `['workbench']`
as expected authority from this authenticated submission. The identity's first
three fields must equal the previously authenticated offer. The receipt's full
identity must equal the top-level identity. The client rejects a mismatch before
creating its receipt cursor. The initial receipt is always sequence 0,
`submitted`, with false acknowledgement and null outcomes, even if execution
completes before the HTTP reply arrives. A later query observes later revisions.

The owner accepts at most one execution claim per accepted execution. Query, cancel and
reconnect do not execute a second time. A failed submission response can leave
submission acceptance unknown; this profile supplies no idempotency key or
submission discovery. Clients must not automatically retry it or relabel a new
execution as recovery of that attempt.

## Query, cancellation and release

`POST /api/workbench/query`, `/api/workbench/cancel` and
`/api/workbench/release` share this exact body:

```json
{
  "contractVersion": "0.2.0-draft.1",
  "identity": {
    "hostId": "host", "sessionId": "session", "providerId": "scheme",
    "executionId": "execution", "snapshotId": "snapshot"
  }
}
```

The authenticated session and every identity field must match retained owner
state. An unknown or explicitly released execution returns 404. Another host, provider
or snapshot cannot borrow a matching execution ID. A changed session rejects rather
than opening an old snapshot under new authority.

Query and cancellation return HTTP 200 and a raw existing executions receipt, without
a wrapper or another version field. Every receipt follows the existing binding,
sequence, monotonic acknowledgement, immutable terminal and ordered outcome
rules. Query does not increase sequence just because it was polled. Terminal
outcomes contain exactly the one call ID `workbench` and must be validated against
the submitted public manifest. `Result.Err` is returned data. SDK model errors,
primary failures, cancellation and separate cleanup evidence remain distinct.

Cancellation acknowledges the request immediately with the owner receipt; that
receipt does not claim execution has terminated. Repeated acknowledgement does
not invent a new revision. The host then terminates its isolated execution worker
and completes cleanup before publishing cancelled or failed terminal evidence.
An execution result already committed by the owner may win the race and remain
returned data after acknowledgement. Cancelling a terminal execution returns its
retained immutable terminal. Missing negotiated cancellation returns 404.

Release is explicit terminal retention cleanup. Successful release returns HTTP
200 and exactly `{"released":true}`. Release before terminal returns 409 and
cannot stop work or discard evidence. Hosts may impose a bounded retained-execution
capacity, rejecting new submissions with 409 when full. They must not silently
evict another execution or overwrite retained evidence to make room. Clients need not
release a execution to inspect its final receipt, but should release terminal executions they
no longer need. This draft does not promise retention after owner restart.

## Disconnect and bounded failures

HTTP failure, timeout, browser reload and lost transport leave the last validated
receipt intact. They never create cancelled or failed terminal evidence. To
reconcile an existing execution, obtain a newly authenticated descriptor and compare
the exact previous host, session, provider, draft and operation set. Reconnect
then permits query of the existing immutable identity. A successful same-session
query uses the existing stale, replay and advance rules. Reconnect never submits
again. An offer mismatch leaves the old receipt disconnected and requires a
separate explicitly supported recovery contract.

Every raw host request and response frame is at most 1,048,576 bytes of UTF-8,
measured before JSON parsing or response publication. The gateway must stop
reading oversized bodies and must bound upstream authentication responses too.
Reject invalid UTF-8, multiple JSON values, duplicate object members at every
depth, unknown members and unknown contract versions. Decode nested model JSON
and JSON argument source with duplicate-member rejection as well. Raw HTTP body
limits remain necessary even when a JSON Schema string length check passes.
Parsers and decoders must impose their depth and aggregate budgets before
unbounded recursive allocation. A response that cannot fit the frame budget
must not publish a truncated receipt or a successful incomplete outcome.

Non-2xx errors have exactly this shape:

```json
{"error":{"code":"workbench.invalid_request","message":"Invalid request"}}
```

The code contains 1 to 128 UTF-16 units; message contains 1 to 512. Errors must
not echo model or argument source, launch tokens, cookies, authentication
headers, provider stderr or stack traces. Hosts return bounded explanatory text;
clients must not treat an error message as executable content or terminal execution
evidence. The following statuses define the transport categories:

| HTTP status | Category |
| --- | --- |
| 400 | Invalid shape, unsupported version, source decoding or validation failure. |
| 401 | Connected v1 cookie authentication failed. |
| 403 | Origin, Host or cross-site request rejected. |
| 404 | Disabled extension/operation or unknown/released execution. |
| 409 | Invalid transition, changed session or exhausted retained-execution capacity. |
| 413 | Request/frame or validation budget exceeded. |
| 503 | Required upstream authentication or execution service unavailable. |

An HTTP error after submission is transport evidence only. The owner may still
hold a running or terminal execution. The client must query after exact same-session
reconciliation rather than synthesizing a terminal outcome.

## Structural fixtures and implementation evidence

The six closed schemas reference the existing executions offer, identity and receipt
schemas, which in turn reference frozen terminal and value schemas. Run
`mise run workbench:schema-check` for formatting, lint, metaschema and the
independently authored positive/negative fixtures. Historical Workbench schema
and MCK paths remain unchanged. No additional compatibility runner is introduced.

Schemas establish parsed structural shape. They do not establish authentication,
raw-byte budgets, duplicate JSON members, UTF-16 identity limits, session and
cross-field identity equality, valid IR, source decoding, provider support,
execution claims, cancellation races or worker cleanup. Fixtures deliberately
include structurally valid opaque source and mismatched identities to expose
those runtime obligations. Host acceptance tests must exercise the real v1
launch/session flow and isolated execution rather than fake-cookie behavior.

This first profile supports an opt-in HTTP gateway and in-memory same-session
reconciliation. Durable recovery, native-provider IPC, generated browser
execution, metadata trust grants and execution transfer between sessions remain
separate work. Publication of this draft alone does not claim those capabilities.
