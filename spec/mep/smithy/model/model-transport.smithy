$version: "2"

// Rich model transport, MEP 0.2.0-draft.1. See spec/mep/model-transport.md
// for the normative rules, and mep.smithy for the scope and the meaning of
// `GAP smithy-` comments.
//
// Admission rules are out of scope for a message model: a SHA-256 or length
// that does not agree with the bytes, decoded depth and node limits, evidence
// binding and trust. The model checks the shape and the lexical form of each
// member.
namespace morphir.mep

/// A model operation. These methods require the exact MEP draft
/// 0.2.0-draft.1. Legacy 0.1 never enables them.
enum ModelOperation {
    COMPILE_MODEL = "morphir.frontend.compileModel"
    GENERATE_MODEL = "morphir.backend.generateModel"
}

/// The representation of a complete model document. `ion-binary` uses media
/// type `application/ion`; `morphir-json` uses `application/json` in UTF-8.
enum ModelCodec {
    ION_BINARY = "ion-binary"
    MORPHIR_JSON = "morphir-json"
}

/// The payload layout.
enum ModelLayout {
    SINGLE_DOCUMENT = "single-document"
}

/// A nonempty string.
@length(min: 1)
string NonEmptyString

/// 64 lowercase hexadecimal digits of a SHA-256 digest.
// The length is a separate trait, because a pattern with `{64}` uses most
// of the default validation work budget.
@length(min: 64, max: 64)
@pattern("^[0-9a-f]*$")
string Sha256Hex

/// Canonical padded RFC 4648 base64 with no whitespace.
// GAP smithy-2qe.34.26: a pattern costs work for each UTF-16 unit of the
// value, and a model payload can be up to 2147483647 bytes. A canonical
// base64 pattern exceeds the default work budget of 100,000 units on a
// payload of a few hundred bytes, and the CLI cannot raise the budget. So
// this shape has no pattern.
string Base64Content

/// A positive limit, at most 2147483647. Bindings use u32 with that bound.
@range(min: 1, max: 2147483647)
integer PositiveLimit

list NonEmptyStringList {
    member: NonEmptyString
}

/// One supported combination of all five members. Compare all five
/// exactly. Never form a Cartesian product of separate lists.
/// `envelopeVersion` is the model envelope version, `0.1.0-draft.1`.
/// `irVersion` names the semantic IR version.
structure ModelTransportTuple {
    @required
    operation: ModelOperation

    @required
    profile: NonEmptyString

    @required
    codec: ModelCodec

    @required
    envelopeVersion: String

    @required
    irVersion: String
}

/// Unique complete tuples.
@uniqueItems
list ModelTransportTupleList {
    member: ModelTransportTuple
}

/// Limits that apply before allocation and parsing.
structure ModelTransportLimits {
    @required
    maxEncodedBytes: PositiveLimit

    @required
    maxDecodedBytes: PositiveLimit

    @required
    maxDepth: PositiveLimit

    @required
    maxNodes: PositiveLimit
}

/// An offer or the session support. Tuples are complete and unique. An
/// empty list supports no model operation. `guarantees` lists ids that the
/// peer can interpret, not guarantees that it has established.
// GAP smithy-2qe.34.24: nothing checks that session tuples and limits
// do not exceed the offer of each peer.
structure ModelTransportSupport {
    @required
    tuples: ModelTransportTupleList

    @required
    limits: ModelTransportLimits

    guarantees: NonEmptyStringList = []
}

/// Opaque single-document bytes, with a length and a digest.
structure ModelPayload {
    @required
    codec: ModelCodec

    @required
    layout: ModelLayout

    @required
    @range(min: 0, max: 2147483647)
    decodedByteLength: Integer

    @required
    sha256: Sha256Hex

    @required
    content: Base64Content
}

/// A required guarantee for an exact scope. A scope is a model or node
/// identity, not a filesystem path.
structure ModelGuaranteeRequirement {
    @required
    guarantee: NonEmptyString

    @required
    scope: NonEmptyString
}

list ModelGuaranteeRequirementList {
    member: ModelGuaranteeRequirement
}

/// A claim, not authority. The receiver admits it under its own checking
/// and trust policy. `producer` is attribution, not authentication.
structure ModelGuaranteeEvidence {
    @required
    guarantee: NonEmptyString

    @required
    modelId: NonEmptyString

    @required
    modelRevision: NonEmptyString

    @required
    contextDigest: Sha256Hex

    @required
    scope: NonEmptyString

    @required
    producer: NonEmptyString

    @required
    evidence: ModelPayload
}

list ModelGuaranteeEvidenceList {
    member: ModelGuaranteeEvidence
}

/// A Morphir model envelope. `revision` is a logical immutable revision, not
/// a transport hash.
///
/// `critical` lists exact registered member paths. A reader refuses a path
/// that it does not know. It is left out when empty.
// GAP smithy-2qe.34.17: the validator cannot check the `critical`
// rule.
structure MorphirModel {
    @required
    envelopeVersion: String

    @required
    modelId: NonEmptyString

    @required
    revision: NonEmptyString

    @required
    irVersion: String

    @required
    profile: NonEmptyString

    @required
    payload: ModelPayload

    evidence: ModelGuaranteeEvidenceList = []

    critical: StringList = []
}

/// A complete dependency model. Its format must agree with the selected
/// tuple of the compile operation.
structure CompileModelDependency {
    @required
    packageName: String

    @required
    model: MorphirModel
}

list CompileModelDependencyList {
    member: CompileModelDependency
}

/// Parameters of `morphir.frontend.compileModel`. `output` selects one
/// admitted compileModel tuple. `options.irVersion` must equal its
/// `irVersion`.
// GAP smithy-2qe.34.24: nothing checks that `output` is an admitted
// session tuple, or that `options.irVersion` equals `output.irVersion`.
structure CompileModelRequest {
    @required
    languageId: String

    @required
    sources: SourceSet

    @required
    package: CompilePackage

    dependencies: CompileModelDependencyList = []

    @required
    options: CompileOptions

    @required
    contextDigest: Sha256Hex

    @required
    output: ModelTransportTuple
}

/// Result of `morphir.frontend.compileModel`. Success is `success: true`
/// with a required `model`. Failure is `success: false`, and `model` must be
/// absent; even null is refused.
// GAP smithy-2qe.34.21: a Smithy union is tagged by its member
// name, not by the value of `success`. This structure cannot require `model`
// when `success` is true, or forbid it when `success` is false.
structure CompileModelResult {
    @required
    success: Boolean

    model: MorphirModel

    diagnostics: DiagnosticList = []

    modules: StringList = []
}

/// Parameters of `morphir.backend.generateModel`. `input` selects an
/// admitted generateModel tuple. `target` is the exact advertised target.
// GAP smithy-2qe.34.24: nothing checks that `input` is an admitted
// session tuple, or that `model` agrees with it.
structure GenerateModelRequest {
    @required
    model: MorphirModel

    @required
    input: ModelTransportTuple

    @required
    target: String

    @required
    contextDigest: Sha256Hex

    requiredGuarantees: ModelGuaranteeRequirementList = []

    options: JsonObject = {}
}
