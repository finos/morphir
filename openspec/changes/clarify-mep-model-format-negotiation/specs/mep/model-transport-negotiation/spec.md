# Spec Delta

## Purpose

Defines how a MEP host and extension agree on the model transport tuple for each
model operation, which agreed tuple the host uses, and when the host converts a
model for generation instead of refusing it.

## ADDED Requirements

### Requirement: Host offer order is preference order
The host SHALL list in `InitializeParams.modelTransport` every model transport
tuple that it supports for each model operation, in its preference order. The
first offered tuple for an operation SHALL be the host's default for that
operation. The protocol SHALL NOT add a wire member to name the default.

#### Scenario: Host prefers Ion and also supports JSON
- **WHEN** a host supports `compileModel` with `ion-binary` and `morphir-json` and prefers Ion
- **THEN** its offer lists the `ion-binary` tuple before the `morphir-json` tuple for `compileModel`
- **AND** the `ion-binary` tuple is the host's default for `compileModel`

#### Scenario: Tuples for different operations interleave
- **WHEN** the offer lists a `generateModel` tuple between two `compileModel` tuples
- **THEN** the default for `compileModel` is the first `compileModel` tuple in the offer

### Requirement: Extension keeps the host order
The extension SHALL select as its session `modelTransport` tuples the
intersection of its own support with the host offer, and SHALL keep the order of
the host offer. The extension SHALL NOT reorder tuples to show its own
preference.

#### Scenario: Extension prefers a later host tuple
- **WHEN** the host offers `[compileModel/ion-binary, compileModel/morphir-json]` and the extension supports both but prefers JSON
- **THEN** the session support is `[compileModel/ion-binary, compileModel/morphir-json]`

### Requirement: Host uses the first agreed tuple
For each model operation, the host SHALL use the first tuple in its offer for
that operation that is also in the session support.

#### Scenario: Both peers support the default
- **WHEN** the session support is `[compileModel/ion-binary, compileModel/morphir-json]`
- **THEN** the host sends `compileModel` requests with the `ion-binary` output tuple

### Requirement: Required format is offered alone
When the host requires one format for an operation, for example because the user
gave an explicit model format, the host SHALL offer only that tuple for the
operation.

#### Scenario: User requires Ion
- **WHEN** the user gives an explicit model format of Ion for compilation
- **THEN** the host offer contains only the `compileModel/ion-binary` tuple for `compileModel`

### Requirement: Only an empty agreement is a negotiation failure
When the agreement for a requested operation is empty, the host SHALL refuse the
operation, SHALL send no request for it, and SHALL report
`extension.tuple_unavailable`. This is a host outcome code, not a JSON-RPC error
number. A non-empty agreement SHALL NOT be a negotiation failure.

#### Scenario: Required format with no overlap
- **WHEN** the host offers only `compileModel/ion-binary` and the extension supports only `compileModel/morphir-json`
- **THEN** the session support for `compileModel` is empty
- **AND** the host reports `extension.tuple_unavailable` and sends no `compileModel` request

#### Scenario: Extension does not support the default
- **WHEN** the host does not require a format, offers `[compileModel/ion-binary, compileModel/morphir-json]`, and the extension supports only `compileModel/morphir-json`
- **THEN** the session support is `[compileModel/morphir-json]`
- **AND** the host compiles with the `morphir-json` tuple and reports no error

### Requirement: Host converts a model for generation
For `morphir.backend.generateModel`, when the host has a model in a tuple that
the session does not agree and the host can convert the model to an agreed
tuple, the host SHALL convert the model and send the converted model with that
agreed tuple as `input`. This SHALL NOT be an error. When the host cannot
convert the model to an agreed tuple, it SHALL send no request and SHALL report
`extension.tuple_unavailable`.

#### Scenario: Host converts Ion to JSON for a JSON-only backend
- **WHEN** the host has a `morphir-model/ion-binary` model and the session agrees only `generateModel/morphir-ir/morphir-json`, and the host can convert the model without loss
- **THEN** the host sends a `generateModel` request with the converted JSON model and the JSON `input` tuple

#### Scenario: Host has no conversion
- **WHEN** the host has a model in a tuple that the session does not agree and the host cannot convert it to an agreed tuple
- **THEN** the host sends no `generateModel` request and reports `extension.tuple_unavailable`

#### Scenario: Conversion happens before dispatch
- **WHEN** an extension refuses a `generateModel` request at admission
- **THEN** the host does not convert the model and resend the request in a different tuple

### Requirement: Host prefers a lossless conversion
When the host can convert a model for generation to more than one agreed tuple,
it SHALL prefer the first agreed tuple in host order to which it can convert the
model without loss. Only when the host can convert the model to no agreed tuple
without loss SHALL it select the first agreed tuple in host order to which it
can convert, and then the loss rules apply.

#### Scenario: Several agreed tuples are convertible without loss
- **WHEN** the host can convert the model without loss to two agreed `generateModel` tuples
- **THEN** the host converts the model to the agreed tuple that comes first in its offer

#### Scenario: First convertible tuple is lossy and a later tuple is lossless
- **WHEN** the session agrees `generateModel` tuples `T1` and then `T2` in host order, and the host can convert the model to `T1` only with loss and to `T2` without loss
- **THEN** the host converts the model to `T2` and sends the `generateModel` request with `T2` as `input`
- **AND** the host needs no permission from the user and reports no dropped data

#### Scenario: Every convertible tuple is lossy
- **WHEN** the session agrees `generateModel` tuples `T1` and then `T2` in host order, and the host can convert the model to both only with loss
- **THEN** the host selects `T1`
- **AND** the host refuses the conversion with its lossy-conversion error unless the user explicitly allows loss for that operation

### Requirement: Host refuses a lossy conversion
A conversion SHALL be lossy when the converted model cannot carry all content of
the original model, for example an enrichment, an annotation, precision,
decimal scale or provenance. When the host can convert the model to no agreed
tuple without loss, and unless the user explicitly allows loss, the host
SHALL refuse the lossy conversion with its lossy-conversion error, SHALL send no
request, and SHALL publish no artifact. This refusal SHALL NOT be
`extension.tuple_unavailable`.

#### Scenario: Lossy conversion without permission
- **WHEN** the only agreed tuple to which the host can convert would drop provenance and the user did not allow loss
- **THEN** the host reports its lossy-conversion error, for example `data.lossy_conversion` with exit code 2 in the MoonBit CLI, and not `extension.tuple_unavailable`
- **AND** the host sends no `generateModel` request and publishes no artifact
- **AND** the error message tells the user how to allow the loss, for example `--allow-model-loss` in the MoonBit CLI

#### Scenario: JSON to Ion conversion is lossless
- **WHEN** the host has a `morphir-ir/morphir-json` model and the session agrees only `generateModel/morphir-model/ion-binary`
- **THEN** the conversion drops no data and needs no permission from the user

### Requirement: User explicitly allows loss for one operation
The host SHALL do a lossy conversion only when the user explicitly allows loss
for that one operation. When the host drops data, it SHALL report each kind of
data that it dropped.

#### Scenario: Lossy conversion with permission
- **WHEN** a conversion to the agreed tuple would drop provenance and annotations and the user explicitly allowed loss for this operation
- **THEN** the host converts the model and sends the `generateModel` request
- **AND** the host warns the user that it dropped provenance and annotations, and lists them as dropped data in the conversion report

#### Scenario: Permission does not carry over
- **WHEN** the user allowed loss for one generation and then starts a second generation without permission
- **THEN** the host refuses a lossy conversion in the second generation

### Requirement: Converted model is a new payload with the same model identity
A converted model SHALL be a new model payload with its own
`decodedByteLength`, `sha256` and `revision`, and SHALL keep the `modelId` of
the original model. The host SHALL derive the new `revision` deterministically
from the SHA-256 digest of the converted payload bytes. The host SHALL keep the
original model bytes. Required guarantees and evidence that apply to the
original payload SHALL NOT carry over to the converted model automatically.

#### Scenario: Converted model has its own identity values
- **WHEN** the host converts a model for generation
- **THEN** the converted model has the same `modelId` as the original, a `revision` different from the original, and a `sha256` and `decodedByteLength` that match the converted bytes

#### Scenario: Revision is deterministic
- **WHEN** the host converts the same original model to the same tuple two times
- **THEN** both converted models have the same `revision`, for example `sha256:<64 lowercase hexadecimal digits>` in the MoonBit CLI

#### Scenario: Evidence for the original does not carry over
- **WHEN** the original model has evidence that binds its revision
- **THEN** the host does not send that evidence as evidence for the converted model
- **AND** the host sends evidence for the converted model only when it binds the new revision and its checker or trust policy accepts it

### Requirement: Host reports every conversion
For each conversion, lossless or lossy, the host SHALL report the conversion to
the user as a diagnostic or notification. The report SHALL contain the original
and converted tuples, the original and converted revisions and payload SHA-256
digests, and the list of dropped data, which is empty unless the user explicitly
allowed loss. The host SHALL NOT add a file to the output of the extension for
this report. The form of the report SHALL be host-defined.

#### Scenario: Lossless conversion is reported
- **WHEN** the host converts a model without loss
- **THEN** the host reports the conversion with both tuples, both revisions, both payload digests and an empty dropped list
- **AND** in the MoonBit CLI, for example, the report is the diagnostic `extension.model_converted` with severity `info` and the data `from` and `to`, each with `profile`, `codec`, `revision` and `payloadSha256`, and `dropped`

#### Scenario: Report is in the diagnostics and on stderr
- **WHEN** the MoonBit CLI converts a model for `morphir generate`
- **THEN** the `extension.model_converted` diagnostic is in the command diagnostics, and in the JSON report when the user gives `--json`
- **AND** the CLI writes one human-readable line for it on stderr

#### Scenario: No output file is added
- **WHEN** the host converts a model for generation
- **THEN** the host adds no file for the conversion to the output of the extension, and the published artifacts are only the artifacts of the extension
