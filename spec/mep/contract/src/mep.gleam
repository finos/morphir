//// The Morphir Extension Protocol (MEP) contract.
////
//// This module is the source of truth for the messages a Morphir host and an
//// extension exchange. Labels are snake_case here and lowerCamelCase on the
//// wire, except where a type's documentation says otherwise. See
//// spec/mep/README.md for the versioning rule and the full wire mapping.

import gleam/dict.{type Dict}
import gleam/option.{type Option}

// -- JSON -------------------------------------------------------------------

/// Any JSON value. Used where the protocol carries data the contract does not
/// constrain, such as compiled IR or backend options.
/// On the wire it is the JSON value itself, not a tagged constructor.
pub type Json {
  JsonNull
  JsonBool(value: Bool)
  JsonInt(value: Int)
  JsonFloat(value: Float)
  JsonString(value: String)
  JsonArray(items: List(Json))
  JsonObject(members: Dict(String, Json))
}

// -- Handshake --------------------------------------------------------------

/// What kind of peer introduced itself. Wire values: `cli`, `unspecified`.
/// A peer kind this contract does not know is read as `Unspecified`.
pub type PeerKind {
  Cli
  Unspecified
}

/// A host or an extension, as it introduces itself. Older messages leave
/// `kind` out; an absent kind is read as `Unspecified`.
pub type PeerInfo {
  PeerInfo(kind: PeerKind, name: String, version: String)
}

/// Parameters of `morphir.extension.describe`.
pub type DescribeParams {
  DescribeParams(protocol_versions: List(String))
}

/// Parameters of `morphir.initialize`. Full SemVer protocol versions are used
/// by the model-operation draft; legacy `0.1` remains an explicit exception.
/// `model_transport` (wire `modelTransport`) is left out when absent. Absence
/// means legacy-only, never an implicit offer of model transport. The offer
/// lists every supported tuple in preference order; the first tuple for each
/// operation is the host's default. A host that requires one format offers
/// only that tuple.
pub type InitializeParams {
  InitializeParams(
    protocol_versions: List(String),
    host: PeerInfo,
    model_transport: Option(ModelTransportSupport),
  )
}

/// Result of `morphir.initialize`.
pub type InitializeResult {
  InitializeResult(
    protocol_version: String,
    extension: ExtensionInfo,
    capabilities: ExtensionCapabilities,
  )
}

/// A kind of extension. Wire values: `frontend`, `backend`, `transform`,
/// `validator`, `workspace`.
pub type ExtensionType {
  FrontendExtension
  BackendExtension
  TransformExtension
  ValidatorExtension
  WorkspaceExtension
}

/// Who an extension is. Wire names stay snake_case for this record, so the
/// label `min_sdk_version` is also the wire name. Optional members are left
/// out of the message when absent.
pub type ExtensionInfo {
  ExtensionInfo(
    id: String,
    name: String,
    version: String,
    description: Option(String),
    types: List(ExtensionType),
    author: Option(String),
    homepage: Option(String),
    license: Option(String),
    min_sdk_version: Option(String),
  )
}

// -- Capabilities -----------------------------------------------------------

/// A source language a frontend reads.
pub type LanguageCapability {
  LanguageCapability(id: String, file_extensions: List(String))
}

/// What a frontend can compile. `multi_document` (wire `multiDocument`) is
/// written only when it is true; an absent member is read as false. A
/// frontend without it compiles exactly one document per request.
pub type FrontendCapability {
  FrontendCapability(
    languages: List(LanguageCapability),
    ir_versions: List(String),
    compile: Bool,
    incremental: Bool,
    fragments: Bool,
    multi_document: Bool,
  )
}

/// What a backend can generate.
pub type BackendCapability {
  BackendCapability(
    targets: List(String),
    ir_versions: List(String),
    generate: Bool,
  )
}

/// Workspace discovery support. Each protocol version is a full SemVer
/// string, such as `0.1.0`, for the workspace discovery protocol. These are
/// independent of full SemVer MEP drafts and the legacy `0.1` exception.
pub type WorkspaceCapability {
  WorkspaceCapability(protocol_versions: List(String), discover: Bool)
}

/// What an extension can do.
///
/// Wire rules:
/// - `frontend`, `backend`, `workspace` and `modelTransport` are left out
///   when absent. An absent `modelTransport` means legacy-only.
/// - `modelTransport` before initialization is guest support. In a session
///   it contains only tuples explicitly offered by both peers and limits no
///   larger than either peer's limits. It is not a Cartesian product. The
///   extension keeps the host offer order, and the host uses the first agreed
///   tuple for each operation. Only an empty agreement is a failure.
///   Under the new draft, agreement with static claims permits this narrowing
///   for modelTransport only; legacy capability equality rules are unchanged.
/// - The four flags `streaming`, `incremental`, `cancellation` and
///   `progress` are always written. An absent flag is read as false.
/// - Members of `extra` sit beside the named members on the wire, not under
///   an `extra` key. Unknown members are read into `extra`.
/// - A writer refuses an `extra` key that is one of the reserved names
///   `frontend`, `backend`, `workspace`, `streaming`, `incremental`,
///   `cancellation`, `progress` or `modelTransport`.
pub type ExtensionCapabilities {
  ExtensionCapabilities(
    frontend: Option(FrontendCapability),
    backend: Option(BackendCapability),
    workspace: Option(WorkspaceCapability),
    model_transport: Option(ModelTransportSupport),
    streaming: Bool,
    incremental: Bool,
    cancellation: Bool,
    progress: Bool,
    extra: Dict(String, Json),
  )
}

// -- Claims -----------------------------------------------------------------

/// Requirements a claim set puts on the host. Each `host` entry is one SemVer
/// comparator, such as `>=0.4.0`, not a combined range; all of them must
/// hold. `host` is left out when empty, and an absent `host` is read as
/// empty.
pub type ClaimsRequirements {
  ClaimsRequirements(host: List(String))
}

/// The result of `morphir.extension.describe`: the capabilities an extension
/// claims, without starting a session.
///
/// Wire rules:
/// - `claims_version` (wire `claimsVersion`) is a SemVer string for the
///   claims format, which is versioned apart from MEP. Writers send
///   `0.1.0-draft.2`. Readers accept exactly `0.1.0-draft.1` or
///   `0.1.0-draft.2` and read both as draft.2.
/// - Draft.1 names the member `statementVersion` instead. The member name
///   must match the draft, and a claim set with both names is refused. In a
///   draft.1 `critical` list, `statementVersion` is read as `claimsVersion`,
///   and a draft.1 `critical` list that names `claimsVersion` is refused.
/// - `protocol_versions` (wire `protocolVersions`) are full SemVer strings
///   for the model-operation draft. The frozen legacy `MAJOR.MINOR` value
///   `0.1` remains accepted only for the legacy protocol.
/// - Unknown top-level members are dropped when read.
/// - `capabilities` is open: members this contract does not name are kept
///   when read and written. The named members inside it, such as
///   `frontend`, are not checked against `ExtensionCapabilities` when read.
/// - `requires` is left out when absent.
/// - `critical` lists member paths, such as `capabilities.frontend`, that a
///   reader must understand. A reader refuses a claim set with a path it
///   does not understand. `critical` is left out when empty, and an absent
///   `critical` is read as empty.
pub type CapabilityClaimSet {
  CapabilityClaimSet(
    claims_version: String,
    protocol_versions: List(String),
    extension: ExtensionInfo,
    capabilities: Dict(String, Json),
    requires: Option(ClaimsRequirements),
    critical: List(String),
  )
}

// -- Methods ----------------------------------------------------------------

/// A MEP method. The wire value is the JSON-RPC 2.0 `method` string:
///
/// | Constructor         | Wire value                       | Kind         |
/// | ------------------- | -------------------------------- | ------------ |
/// | `Initialize`        | `morphir.initialize`             | request      |
/// | `Describe`          | `morphir.extension.describe`     | request      |
/// | `Initialized`       | `morphir.initialized`            | notification |
/// | `Ping`              | `morphir.ping`                   | request      |
/// | `Info`              | `morphir.extension.info`         | request      |
/// | `Capabilities`      | `morphir.extension.capabilities` | request      |
/// | `Compile`           | `morphir.frontend.compile`       | request      |
/// | `CompileModel`      | `morphir.frontend.compileModel`  | request      |
/// | `Generate`          | `morphir.backend.generate`       | request      |
/// | `GenerateModel`     | `morphir.backend.generateModel`  | request      |
/// | `Validate`          | `morphir.validator.validate`     | request      |
/// | `Transform`         | `morphir.transform.transform`    | request      |
/// | `WorkspaceDiscover` | `morphir.workspace.discover`     | request      |
/// | `Shutdown`          | `morphir.shutdown`               | request      |
/// | `Exit`              | `morphir.exit`                   | notification |
/// | `CancelRequest`     | `$/cancelRequest`                | notification |
/// | `Progress`          | `morphir.progress`               | notification |
///
/// A notification carries no request id and gets no response.
///
/// `$/cancelRequest` and `morphir.progress` come from the protocol draft
/// (docs/design/draft/extensions/protocol.md). A host sends
/// `$/cancelRequest` only to an extension that advertises `cancellation`,
/// and an extension sends `morphir.progress` only when it advertises
/// `progress`. The Rust SDK does not send or handle them yet.
pub type Method {
  Initialize
  Describe
  Initialized
  Ping
  Info
  Capabilities
  Compile
  CompileModel
  Generate
  GenerateModel
  Validate
  Transform
  WorkspaceDiscover
  Shutdown
  Exit
  CancelRequest
  Progress
}

// -- Errors -----------------------------------------------------------------

/// An error code in a JSON-RPC 2.0 error object. The wire value is the
/// integer code:
///
/// | Constructor               | Code   |
/// | ------------------------- | ------ |
/// | `ParseError`              | -32700 |
/// | `InvalidRequest`          | -32600 |
/// | `MethodNotFound`          | -32601 |
/// | `InvalidParams`           | -32602 |
/// | `InternalError`           | -32603 |
/// | `ExtensionError`          | -32000 |
/// | `CompilationError`        | -32001 |
/// | `GenerationError`         | -32002 |
/// | `ValidationError`         | -32003 |
/// | `TransformationError`     | -32004 |
/// | `ExtensionFailure`        | -32010 |
/// | `ProtocolVersionMismatch` | -32011 |
/// | `PermissionDenied`        | -32012 |
/// | `CapabilityUnavailable`   | -32013 |
/// | `NotInitialized`          | -32014 |
/// | `RequestCancelled`        | -32800 |
///
/// The first five are the JSON-RPC 2.0 standard codes. `ExtensionError`
/// through `NotInitialized` are MEP codes in the server-defined range, -32000
/// to -32099. `RequestCancelled` is the code the protocol draft gives to a
/// cancelled request, as in the Language Server Protocol; the Rust SDK does
/// not define it yet.
pub type ErrorCode {
  ParseError
  InvalidRequest
  MethodNotFound
  InvalidParams
  InternalError
  ExtensionError
  CompilationError
  GenerationError
  ValidationError
  TransformationError
  ExtensionFailure
  ProtocolVersionMismatch
  PermissionDenied
  CapabilityUnavailable
  NotInitialized
  RequestCancelled
}

/// The JSON-RPC 2.0 error object. `code` is an `ErrorCode` value or a
/// JSON-RPC 2.0 standard code; it is a signed 32-bit integer, i32 in the SDK.
/// `data` is left out of the message when absent.
pub type RpcError {
  RpcError(code: Int, message: String, data: Option(Json))
}

// -- Cancellation and progress ---------------------------------------------

/// A JSON-RPC 2.0 request id. On the wire it is the number or the string
/// itself, not a tagged constructor. A numeric id is non-negative; u64 in the
/// SDK, which sends numeric ids only.
pub type RequestId {
  NumericRequestId(value: Int)
  StringRequestId(value: String)
}

/// Parameters of `$/cancelRequest`: the id of the request to cancel. An
/// extension that advertises `cancellation` stops useful work and answers
/// the cancelled request with `RequestCancelled`. Cancellation is
/// cooperative.
pub type CancelParams {
  CancelParams(id: RequestId)
}

/// The stage of a progress report. Wire values: `begin`, `report`, `end`.
pub type ProgressKind {
  ProgressBegin
  ProgressReport
  ProgressEnd
}

/// Parameters of `morphir.progress`, for an active request.
///
/// Wire rules: `percentage` is left out when absent. When present, it is an
/// integer from 0 through 100.
pub type ProgressParams {
  ProgressParams(
    request_id: RequestId,
    kind: ProgressKind,
    message: String,
    percentage: Option(Int),
  )
}

// -- Compile ----------------------------------------------------------------

/// A source document sent to a frontend. `version` goes up each time the
/// document changes. It is non-negative; u64 in the SDK.
pub type SourceDocument {
  SourceDocument(uri: String, language_id: String, version: Int, text: String)
}

/// The package a compilation builds.
///
/// Wire rules: `exposed_modules` (wire `exposedModules`) is left out when
/// absent. An absent list exposes every module; an empty list exposes none.
pub type CompilePackage {
  CompilePackage(name: String, exposed_modules: Option(List(String)))
}

/// A package distribution the compilation can use. `distribution` is a
/// serialized Morphir distribution in the IR version that `ir_version` names.
pub type CompileDependency {
  CompileDependency(
    package_name: String,
    ir_version: String,
    distribution: Json,
  )
}

/// Options that control a compilation.
///
/// Wire rules:
/// - `typesOnly` and `irVersion` are required and always written.
/// - Members of `extra` sit beside the named members on the wire, not under
///   an `extra` key. Unknown members are read into `extra`.
/// - A writer refuses an `extra` key named `typesOnly`, `irVersion`,
///   `sourceRootUri` or `sourceRoot`.
/// - A reader refuses the legacy keys `sourceRootUri` and `sourceRoot`: the
///   source root belongs in `SourceSet.root`.
pub type CompileOptions {
  CompileOptions(
    types_only: Bool,
    ir_version: String,
    extra: Dict(String, Json),
  )
}

/// The documents a compilation submits, with the root that module names are
/// derived against.
///
/// Wire rules: `root` is left out when absent.
pub type SourceSet {
  SourceSet(root: Option(String), documents: List(SourceDocument))
}

/// Parameters of `morphir.frontend.compile`.
///
/// Wire rules:
/// - `sources` is required. Unknown members are ignored, including a
///   top-level `documents`, which cannot replace `sources`.
/// - An absent `dependencies` is read as empty.
/// - `baseline` is left out when absent.
pub type CompileRequest {
  CompileRequest(
    language_id: String,
    sources: SourceSet,
    package: CompilePackage,
    dependencies: List(CompileDependency),
    options: CompileOptions,
    baseline: Option(CompileBaseline),
  )
}

/// Result of `morphir.frontend.compile`.
///
/// Wire rules:
/// - `irVersion`, `ir` and `contextDigest` are left out when absent.
/// - An absent `diagnostics` or `modules` is read as empty.
/// - `moduleResults` is left out when empty, and an absent `moduleResults`
///   is read as empty.
pub type CompileResult {
  CompileResult(
    success: Bool,
    ir_version: Option(String),
    ir: Option(Json),
    diagnostics: List(Diagnostic),
    modules: List(String),
    module_results: List(ModuleResult),
    context_digest: Option(String),
  )
}

/// A module from a prior compilation, sent back for incremental compilation.
///
/// Wire rules: an absent `dependsOn` is read as empty. `frontendState` is
/// left out when absent.
pub type BaselineModule {
  BaselineModule(
    name: String,
    uri: String,
    source_digest: String,
    interface_digest: String,
    depends_on: List(String),
    ir: Json,
    frontend_state: Option(Json),
  )
}

/// The baseline a host sends for incremental compilation.
///
/// Wire rules: an absent `modules` is read as empty. `contextDigest` is left
/// out when absent, and a baseline without it cannot be reused.
pub type CompileBaseline {
  CompileBaseline(modules: List(BaselineModule), context_digest: Option(String))
}

/// The outcome for one module in an incremental compilation. Wire values are
/// lowercase: `compiled`, `unchanged`, `failed`, `blocked`.
pub type ModuleStatus {
  Compiled
  Unchanged
  Failed
  Blocked
}

/// The result for one module in an incremental compilation.
///
/// Wire rules: `sourceDigest`, `interfaceDigest`, `ir` and `frontendState`
/// are left out when absent. An absent `dependsOn` or `diagnostics` is read
/// as empty.
pub type ModuleResult {
  ModuleResult(
    name: String,
    uri: String,
    status: ModuleStatus,
    source_digest: Option(String),
    interface_digest: Option(String),
    depends_on: List(String),
    ir: Option(Json),
    frontend_state: Option(Json),
    diagnostics: List(Diagnostic),
  )
}

// -- Rich model transport ---------------------------------------------------

/// A model operation. Wire values are `morphir.frontend.compileModel` and
/// `morphir.backend.generateModel`, respectively. These methods require the
/// exact MEP draft `0.2.0-draft.1`, bilateral model transport and operation
/// capability admission; legacy `0.1` never enables them.
pub type ModelOperation {
  CompileModelOperation
  GenerateModelOperation
}

/// The representation of a complete model document. Wire values are
/// `ion-binary` and `morphir-json`. Ion binary is the recommended default;
/// JSON remains a supported choice. The host offer order, not the codec, sets
/// the default of a session. A codec does not assert a semantic guarantee.
/// Ion uses media type `application/ion` with its binary version marker;
/// Morphir JSON uses `application/json` encoded as UTF-8.
pub type ModelCodec {
  IonBinaryCodec
  MorphirJsonCodec
}

/// The payload layout. Wire value: `single-document`. There are no implicit
/// file references, document trees, compression or external symbol tables.
pub type ModelLayout {
  SingleDocumentModel
}

/// One supported combination, never independent lists whose Cartesian product
/// might imply unsupported combinations. `envelopeVersion` is the exact
/// independent envelope draft `0.1.0-draft.1`; `irVersion` names semantic IR,
/// not MEP or the envelope. `profile` is a nonempty model-content profile id,
/// independent of source language and target language. See model-transport.md.
pub type ModelTransportTuple {
  ModelTransportTuple(
    operation: ModelOperation,
    profile: String,
    codec: ModelCodec,
    envelope_version: String,
    ir_version: String,
  )
}

/// Bounds applied before allocation and parsing. Encoded bytes count the UTF-8
/// base64 content member, not its JSON quotes; decoded bytes count payload
/// bytes, summed across model, dependency and evidence payloads per message.
/// Values are positive and at most 2147483647 (u32 in bindings with
/// the same bound). Depth and nodes also apply to decoded profile content.
/// Depth counts each document root as one; nodes sum decoded value nodes.
/// Session values never exceed either peer's independently configured limits.
pub type ModelTransportLimits {
  ModelTransportLimits(
    max_encoded_bytes: Int,
    max_decoded_bytes: Int,
    max_depth: Int,
    max_nodes: Int,
  )
}

/// Offers or session support. Tuples are complete and unique. An absent offer
/// never grants model support; an empty list supports no model operations.
/// `guarantees` lists nonempty ids the peer can interpret, not guarantees it
/// has established. An absent `guarantees` is read as empty. Unknown required
/// guarantees refuse invocation; optional evidence remains preserved.
pub type ModelTransportSupport {
  ModelTransportSupport(
    tuples: List(ModelTransportTuple),
    limits: ModelTransportLimits,
    guarantees: List(String),
  )
}

/// Opaque single-document bytes, independently bounded and hashed. `content`
/// is canonical padded RFC 4648 base64 for BOTH codecs, without whitespace.
/// `decodedByteLength` is non-negative, at most 2147483647 (u32 in bindings),
/// and equals the decoded bytes. `sha256` is 64 lowercase hexadecimal digits
/// over those exact bytes, before profile parsing; it is not a semantic hash
/// or logical model revision. Unknown optional Ion facts and ordered
/// annotations survive by retaining the complete bytes and symbol tables.
pub type ModelPayload {
  ModelPayload(
    codec: ModelCodec,
    layout: ModelLayout,
    decoded_byte_length: Int,
    sha256: String,
    content: String,
  )
}

/// A required guarantee for an exact scope, with nonempty namespaced ids.
/// A scope is a model or node identity, not an ambient filesystem path.
pub type ModelGuaranteeRequirement {
  ModelGuaranteeRequirement(guarantee: String, scope: String)
}

/// A claim, not authority: the receiver must admit this evidence under its
/// checking/trust policy before it can establish a prerequisite. All identity
/// and scope strings are nonempty. `contextDigest` is a SHA-256 string for
/// the declared dependency/configuration context. Identity, revision, context
/// and exact scope must match the required view; producer is attribution,
/// never authentication. The opaque evidence payload has the same bounds.
pub type ModelGuaranteeEvidence {
  ModelGuaranteeEvidence(
    guarantee: String,
    model_id: String,
    model_revision: String,
    context_digest: String,
    scope: String,
    producer: String,
    evidence: ModelPayload,
  )
}

/// A Morphir model envelope. The payload's profile defines its content; the
/// existing semantic IR Distribution owns Library/Specs/Application variants.
/// There is no outer parsed/typed/optimized state enum. Checked guarantees
/// are independent revision/context-scoped views established by admission.
/// `revision` is a nonempty logical immutable revision, not a transport hash.
/// Changes to semantic content or facts mint a revision and invalidate evidence
/// unless an explicit component contract proves preservation. Exact transcoding
/// can preserve a logical revision, but must recompute the payload digest.
///
/// Wire rules: an absent `evidence` is read as empty. `critical` is left out
/// when empty and read as empty when absent. It lists exact registered member
/// paths relative to the envelope; a known parent never admits an unknown
/// critical child. Unknown required paths refuse admission. Preserve unknown
/// optional profile enrichments, annotation order and provenance as bytes.
pub type MorphirModel {
  MorphirModel(
    envelope_version: String,
    model_id: String,
    revision: String,
    ir_version: String,
    profile: String,
    payload: ModelPayload,
    evidence: List(ModelGuaranteeEvidence),
    critical: List(String),
  )
}

/// A complete dependency model, not a legacy JSON-only distribution. Its
/// format must match the compile operation's selected tuple. Package name
/// retains CompileDependency's package-namespace meaning.
pub type CompileModelDependency {
  CompileModelDependency(package_name: String, model: MorphirModel)
}

/// A complete source-set compilation. `output` selects one compileModel tuple
/// already admitted in this session. `options.irVersion` must equal its exact
/// `irVersion`. The frontend's language and source-count capabilities still
/// apply. `contextDigest` binds the declared dependency/configuration context.
/// No legacy incremental baseline is implied by this new operation.
/// Wire rules: absent `dependencies` is read as empty.
pub type CompileModelRequest {
  CompileModelRequest(
    language_id: String,
    sources: SourceSet,
    package: CompilePackage,
    dependencies: List(CompileModelDependency),
    options: CompileOptions,
    context_digest: String,
    output: ModelTransportTuple,
  )
}

/// A success/failure sum. On the wire, ModelCompiled is an object with
/// `success: true`, a REQUIRED `model`, `diagnostics` and `modules`.
/// ModelCompilationFailed has `success: false` and `diagnostics`; `model`
/// MUST be absent, even null is refused. Non-boolean success tags are refused.
/// An absent `diagnostics` or success `modules` is read as empty. A successful
/// result's complete model must match the selected output tuple and limits.
pub type CompileModelResult {
  ModelCompiled(
    model: MorphirModel,
    diagnostics: List(Diagnostic),
    modules: List(String),
  )
  ModelCompilationFailed(diagnostics: List(Diagnostic))
}

/// Generate from a retained model. `input` selects an admitted generateModel
/// tuple; the model's profile, codec, envelope and semantic IR version must
/// match it. `target` is the exact advertised target, independent of profile.
/// Evidence must bind this model revision and `contextDigest`, and be admitted
/// for each exact required scope before pure generation. The result reuses
/// GenerateResult and Artifact, including their existing binary encoding.
/// If the host has the model in a tuple that the session does not agree, but
/// can convert it to an agreed tuple, the host sends the model converted to
/// the first agreed tuple in host order that it can reach without loss. Only
/// when no agreed tuple is lossless does it select the first such tuple. The
/// converted model keeps its `modelId`, has its own digest and a revision
/// derived from that digest, and evidence for the original does not carry
/// over. The host reports every conversion to the user as a diagnostic or
/// notification, and adds no file to the result for it. The host
/// refuses a lossy conversion, and the refusal is not
/// `extension.tuple_unavailable`, unless the user allows loss for that
/// operation. Only when it cannot convert does it report
/// `extension.tuple_unavailable`.
/// Wire rules: absent `requiredGuarantees` or `options` is read as empty.
pub type GenerateModelRequest {
  GenerateModelRequest(
    model: MorphirModel,
    input: ModelTransportTuple,
    target: String,
    context_digest: String,
    required_guarantees: List(ModelGuaranteeRequirement),
    options: Dict(String, Json),
  )
}

// -- Generate ---------------------------------------------------------------

/// Parameters of `morphir.backend.generate`. `target` is the exact target id
/// the host selected; a backend does not guess a default.
///
/// Wire rules: an absent `options` is read as empty.
pub type GenerateRequest {
  GenerateRequest(ir: Json, target: String, options: Dict(String, Json))
}

/// Result of `morphir.backend.generate`.
///
/// Wire rules: an absent `artifacts` or `diagnostics` is read as empty.
pub type GenerateResult {
  GenerateResult(
    success: Bool,
    artifacts: List(Artifact),
    diagnostics: List(Diagnostic),
  )
}

/// A generated file. `path` is relative to the output directory.
///
/// Wire rules: when `binary` is true, `content` is base64; otherwise it is
/// text. An absent `binary` is read as false.
pub type Artifact {
  Artifact(path: String, content: String, binary: Bool)
}

// -- Diagnostics ------------------------------------------------------------

/// A diagnostic message. `data` is structured data that the extension owns,
/// such as values for a fix.
///
/// Wire rules: `code`, `location` and `data` are left out when absent.
/// `related` is left out when empty, and an absent `related` is read as
/// empty.
pub type Diagnostic {
  Diagnostic(
    severity: DiagnosticSeverity,
    code: Option(String),
    message: String,
    location: Option(SourceLocation),
    related: List(RelatedInformation),
    data: Option(Json),
  )
}

/// How serious a diagnostic is. Wire values are lowercase: `error`,
/// `warning`, `info`, `hint`.
pub type DiagnosticSeverity {
  ErrorSeverity
  WarningSeverity
  InfoSeverity
  HintSeverity
}

/// A range in a source document, identified by URI.
pub type SourceLocation {
  SourceLocation(uri: String, range: SourceRange)
}

/// A half-open range: `start` is inclusive and `end` is exclusive.
pub type SourceRange {
  SourceRange(start: SourcePosition, end: SourcePosition)
}

/// A zero-based position in a source document. `line` counts lines.
/// `character` counts UTF-16 code units from the start of the line, as in
/// the Language Server Protocol. Both are non-negative; u32 in the SDK.
pub type SourcePosition {
  SourcePosition(line: Int, character: Int)
}

/// More information about a diagnostic, at another location.
pub type RelatedInformation {
  RelatedInformation(location: SourceLocation, message: String)
}
