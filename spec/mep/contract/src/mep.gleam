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
/// string, such as `0.1.0`.
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
///   draft.1 `critical` list, `statementVersion` is read as `claimsVersion`.
/// - `capabilities` is open: members this contract does not name are kept
///   when read and written.
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
/// | Constructor         | Wire value                       |
/// | ------------------- | -------------------------------- |
/// | `Initialize`        | `morphir.initialize`             |
/// | `Describe`          | `morphir.extension.describe`     |
/// | `Initialized`       | `morphir.initialized`            |
/// | `Ping`              | `morphir.ping`                   |
/// | `Info`              | `morphir.extension.info`         |
/// | `Capabilities`      | `morphir.extension.capabilities` |
/// | `Compile`           | `morphir.frontend.compile`       |
/// | `Generate`          | `morphir.backend.generate`       |
/// | `Validate`          | `morphir.validator.validate`     |
/// | `Transform`         | `morphir.transform.transform`    |
/// | `WorkspaceDiscover` | `morphir.workspace.discover`     |
/// | `Shutdown`          | `morphir.shutdown`               |
/// | `Exit`              | `morphir.exit`                   |
///
/// `morphir.initialized` and `morphir.exit` are notifications: they carry no
/// request id and get no response. All other methods are requests.
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
///
/// The first five are the JSON-RPC 2.0 standard codes. The others are MEP
/// codes in the server-defined range, -32000 to -32099.
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
}

/// The JSON-RPC 2.0 error object. `code` is an `ErrorCode` value or a
/// JSON-RPC 2.0 standard code. `data` is left out of the message when absent.
pub type RpcError {
  RpcError(code: Int, message: String, data: Option(Json))
}
