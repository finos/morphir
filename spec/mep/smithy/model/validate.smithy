$version: "2"

// Model validation, MEP 0.2.0-draft.1. See model-transport.smithy for the
// model envelope, and mep.smithy for the scope and the meaning of
// `GAP smithy-` comments.
namespace morphir.mep

/// What a validator can check. `irVersions` lists the semantic IR versions
/// that the validator reads. A `validateModel` tuple authorizes the method,
/// and its `irVersion` must also be in `irVersions`.
// GAP smithy-2qe.34.24: nothing checks that each rule `id` and each rule
// `code` is unique in `rules`.
structure ValidatorCapability {
    @required
    irVersions: StringList

    /// The rules that the validator can report. Left out when empty. An
    /// empty list means that the validator does not list its rules.
    rules: ValidatorRuleList = []
}

/// One rule of a validator. `id` is an absolute IRI (RFC 3987) that names
/// the rule, compared as a plain string. The extension owns the IRI. `code`
/// is the `Diagnostic.code` of each diagnostic that the rule reports.
structure ValidatorRule {
    /// The pattern checks only that the IRI has a scheme. The model does not
    /// check the rest of the RFC 3987 syntax.
    @required
    @pattern("^[A-Za-z][A-Za-z0-9+.\\-]*:.*$")
    id: String

    @required
    code: NonEmptyString
}

@uniqueItems
list ValidatorRuleList {
    member: ValidatorRule
}

/// Parameters of `morphir.validator.validateModel`. `input` selects an
/// admitted validateModel tuple, and the profile, codec, envelope version
/// and IR version of `model` must match it. `options` belongs to the
/// extension, and is read as empty when absent. A host never sends a lossy
/// conversion of a model for validation.
// GAP smithy-2qe.34.24: nothing checks that `input` is an admitted session
// tuple, that `model` agrees with it, or that its `irVersion` is in
// `validator.irVersions`.
structure ValidateModelRequest {
    @required
    model: MorphirModel

    @required
    input: ModelTransportTuple

    options: JsonObject = {}
}

/// Result of `morphir.validator.validateModel`. There is no success flag:
/// the host decides the outcome from the severities. A validator that
/// cannot run answers with a JSON-RPC error, not with a result.
structure ValidateModelResult {
    @required
    diagnostics: DiagnosticList
}
