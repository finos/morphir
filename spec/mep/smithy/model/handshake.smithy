$version: "2"

// Handshake, capabilities and capability claims. See mep.smithy for the
// scope and the meaning of `GAP smithy-` comments.
namespace morphir.mep

// -- Handshake --------------------------------------------------------------

/// What kind of peer introduced itself.
// GAP smithy-2qe.34.23: MEP reads an unknown kind as `unspecified`, but
// the validator refuses a value that the enum does not declare.
enum PeerKind {
    CLI = "cli"
    UNSPECIFIED = "unspecified"
}

/// A host or an extension, as it introduces itself.
structure PeerInfo {
    /// Older messages leave `kind` out. An absent kind is read as
    /// `unspecified`.
    kind: PeerKind

    @required
    name: String

    @required
    version: String
}

/// Parameters of `morphir.extension.describe`: the protocol versions that
/// the caller understands.
structure DescribeParams {
    @required
    protocolVersions: StringList
}

/// Parameters of `morphir.initialize`. The model-operation draft uses full
/// SemVer protocol versions; the legacy `0.1` spelling is the one exception.
// GAP smithy-2qe.34.17: receivers ignore unknown members, such as a future
// `workspace` or `permissions`, but the validator refuses them.
structure InitializeParams {
    @required
    protocolVersions: StringList

    @required
    host: PeerInfo

    /// The host offer. Left out when absent. Absence means legacy only, and
    /// never an implicit offer of model transport.
    modelTransport: ModelTransportSupport
}

/// Result of `morphir.initialize`.
// GAP smithy-2qe.34.24: nothing checks that `protocolVersion` is one
// of the offered `protocolVersions`, or that the session `modelTransport` is
// a bilateral subset of the host offer.
structure InitializeResult {
    @required
    protocolVersion: String

    @required
    extension: ExtensionInfo

    @required
    capabilities: ExtensionCapabilities
}

/// A kind of extension.
enum ExtensionType {
    FRONTEND = "frontend"
    BACKEND = "backend"
    TRANSFORM = "transform"
    VALIDATOR = "validator"
    WORKSPACE = "workspace"
}

list ExtensionTypeList {
    member: ExtensionType
}

/// Who an extension is. Member names stay snake_case on the wire for this
/// record. Optional members are left out when absent.
structure ExtensionInfo {
    @required
    id: String

    @required
    name: String

    @required
    version: String

    description: String

    @required
    types: ExtensionTypeList

    author: String

    homepage: String

    license: String

    min_sdk_version: String
}

// -- Capabilities -----------------------------------------------------------

/// A source language that a frontend reads.
structure LanguageCapability {
    @required
    id: String

    @required
    fileExtensions: StringList
}

list LanguageCapabilityList {
    member: LanguageCapability
}

/// What a frontend can compile.
structure FrontendCapability {
    @required
    languages: LanguageCapabilityList

    @required
    irVersions: StringList

    @required
    compile: Boolean

    @required
    incremental: Boolean

    /// Reserved. It has no defined meaning yet, and a host does not act on it.
    @required
    fragments: Boolean

    /// Written only when true. Absent means false. A frontend without it
    /// compiles exactly one document for each request.
    multiDocument: Boolean = false
}

/// What a backend can generate.
structure BackendCapability {
    @required
    targets: StringList

    @required
    irVersions: StringList

    @required
    generate: Boolean
}

/// Workspace discovery support. Each protocol version is a full SemVer
/// string, such as `0.1.0`, of the workspace discovery protocol, not of MEP.
structure WorkspaceCapability {
    @required
    protocolVersions: StringList

    @required
    discover: Boolean
}

/// What an extension can do.
///
/// `frontend`, `backend`, `workspace` and `modelTransport` are left out when
/// absent. An absent `modelTransport` means legacy only. In a session,
/// `modelTransport` contains only tuples that both peers offer, and limits
/// no larger than the limits of each peer.
///
/// The four flags are always written. An absent flag is read as false.
// GAP smithy-2qe.34.18: the Gleam `extra` members sit beside the
// named members on the wire, and a writer refuses an `extra` key that is a
// named member. Smithy cannot declare additional members of a structure, so
// an `extra` member is an unknown member here.
structure ExtensionCapabilities {
    frontend: FrontendCapability

    backend: BackendCapability

    workspace: WorkspaceCapability

    modelTransport: ModelTransportSupport

    streaming: Boolean = false

    incremental: Boolean = false

    cancellation: Boolean = false

    progress: Boolean = false
}

// -- Claims -----------------------------------------------------------------

/// Requirements that a claim set puts on the host. Each `host` entry is one
/// SemVer comparator, such as `>=0.4.0`. All of them must hold. `host` is
/// left out when empty and read as empty when absent.
structure ClaimsRequirements {
    host: StringList = []
}

/// The result of `morphir.extension.describe`: the capabilities that an
/// extension claims, without a session.
///
/// Writers send `claimsVersion` `0.1.0-draft.2`. Readers also accept
/// draft.1, which names the member `statementVersion`.
// GAP smithy-2qe.34.21: exactly one of `claimsVersion` and
// `statementVersion` must be present. Both are optional here, so a claim set
// with neither or both is accepted.
// GAP smithy-2qe.34.17: unknown top-level members are dropped when
// read, but the validator refuses them.
// GAP smithy-2qe.34.17: a reader refuses a claim set whose
// `critical` names a path that it does not understand. The validator cannot
// check this rule.
structure CapabilityClaimSet {
    claimsVersion: String

    statementVersion: String

    /// Full SemVer MEP versions, and the legacy `0.1` spelling.
    @required
    protocolVersions: StringList

    @required
    extension: ExtensionInfo

    /// Open: members that the contract does not name are kept. Named
    /// members, such as `frontend`, are not checked when read.
    @required
    capabilities: JsonObject

    /// Left out when absent.
    requires: ClaimsRequirements

    /// Member paths that a reader must understand. Left out when empty.
    critical: StringList = []
}
