$version: "2"

// Model validation, MEP 0.2.0-draft.1. See model-transport.smithy for the
// model envelope, and mep.smithy for the scope and the meaning of
// `GAP smithy-` comments.
namespace morphir.mep

/// What a validator can check. `irVersions` lists the semantic IR versions
/// that the validator reads. A `validateModel` tuple authorizes the method,
/// and its `irVersion` must also be in `irVersions`.
structure ValidatorCapability {
    @required
    irVersions: StringList
}

/// Parameters of `morphir.validator.validateModel`. The tuple of `model` is
/// the operation `morphir.validator.validateModel` with the `profile`,
/// `payload.codec`, `envelopeVersion` and `irVersion` of the envelope. It
/// must be an admitted session tuple. `options` belongs to the extension,
/// and is read as empty when absent.
// GAP smithy-2qe.34.24: nothing checks that the tuple of `model` is an
// admitted session tuple, or that its `irVersion` is in
// `validator.irVersions`.
structure ValidateModelRequest {
    @required
    model: MorphirModel

    options: JsonObject = {}
}

/// Result of `morphir.validator.validateModel`. There is no success flag:
/// the host decides the outcome from the severities. A validator that
/// cannot run answers with a JSON-RPC error, not with a result.
structure ValidateModelResult {
    @required
    diagnostics: DiagnosticList
}
