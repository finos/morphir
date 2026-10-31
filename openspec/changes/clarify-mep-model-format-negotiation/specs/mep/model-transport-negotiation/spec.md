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

### Requirement: Host conversion follows the host loss rules
A host conversion for generation SHALL follow the host's own loss rules. The
host SHALL refuse a conversion that would drop source or naming provenance,
SHALL report its lossy-conversion error, and SHALL send no request.

#### Scenario: Conversion would drop provenance
- **WHEN** a conversion to the agreed tuple would drop source or naming provenance
- **THEN** the host reports its lossy-conversion error, for example `data.lossy_conversion` in the MoonBit CLI
- **AND** the host sends no `generateModel` request

### Requirement: Converted model is a new payload
A converted model SHALL be a new model payload with its own
`decodedByteLength`, `sha256` and `revision`. The host SHALL keep the original
model bytes. Required guarantees and evidence that apply to the original
payload SHALL NOT carry over to the converted model automatically.

#### Scenario: Converted model has its own identity values
- **WHEN** the host converts a model for generation
- **THEN** the converted model has a `revision` different from the original and a `sha256` and `decodedByteLength` that match the converted bytes

#### Scenario: Evidence for the original does not carry over
- **WHEN** the original model has evidence that binds its revision
- **THEN** the host does not send that evidence as evidence for the converted model
- **AND** the host sends evidence for the converted model only when it binds the new revision and its checker or trust policy accepts it
