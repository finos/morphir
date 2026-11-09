# Spec Delta

## Purpose

Defines the model-tier validator method `morphir.validator.validateModel` of
MEP `0.2.0-draft.1`: its request, result and capability, when a host offers
its tuples, and when a host converts a model for validation.

## ADDED Requirements

### Requirement: validateModel needs the session, the capability and a tuple
An extension SHALL accept `morphir.validator.validateModel` only when the
session state is `ready`, the session protocol version is `0.2.0-draft.1`,
`extension.types` contains `validator`, the session `capabilities.validator` is
present, and the session `capabilities.modelTransport.tuples` contains a tuple
with the operation `morphir.validator.validateModel`. Otherwise it SHALL answer
with `-32013`, or with `-32014` before initialization and after shutdown.

#### Scenario: Generate support does not authorize validation
- **WHEN** the session agrees only `generateModel` tuples and the host sends `validateModel`
- **THEN** the extension answers with `-32013`

#### Scenario: Legacy session
- **WHEN** the session protocol version is `0.1` and the host sends `validateModel`
- **THEN** the extension answers with `-32013`

### Requirement: The request carries the model, its input tuple and options
`ValidateModelRequest` SHALL carry `model`, `input` and `options`. `input`
SHALL be an admitted validateModel tuple of the session. The `profile`,
`payload.codec`, `envelopeVersion` and `irVersion` of `model` SHALL match
`input`, and `input.irVersion` SHALL be in `validator.irVersions`. An absent
`options` SHALL be read as empty. The extension owns the options and SHALL
refuse an option that it does not know with `-32602`. The request SHALL have
no context digest and no required guarantees.

#### Scenario: Input and envelope disagree
- **WHEN** `input` is the agreed `morphir-ir`/`morphir-json` tuple and the model envelope is `morphir-model`/`ion-binary`
- **THEN** the extension refuses the request with `-32602`

#### Scenario: IR version that the validator does not read
- **WHEN** `input.irVersion` is not in `validator.irVersions`
- **THEN** the extension answers with `-32013`

### Requirement: The result is a list of diagnostics
`ValidateModelResult` SHALL have a required `diagnostics` list, which can be
empty, and no success flag. A model that breaks a rule SHALL give diagnostics
in a result. A validator that cannot run SHALL answer with `-32003`, not with a
result. The host decides the outcome from the severities.

#### Scenario: A warning
- **WHEN** the validator finds an empty package
- **THEN** the result has one diagnostic with the severity `warning`

#### Scenario: The validator cannot run
- **WHEN** the validator has an internal failure after admission
- **THEN** the extension answers with `-32003` and the session stays `ready`

### Requirement: The validator capability lists IR versions and rules
`ValidatorCapability` SHALL have `irVersions` and `rules`. `rules` SHALL be left
out when empty and read as empty when absent. An empty list SHALL mean that the
validator does not list its rules. `validator` SHALL be a reserved name in
`ExtensionCapabilities`.

#### Scenario: Rules not listed
- **WHEN** `rules` is absent
- **THEN** the host reads an empty list, which means that the validator does not list its rules

### Requirement: A rule has an IRI and a diagnostic code
Each `ValidatorRule` SHALL have an `id` that is an absolute IRI (RFC 3987) and a
nonempty `code`. In one list, each `id` and each `code` SHALL be unique. Peers
SHALL compare an `id` as a plain string, with no normalization, and a host SHALL
NOT have to dereference it. A diagnostic whose `code` is the `code` of a listed
rule comes from that rule.

#### Scenario: Map a diagnostic to its rule IRI
- **WHEN** the validator lists the rule `https://example.org/morphir/rules/empty-package` with the code `example.empty-package`, and a result has a diagnostic with that code
- **THEN** the host maps the diagnostic to that rule IRI

### Requirement: A host offers validateModel tuples only to a validator
A host SHALL offer `morphir.validator.validateModel` tuples only to an
extension whose `morphir.extension.describe` result or recorded claims list at
least one validateModel tuple in `capabilities.modelTransport`. A host that has
neither SHALL offer no validateModel tuple. This rule SHALL NOT change the draft version
`0.2.0-draft.1`.

#### Scenario: Existing frontend
- **WHEN** a host starts a frontend whose claims name only `compileModel` tuples
- **THEN** the host offer contains no `validateModel` tuple

### Requirement: The host converts a model for validation without loss
When the host has the model in a tuple that the session does not agree for
`validateModel`, the host SHALL convert it to the first agreed validateModel
tuple in host order that it can reach without loss, and SHALL send the
converted model with that tuple as `input`. The identity, evidence, conversion
report and before-dispatch rules of host conversion for generation SHALL apply.
Only when the host cannot convert SHALL it report `extension.tuple_unavailable`.

#### Scenario: Lossless conversion
- **WHEN** the host has a `morphir-ir` JSON model and the session agrees only the `morphir-model` Ion tuple for `validateModel`
- **THEN** the host sends the converted Ion model with the same `modelId` and a new revision, and reports the conversion

### Requirement: The host never sends a lossy conversion for validation
The host SHALL NOT send a lossy conversion of a model for validation, even when
the user allows loss. When only a lossy conversion is possible, the host SHALL
refuse with its lossy-conversion error, not `extension.tuple_unavailable`, and
SHALL send no request.

#### Scenario: Loss allowed for generation does not apply
- **WHEN** the only agreed validateModel tuple loses data of the model and the user gave `--allow-model-loss`
- **THEN** the host refuses with its lossy-conversion error and sends no request
