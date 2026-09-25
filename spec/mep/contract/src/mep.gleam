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

/// Parameters of `morphir.initialize`.
pub type InitializeParams {
  InitializeParams(protocol_versions: List(String), host: PeerInfo)
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
/// not MEP versions, which use the `MAJOR.MINOR` form.
pub type WorkspaceCapability {
  WorkspaceCapability(protocol_versions: List(String), discover: Bool)
}

/// What an extension can do.
///
/// Wire rules:
/// - `frontend`, `backend` and `workspace` are left out when absent.
/// - The four flags `streaming`, `incremental`, `cancellation` and
///   `progress` are always written. An absent flag is read as false.
/// - Members of `extra` sit beside the named members on the wire, not under
///   an `extra` key. Unknown members are read into `extra`.
/// - A writer refuses an `extra` key that is one of the reserved names
///   `frontend`, `backend`, `workspace`, `streaming`, `incremental`,
///   `cancellation` or `progress`.
pub type ExtensionCapabilities {
  ExtensionCapabilities(
    frontend: Option(FrontendCapability),
    backend: Option(BackendCapability),
    workspace: Option(WorkspaceCapability),
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
/// - `protocol_versions` (wire `protocolVersions`) are MEP versions in the
///   canonical `MAJOR.MINOR` form, such as `0.1`, not full SemVer.
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
/// | `Generate`          | `morphir.backend.generate`       | request      |
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
  Generate
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
/// JSON-RPC 2.0 standard code. `data` is left out of the message when absent.
pub type RpcError {
  RpcError(code: Int, message: String, data: Option(Json))
}

// -- Cancellation and progress ---------------------------------------------

/// A JSON-RPC 2.0 request id. On the wire it is the number or the string
/// itself, not a tagged constructor.
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

/// A source document sent to a frontend. `version` is a non-negative integer
/// that goes up each time the document changes.
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

/// A diagnostic message.
///
/// Wire rules: `code` and `location` are left out when absent. `related` is
/// left out when empty, and an absent `related` is read as empty.
pub type Diagnostic {
  Diagnostic(
    severity: DiagnosticSeverity,
    code: Option(String),
    message: String,
    location: Option(SourceLocation),
    related: List(RelatedInformation),
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
/// the Language Server Protocol. Both are non-negative.
pub type SourcePosition {
  SourcePosition(line: Int, character: Int)
}

/// More information about a diagnostic, at another location.
pub type RelatedInformation {
  RelatedInformation(location: SourceLocation, message: String)
}
