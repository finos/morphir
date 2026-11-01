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
- **WHEN** the host offers the compile tuples of IR `4.0.0`, `morphir-model` with `ion-binary`, then `morphir-ir` with
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

### Requirement: Host tuple order
The host's order of preference SHALL be IR `4.0.0`, then IR `3.0.0`, each with `morphir-model` and `ion-binary`, then
with `morphir-ir` and `morphir-json`, all with envelope `0.1.0-draft.1` (bead: morphir-ukvn.5.64.36.23).

#### Scenario: Worker with both IR versions and no requirement
- **WHEN** no requirement narrows the offer and the worker supports JSON tuples at IR `3.0.0` and `4.0.0`
- **THEN** the worker returns the tuples in the host's order and the session uses the JSON tuple of IR `4.0.0`

#### Scenario: Worker with only IR 3.0.0
- **WHEN** no requirement narrows the offer and the worker supports only the JSON tuple of IR `3.0.0`
- **THEN** the session uses that tuple, and no error is reported

### Requirement: Required model tuple
When the caller requires one format, for example because the user gives `--model-format`, the host SHALL offer only
the tuples of that format and SHALL NOT use another tuple. A worker that supports none of them SHALL give an empty
agreement, which is `extension.tuple_unavailable`.

#### Scenario: Required tuple not supported
- **WHEN** the user gives `--model-format json`, so the host offers only `morphir-ir` with `morphir-json`, at IR
  `4.0.0` and `3.0.0`, and the worker supports only Ion
- **THEN** the session is refused with `extension.tuple_unavailable` and no operation is sent

### Requirement: Required IR version
When the caller requires an IR version, for example because the user gives `--ir-version`, the host SHALL offer only
the tuples of that IR version and SHALL NOT use another tuple (bead: morphir-ukvn.5.64.36.23). A full version SHALL
select that exact version. A major-only version SHALL select the highest version of that major in the matching tuples
that the extension claims. A requirement of IR version and a requirement of format SHALL intersect.

#### Scenario: IR 3 selected
- **WHEN** the user gives `--ir-version 3` and the worker claims JSON tuples at IR `3.0.0` and `4.0.0`
- **THEN** the host offers only the Ion and JSON tuples of IR `3.0.0`, the worker agrees on the JSON tuple, and the
  compile request has that tuple as `output` and `options.irVersion` `3.0.0`

#### Scenario: Major version and exact version
- **WHEN** the user gives `--ir-version 3` in one command and `--ir-version 3.0.0` in another, and `3.0.0` is the only
  version of that major that the worker claims
- **THEN** both commands make the same offer and the same request

#### Scenario: IR version and format intersect
- **WHEN** the worker claims Ion at IR `4.0.0` and JSON at IR `3.0.0`, and the user gives `--ir-version 3` with
  `--model-format ion`
- **THEN** the command is refused with `extension.tuple_unavailable`, because no tuple meets both requirements

### Requirement: No tuple at the required IR version
When the claims show no tuple that meets the requirements, the host SHALL refuse with `extension.tuple_unavailable`
before an operation session starts. When the claims show one but the live worker agrees on none, the host SHALL refuse
with `extension.tuple_unavailable` after negotiation and SHALL send no operation (bead: morphir-ukvn.5.64.36.23).

#### Scenario: No tuple at the selected IR version in the claims
- **WHEN** the user gives `--ir-version 3` and the worker claims tuples of IR `4.0.0` only
- **THEN** the command is refused with `extension.tuple_unavailable` and starts no operation session

#### Scenario: No agreement at the selected IR version
- **WHEN** the probed claims hold a tuple of IR `3.0.0`, the user gives `--ir-version 3`, and the live worker agrees
  on no offered tuple
- **THEN** the session is refused with `extension.tuple_unavailable` after negotiation and no operation is sent

### Requirement: Request and result follow the agreed tuple
`options.irVersion`, `contextDigest` and the output checks SHALL follow the agreed tuple, not a constant
(bead: morphir-ukvn.5.64.36.23). A request whose `options.irVersion` differs from the agreed tuple SHALL be refused
without being sent.

#### Scenario: Request of another IR version
- **WHEN** the session agreed a tuple of IR `3.0.0` and a compile request has `options.irVersion` `4.0.0`
- **THEN** the call is refused with `extension.tuple_unavailable` and nothing is sent

#### Scenario: Result of another IR version
- **WHEN** the session agreed a JSON tuple of IR `3.0.0` and the result's envelope or `formatVersion` names another
  IR version
- **THEN** the command fails with `extension.result_invalid` and publishes nothing

### Requirement: Compile protocol line
A guest that claims MEP `0.2.0-draft.1` SHALL compile on the model line, also when it claims MEP `0.1` too. Only a
guest that claims MEP `0.1` and no other offered line SHALL compile on MEP `0.1`. The host SHALL NOT choose MEP `0.1`
because no tuple matches a requirement, because that hides from the user that the requested combination is not
available (bead: morphir-ukvn.5.64.36.23).

#### Scenario: Guest on both lines with no matching tuple
- **WHEN** a guest claims both lines and legacy compile, has no model tuple for the requested IR version, and the
  user gives `--ir-version 3`
- **THEN** the command is refused with `extension.tuple_unavailable`, and no MEP `0.1` session starts

#### Scenario: Guest on both lines with no compile tuple
- **WHEN** a guest claims both lines and legacy compile, and its model tuples are only for `generateModel`
- **THEN** the command is refused with `extension.tuple_unavailable`, and no MEP `0.1` session starts

#### Scenario: Guest on the legacy line only
- **WHEN** a guest claims only MEP `0.1`, also with a model transport in its claims
- **THEN** it compiles with `morphir.frontend.compile` on MEP `0.1`, and `--ir-version` selects from its claimed
  frontend IR versions

### Requirement: Plain IR on the model line
For a guest on the model line, shared code of the host package SHALL wrap plain Morphir IR JSON in a `morphir-ir` and
`morphir-json` envelope around the exact bytes, with a model ID and a revision from their SHA-256, and the host SHALL
send it with `morphir.backend.generateModel` at the tuple of its `formatVersion`. No matching tuple SHALL be
`extension.tuple_unavailable` (bead: morphir-ukvn.5.64.36.23).

#### Scenario: Plain IR at each format version
- **WHEN** a guest on both lines claims the JSON generate tuples of IR `3.0.0` and `4.0.0`, and the user generates from
  a plain IR file whose `formatVersion` is `3` or `4`
- **THEN** the host offers only the tuple of that version and sends the wrapped model with
  `morphir.backend.generateModel`

#### Scenario: Same file, same envelope
- **WHEN** two hosts wrap the same bytes
- **THEN** the envelopes are equal, with `modelId` `urn:morphir:plain-ir:sha256:<digest>` and `revision`
  `sha256:<digest>`, and other bytes give another revision

#### Scenario: Plain IR with no matching tuple
- **WHEN** a guest on both lines claims legacy generate and no generate tuple of the file's format version
- **THEN** the command is refused with `extension.tuple_unavailable`, and no MEP `0.1` session starts

#### Scenario: Plain IR on the legacy line
- **WHEN** a guest claims only MEP `0.1`
- **THEN** the host sends the plain IR to `morphir.backend.generate`, as it is

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

#### Scenario: Agreement at another IR version
- **WHEN** the user gives `--ir-version 3` and the worker answers with a tuple of IR `4.0.0`
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
