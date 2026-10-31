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

### Requirement: Host converts to the first convertible agreed tuple
When the host can convert a model for generation to more than one agreed tuple,
it SHALL convert to the first agreed tuple in host order to which it can
convert.

#### Scenario: Several agreed tuples are convertible
- **WHEN** the host can convert the model to two agreed `generateModel` tuples
- **THEN** the host converts the model to the agreed tuple that comes first in its offer

### Requirement: Host refuses a lossy conversion
A conversion SHALL be lossy when the converted model cannot carry all content of
the original model, for example an enrichment, an annotation, precision,
decimal scale or provenance. Unless the user explicitly allows loss, the host
SHALL refuse a lossy conversion with its lossy-conversion error, SHALL send no
request, and SHALL publish no artifact. This refusal SHALL NOT be
`extension.tuple_unavailable`.

#### Scenario: Lossy conversion without permission
- **WHEN** a conversion to the agreed tuple would drop provenance and the user did not allow loss
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
- **AND** the host tells the user that it dropped provenance and annotations, and records them in the conversion record

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

### Requirement: Host keeps a conversion record
For each conversion, the host SHALL keep a record that links the converted model
to the original. The record SHALL contain the original and converted tuples,
the original and converted revisions and payload SHA-256 digests, and the list
of dropped data, which is empty for a lossless conversion. The record location
SHALL be reserved for the host. The host SHALL NOT let an extension artifact
overwrite the record.

#### Scenario: Lossless conversion record
- **WHEN** the host converts a model without loss
- **THEN** the host writes a conversion record with both tuples, both revisions, both payload digests and an empty dropped list, for example `mep/conversion.json` in the MoonBit CLI

#### Scenario: Extension artifact at the record location
- **WHEN** the extension returns an artifact at the location of the conversion record
- **THEN** the host refuses the result and does not write the artifact over the record
