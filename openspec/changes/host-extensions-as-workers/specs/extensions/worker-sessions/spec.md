# Spec Delta

## Purpose

Defines the MEP session between the MoonBit CLI's extension host and a worker of any kind: lifecycle, negotiation,
claim checks, request and result checks, limits and failure classes, and the probe and activation operations that
extension acquisition uses.

## ADDED Requirements

### Requirement: One session layer for every worker kind
The host SHALL run the same session logic for every worker kind (process, WASM in a native worker runtime, Node
worker thread, browser Web Worker). Workers SHALL exchange whole MEP messages with the host through a channel. A
worker kind SHALL NOT change which messages are sent, which checks apply, or how a result is classified.

#### Scenario: Same guest, two worker kinds
- **WHEN** the MoonBit guest compiles the same source once as a native process worker and once as a WASM worker
- **THEN** the host sends the same message sequence and returns the same result, diagnostics and failure classes

#### Scenario: Transport fault
- **WHEN** a channel reports that the worker closed, sent a malformed frame or exceeded a frame limit
- **THEN** the session fails with `extension.incomplete_session` or `extension.frame_invalid` and the host stops the worker

### Requirement: Interactive session order
The host SHALL send one request at a time and read its response before the next message. An operation session SHALL
be `initialize`, `initialized`, the operation, `shutdown`, then `exit`. A probe SHALL be `morphir.extension.describe`
then `exit`. A worker that stops before the `shutdown` response SHALL fail the session.

#### Scenario: Early exit
- **WHEN** the worker exits after `initialize` but before it answers the operation
- **THEN** the session fails with `extension.incomplete_session` and no output is published

#### Scenario: Failed initialization stops early
- **WHEN** `initialize` returns a JSON-RPC error
- **THEN** the host sends `exit`, sends no operation and reports the guest's error code and message

### Requirement: Response checks
Each response SHALL carry the ID of the pending request and exactly one of `result` or `error`. A response with
another ID, an unsolicited response, or a second response SHALL fail the session. The host SHALL check a message's
declared size against its limit before it allocates or parses the body.

#### Scenario: Wrong ID
- **WHEN** the worker answers request 3 with ID 4
- **THEN** the session fails with `extension.unexpected_response` and the host stops the worker

#### Scenario: Oversized response
- **WHEN** a response frame declares more bytes than the response limit
- **THEN** the session fails with `extension.response_limit` before the body is read

### Requirement: Protocol lines
The host SHALL offer MEP `0.1` for `morphir.frontend.compile` and `morphir.backend.generate`, and MEP
`0.2.0-draft.1` for `morphir.frontend.compileModel` and `morphir.backend.generateModel`. Negotiating `0.1` SHALL
NOT enable model methods. A worker that selects a version the host did not offer SHALL fail initialization.

#### Scenario: Legacy guest
- **WHEN** the Python or Elm guest initializes with MEP `0.1`
- **THEN** the host calls the legacy compile or generate method and never a model method

#### Scenario: Version the host did not offer
- **WHEN** a worker answers `initialize` with a protocol version outside the offer
- **THEN** the session is refused with `extension.protocol_unavailable` before any operation

### Requirement: Model tuple negotiation
For model methods the host SHALL offer in `initialize` every five-part tuple (operation, profile, codec, envelope
version, IR version) that it supports for the operation, in its order of preference, with no wire field for the
default. The session SHALL use the first agreed tuple. Only an empty agreement SHALL be
`extension.tuple_unavailable`. Effective model limits SHALL be the smaller of the host's and the worker's limits.

#### Scenario: Worker without the default tuple
- **WHEN** the host offers the compile tuples `morphir-model` with `ion-binary`, then `morphir-ir` with
  `morphir-json`, and the worker supports only the JSON tuple
- **THEN** the worker agrees on the JSON tuple, the session uses it, and no error is reported

#### Scenario: Worker that supports every offered tuple
- **WHEN** the host offers the Ion tuple, then the JSON tuple, and the worker supports both
- **THEN** the worker returns both tuples in the host's order and the session uses the Ion tuple

#### Scenario: No offered tuple supported
- **WHEN** the worker supports no tuple that the host offers for the operation
- **THEN** the session is refused with `extension.tuple_unavailable` and no operation is sent

#### Scenario: Smaller worker limit
- **WHEN** the worker declares a smaller decoded-byte limit than the host's 2 MiB
- **THEN** the request is checked against the worker's limit before it is sent

### Requirement: Required model tuple
When the caller requires one model tuple, for example because the user gives `--model-format`, the host SHALL offer
only that tuple and SHALL NOT use another tuple. A worker that does not support it SHALL give an empty agreement,
which is `extension.tuple_unavailable`.

#### Scenario: Required tuple not supported
- **WHEN** the user gives `--model-format json`, so the host offers only `morphir-ir` with `morphir-json`, and the
  worker supports only Ion
- **THEN** the session is refused with `extension.tuple_unavailable` and no operation is sent

### Requirement: Agreement follows the offer
The worker SHALL return the intersection of its own support with the offer, in the host's order. An answer that
holds a tuple that the host did not offer, or that does not keep the host's order, SHALL be refused with
`extension.agreement_mismatch` before any operation.

#### Scenario: Agreement out of the host's order
- **WHEN** the host offers the Ion tuple, then the JSON tuple, and the worker returns the JSON tuple before the Ion
  tuple
- **THEN** activation fails with `extension.agreement_mismatch`, sends `shutdown` and `exit`, and sends no operation

#### Scenario: Agreement with a tuple that was not offered
- **WHEN** the user gives `--model-format json` and the worker answers with the Ion tuple
- **THEN** activation fails with `extension.agreement_mismatch` and sends no operation

### Requirement: Limits
The host SHALL enforce a 4 MiB framed request, a 16 MiB response, model payloads of 2 MiB decoded and 2,796,204
encoded bytes, and the Extism profile limits for MEP `0.1` WASM guests. It SHALL negotiate depth 128 and 100,000
nodes, which the party that decodes a model enforces. The report SHALL state the limits that applied.

#### Scenario: Request too large
- **WHEN** a compile request encodes to more than 4 MiB
- **THEN** the command is refused with `extension.request_limit` and no worker starts

#### Scenario: Declared size does not match the payload
- **WHEN** a model payload declares a decoded length that differs from the length of its decoded content
- **THEN** the request is refused with `extension.request_limit` before it is sent

### Requirement: Describe probe
The host SHALL provide a probe that starts a worker from a worker specification, sends `describe` and `exit`,
returns the extension's identity, version and claims, and stops the worker. A probe result SHALL NOT grant
execution authority and SHALL NOT be cached by the host.

#### Scenario: Probe a staged artifact
- **WHEN** acquisition probes a verified artifact in a staging directory
- **THEN** it receives the extension ID, version and claims, and the worker and its private directory are gone

#### Scenario: Probe of a guest that does not describe
- **WHEN** the worker answers `describe` with an error or exits
- **THEN** the probe fails with `extension.describe_failed` and returns no claims

### Requirement: Activation against recorded claims
The host SHALL provide activation that starts a worker from a worker specification and expected claims, initializes
it, and, before any operation, compares the stable claims of the offered protocol line with the record. Model
transport is negotiated, not compared: the worker SHALL return offered tuples in the host's order, as "Agreement
follows the offer" states, and limits no larger than offered.

#### Scenario: Claims match
- **WHEN** an installed extension initializes with the identity and capabilities recorded at install
- **THEN** activation returns a session that accepts compile or generate calls

#### Scenario: Claims drift
- **WHEN** the worker reports a different version or drops a capability that was recorded
- **THEN** activation fails with `extension.claims_mismatch`, sends `shutdown` and `exit`, and sends no operation

#### Scenario: Negotiated model transport is not drift
- **WHEN** a guest that described four model tuples answers `initialize` with only the offered tuples that it
  supports and smaller limits
- **THEN** activation succeeds and the session uses the first agreed tuple and the smaller limits

### Requirement: Session calls
An activated session SHALL accept compile and generate calls that match the negotiated protocol line and the
worker's capabilities, and SHALL refuse others without sending them. Closing a session SHALL send `shutdown` and
`exit` and SHALL report how the worker stopped.

#### Scenario: Unsupported call
- **WHEN** a caller asks a frontend-only session to generate
- **THEN** the call is refused with `extension.capability_unavailable` and the worker receives nothing

### Requirement: Outcome classes
The host SHALL classify every session as completed, unsuccessful (`success: false`), failed (protocol, transport or
worker fault), refused (checks before an operation), deadline or cancelled, and SHALL keep the guest's diagnostics
and stderr tail in each class.

#### Scenario: Source errors
- **WHEN** the guest answers compile with `success: false` and diagnostics
- **THEN** the outcome is unsuccessful and every diagnostic keeps its code, severity, location and message

### Requirement: Deadlines and cancellation
Every session SHALL have a deadline, 60,000 ms by default and at most 594,000 ms. When the deadline passes or the
caller cancels, the host SHALL stop the worker without waiting for its reply. The host SHALL NOT send
`$/cancelRequest` and SHALL report that wire cancellation was not used.

#### Scenario: Deadline
- **WHEN** a worker does not answer before the session deadline
- **THEN** the outcome is deadline, the worker is stopped and the report says `wireCancellation: false`

#### Scenario: Caller cancels
- **WHEN** the CLI receives SIGINT or its host stop token is triggered during an operation
- **THEN** the outcome is cancelled and the worker is stopped before the call returns

### Requirement: Worker specification
The host SHALL start workers only from a typed worker specification: an artifact location with its SHA-256 and a
runtime that is either a process (platform and argument array) or WASM (an optional declared ABI). A
specification that combines fields of both runtimes, or has no digest, SHALL be refused.

#### Scenario: Specification from an installed catalog
- **WHEN** acquisition passes the stored artifact and its recorded process runtime
- **THEN** the host starts that artifact with the recorded arguments, unchanged

#### Scenario: Platform mismatch
- **WHEN** a process specification names a platform the host cannot run
- **THEN** the host refuses it with `extension.platform_mismatch` and starts nothing

### Requirement: Host worker support
The host SHALL report which runtimes it can start: process and WASM on native and Node, and WASM only in a browser.
A request for a runtime the host cannot start SHALL be refused with `extension.runtime_unavailable`.

#### Scenario: Browser host and a process artifact
- **WHEN** a browser host is asked to start a process worker
- **THEN** it refuses with `extension.runtime_unavailable` and reports that it supports WASM workers
