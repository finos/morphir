$version: "2"

namespace morphir.mep

/// Exact SemVer tokens for bounded model access.
enum ModelAccessProtocolVersion {
    DRAFT_2 = "0.2.0-draft.2"
}

enum ModelAccessVersion {
    DRAFT_1 = "0.1.0-draft.1"
}

enum ModelAccessIrVersion {
    IR_3 = "3.1.0"
    IR_4 = "4.0.0"
}

enum ModelAccessOperation {
    GENERATE_MODEL = "morphir.backend.generateModel"
}

enum ModelAccessProfile {
    MORPHIR_IR = "morphir-ir"
}

enum ModelAccessCodec {
    MORPHIR_JSON = "morphir-json"
    MORPHIR_YAML = "morphir-yaml"
}

enum ModelAccessLayout {
    DOCUMENT_TREE = "document-tree"
}

enum ModelAccessEncoding {
    PLAIN = "plain"
    CONTEXT_DRAFT_1 = "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json"
}

structure ModelAccessTuple {
    @required
    protocolVersion: ModelAccessProtocolVersion

    @required
    accessVersion: ModelAccessVersion

    @required
    operation: ModelAccessOperation

    @required
    irVersion: ModelAccessIrVersion

    @required
    profile: ModelAccessProfile

    @required
    codec: ModelAccessCodec

    @required
    layout: ModelAccessLayout

    @required
    contextualEncoding: ModelAccessEncoding
}

@uniqueItems
list ModelAccessTupleList {
    member: ModelAccessTuple
}

@range(min: 1, max: 9007199254740991)
long PositiveSessionLimit

@range(min: 0, max: 9007199254740991)
long ArtifactOffset

structure ModelAccessLimits {
    @required
    maxFrameBytes: PositiveLimit

    @required
    maxEncodedBytesPerExchange: PositiveLimit

    @required
    maxDecodedBytesPerExchange: PositiveLimit

    @required
    maxDocumentsPerBatch: PositiveLimit

    @required
    maxDepth: PositiveLimit

    @required
    maxNodes: PositiveLimit

    @required
    maxDiagnosticsPerExchange: PositiveLimit

    @required
    maxOutstandingRequests: PositiveLimit

    @required
    maxGuestStateBytes: PositiveLimit

    @required
    maxHostCacheBytes: PositiveLimit

    @required
    maxArtifactChunkBytes: PositiveLimit

    @required
    maxArtifactBytes: PositiveSessionLimit

    @required
    maxTotalArtifactBytes: PositiveSessionLimit

    @required
    maxSessionDiskBytes: PositiveSessionLimit

    @required
    maxSessionWorkUnits: PositiveSessionLimit

    @required
    maxRounds: PositiveLimit

    @required
    maxCallMilliseconds: PositiveLimit

    @required
    maxSessionMilliseconds: PositiveLimit
}

structure ModelAccessSupport {
    @required
    tuples: ModelAccessTupleList

    @required
    limits: ModelAccessLimits
}

structure ModelAccessSnapshot {
    @required
    snapshotId: NonEmptyString

    @required
    modelId: NonEmptyString

    @required
    revision: NonEmptyString

    @required
    contextDigest: Sha256Hex

    @required
    scope: NonEmptyString
}

structure ModelAccessStart {
    @required
    sessionId: NonEmptyString

    @required
    snapshot: ModelAccessSnapshot

    @required
    input: ModelAccessTuple

    @required
    target: NonEmptyString

    @required
    options: Document

    @required
    requiredGuarantees: ModelGuaranteeRequirementList

    @required
    limits: ModelAccessLimits
}

structure ModelAccessAdvance {
    @required
    sessionId: NonEmptyString

    @required
    round: PositiveLimit

    @required
    deliveries: ModelAccessDeliveryList
}

structure ModelAccessCancel {
    @required
    sessionId: NonEmptyString
}

enum ModelAccessReadKind {
    INVENTORY = "inventory"
    DOCUMENT = "document"
}

/// Shape of the kind-tagged sum. The tag determines required and forbidden members.
structure ModelAccessRequest {
    @required
    requestId: NonEmptyString

    @required
    kind: ModelAccessReadKind

    selection: NonEmptyString
    pageSize: PositiveLimit
    cursor: NonEmptyString
    documentId: NonEmptyString
}

list ModelAccessRequestList {
    member: ModelAccessRequest
}

/// Shape of the kind-tagged sum. Session and tag checks apply on admission.
structure ModelAccessDelivery {
    @required
    requestId: NonEmptyString

    @required
    kind: ModelAccessReadKind

    @required
    snapshotId: NonEmptyString

    entries: ModelInventoryEntryList
    nextCursor: NonEmptyString
    documentId: NonEmptyString

    @range(min: 0, max: 2147483647)
    decodedByteLength: Integer

    sha256: Sha256Hex
    content: Base64Content
}

list ModelAccessDeliveryList {
    member: ModelAccessDelivery
}

enum ModelInventoryRole {
    DEFINITION = "definition"
    SPECIFICATION = "specification"
}

/// The single member name selects the corresponding inventory entry.
union ModelInventoryEntry {
    module: ModuleEntry
    type: TypeEntry
    value: ValueEntry
}

structure ModuleEntry {
    @required
    documentId: NonEmptyString

    @required
    packageName: NonEmptyString

    @required
    modulePath: NonEmptyString

    @required
    role: ModelInventoryRole

    memberSelection: NonEmptyString
}

structure TypeEntry {
    @required
    documentId: NonEmptyString

    @required
    packageName: NonEmptyString

    @required
    modulePath: NonEmptyString

    @required
    role: ModelInventoryRole

    @required
    name: NonEmptyString
}

structure ValueEntry {
    @required
    documentId: NonEmptyString

    @required
    packageName: NonEmptyString

    @required
    modulePath: NonEmptyString

    @required
    role: ModelInventoryRole

    @required
    name: NonEmptyString
}

list ModelInventoryEntryList {
    member: ModelInventoryEntry
}

structure ModelArtifactChunk {
    @required
    path: NonEmptyString

    @required
    offset: ArtifactOffset

    @required
    @range(min: 0, max: 2147483647)
    decodedByteLength: Integer

    @required
    sha256: Sha256Hex

    @required
    content: Base64Content

    @required
    end: Boolean
}

list ModelArtifactChunkList {
    member: ModelArtifactChunk
}

enum ModelAccessState {
    CONTINUE = "continue"
    COMPLETE = "complete"
    FAILED = "failed"
}

/// Shape of the state-tagged sum. The draft defines allowed fields for each state.
structure ModelAccessStep {
    @required
    state: ModelAccessState

    @required
    sessionId: NonEmptyString

    round: PositiveLimit
    requests: ModelAccessRequestList
    artifacts: ModelArtifactChunkList

    @required
    diagnostics: DiagnosticList
}
