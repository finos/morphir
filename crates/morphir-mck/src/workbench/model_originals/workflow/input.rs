// Generated private inputV27 descriptor. Source schema and all original literals remain unchanged.
// Root supplies same-owner closed macros and genuine validated leaves; no trial or Value fallback.
// optional fields are Presence<T>: explicit null still passes through T and refuses.
// Whole-document delegates and nested discriminators preserve exact branch correlation.
// Every declaration/use/source branch/constant/bound is recorded in translation.json.

use super::*;

text! { AtomicBytesHexHex { min: 0, max: 1048576, pattern: "^(?:[0-9a-f]{1024})*(?:[0-9a-f]{2}){0,511}$" } }

tagged! { AtomicBytes("kind") {
    Hex => "hex" {
        hex: AtomicBytesHexHex => "hex",
    },
    Utf8 => "utf8" {
        text: Text<0, 1048576> => "text",
    },
    RepeatU8 => "repeat-u8" {
        byte: U8 => "byte",
        length: Natural<0, 268435456> => "length",
    },
    CycleU8 => "cycle-u8" {
        length: Natural<0, 268435456> => "length",
        seed: U8 => "seed",
    },
    ChunkIndexedU8 => "chunk-indexed-u8" {
        length: Natural<0, 268435456> => "length",
        seed: U8 => "seed",
    },
} }

text! { BytesHexHex { min: 0, max: 1048576, pattern: "^(?:[0-9a-f]{1024})*(?:[0-9a-f]{2}){0,511}$" } }

tagged! { Bytes("kind") {
    Hex => "hex" {
        hex: BytesHexHex => "hex",
    },
    Utf8 => "utf8" {
        text: Text<0, 1048576> => "text",
    },
    RepeatU8 => "repeat-u8" {
        byte: U8 => "byte",
        length: Natural<0, 268435456> => "length",
    },
    CycleU8 => "cycle-u8" {
        length: Natural<0, 268435456> => "length",
        seed: U8 => "seed",
    },
    ChunkIndexedU8 => "chunk-indexed-u8" {
        length: Natural<0, 268435456> => "length",
        seed: U8 => "seed",
    },
    Concat => "concat" {
        parts: Items<AtomicBytes, 1, 4096> => "parts",
    },
} }

words! { ClientActionStartImportVia {
    Browser => "browser",
    Native => "native",
} }

words! { ClientActionStartConnectedScope {
    Primary => "primary",
    Complete => "complete",
} }

words! { ClientActionStartConnectedSemantic {
    None => "none",
    Projection => "projection",
} }

words! { ClientActionReadRunEffectKind {
    ReadOriginal => "read-original",
    ReadProjection => "read-projection",
} }

literal! { ClientActionReadRunExpectedRequestContractVersion => "0.1.0-draft.1" }

literal! { ClientActionReadRunExpectedRequestMethod => "morphir.model-originals.read" }

record! { ClientActionReadRunExpectedRequest {
        capture_id: Text<0, 128> => "captureId",
        contract_version: ClientActionReadRunExpectedRequestContractVersion => "contractVersion",
        max_bytes: Natural<1, 65536> => "maxBytes",
        method: ClientActionReadRunExpectedRequestMethod => "method",
        target: ReadTarget => "target",
} }

record! { ClientActionReadRunWindow {
        after_offset: Natural<0, 268435456> => "afterOffset",
        chunk_bytes: Natural<1, 65536> => "chunkBytes",
        first_offset: Natural<0, 268435456> => "firstOffset",
        rows: Natural<1, 8192> => "rows",
} }

record! { ClientActionMutateCallerReplacement {
        project_id: RawJson => "projectId",
        source: RawJson => "source",
} }

tagged! { ClientActionDownloadOriginalTarget("kind") {
    RetainedFile => "retained-file" {

    },
    InventoryPath => "inventory-path" {
        path: SourcePath => "path",
    },
} }

literal! { ClientActionSubmitExecutionExecutionMode => "typed" }

literal! { ClientActionBeginLocalEvaluationExecutionMode => "typed" }

words! { ClientActionAwaitNativeBoundaryBoundary {
    CatalogPending => "catalog-pending",
    Initialized => "initialized",
    WorkspaceSelected => "workspace-selected",
    InspectionPending => "inspection-pending",
    ModelOpenSettled => "model-open-settled",
} }

text! { ClientActionBindNativeProjectProjectId { min: 0, max: unbounded, pattern: "^[a-zA-Z0-9_.-]{1,128}$" } }

words! { ClientActionBeginConnectedOpeningScope {
    Primary => "primary",
    Complete => "complete",
} }

words! { ClientActionBeginConnectedOpeningSemantic {
    None => "none",
    Projection => "projection",
} }

words! { ClientActionAwaitConnectedBoundaryBoundary {
    InspectionPending => "inspection-pending",
    OpeningSettled => "opening-settled",
} }

// Private additive identity input; exact UI strings, no normalization.
literal! { IdentityPersistence => "session" }
record! { IdentitySourceSnapshot {
    provider_id: Text<0, {usize::MAX}> => "providerId",
    locator: Text<0, {usize::MAX}> => "locator",
    display_name: Text<0, {usize::MAX}> => "displayName",
} optional { persistence: IdentityPersistence => "persistence" } }
tagged! { IdentitySubject("kind") {
    SourceKey => "source-key" {
        source_snapshot: IdentitySourceSnapshot => "sourceSnapshot",
    },
    ProjectKey => "project-key" {
        source_snapshot: IdentitySourceSnapshot => "sourceSnapshot",
        relative_path: Text<0, {usize::MAX}> => "relativePath",
    },
} }

tagged! { ClientAction("kind") {
    ObserveIdentity => "observe-identity" { sample: FixtureAlias => "sample", subject: IdentitySubject => "subject" },
    InitializeExecutionRuntime => "initialize-execution-runtime" {
        attempt: FixtureAlias => "attempt",
    },
    StartImport => "start-import" {
        attempt: FixtureAlias => "attempt",
        codec: ModelCodec => "codec",
        filename: Text<0, 4096> => "filename",
        via: ClientActionStartImportVia => "via",
    },
    StartConnected => "start-connected" {
        attempt: FixtureAlias => "attempt",
        project_id: Text<0, 12288> => "projectId",
        scope: ClientActionStartConnectedScope => "scope",
        semantic: ClientActionStartConnectedSemantic => "semantic",
        source: SourceIdentity => "source",
    },
    BindModelOwner => "bind-model-owner" {
        attempt: FixtureAlias => "attempt",
        model: FixtureAlias => "model",
    },
    ExecutePendingCore => "execute-pending-core" {
        effect: EffectRef => "effect",
    },
    PreparePendingCore => "prepare-pending-core" {
        effect: EffectRef => "effect",
    },
    SettlePreparedCore => "settle-prepared-core" {
        effect: EffectRef => "effect",
    },
    Deliver => "deliver" {
        effect: EffectRef => "effect",
        reply: DeliveredReply => "reply",
    },
    Reject => "reject" {
        effect: EffectRef => "effect",
        error: RejectedEffect => "error",
    },
    ReadRun => "read-run" {
        attempt: FixtureAlias => "attempt",
        effect_kind: ClientActionReadRunEffectKind => "effectKind",
        expected_request: ClientActionReadRunExpectedRequest => "expectedRequest",
        first_ordinal: Natural<0, 8191> => "firstOrdinal",
        reply_parts: Items<ReadRunPart, 1, 32> => "replyParts",
        source: FixtureAlias => "source",
        window: ClientActionReadRunWindow => "window",
    },
    SignalPicker => "signal-picker" {
        effect: EffectRef => "effect",
        signal: PickerSignal => "signal",
    },
    CancelOpening => "cancel-opening" {
        attempt: FixtureAlias => "attempt",
    },
    MutateCaller => "mutate-caller" {
        attempt: FixtureAlias => "attempt",
        replacement: ClientActionMutateCallerReplacement => "replacement",
    },
    Inspect => "inspect" {
        model: FixtureAlias => "model",
        query: Text<0, 4096> => "query",
    },
    Search => "search" {
        model: FixtureAlias => "model",
        query: Text<0, 4096> => "query",
    },
    ConceptualSpecification => "conceptual-specification" {
        model: FixtureAlias => "model",
        query: Text<0, 4096> => "query",
    },
    DownloadOriginal => "download-original" {
        model: FixtureAlias => "model",
        target: ClientActionDownloadOriginalTarget => "target",
    },
    DownloadArchive => "download-archive" {
        model: FixtureAlias => "model",
    },
    CloseModel => "close-model" {
        model: FixtureAlias => "model",
    },
    CloseCurrentModel => "close-current-model" {

    },
    ReplaceModel => "replace-model" {
        incoming: FixtureAlias => "incoming",
        model: FixtureAlias => "model",
    },
    SubmitExecution => "submit-execution" {
        arguments: RawJsonSource => "arguments",
        entry: Text<0, 4096> => "entry",
        execution: FixtureAlias => "execution",
        execution_mode: ClientActionSubmitExecutionExecutionMode => "executionMode",
        model: FixtureAlias => "model",
    },
    ReleaseExecution => "release-execution" {
        execution: FixtureAlias => "execution",
    },
    Checkpoint => "checkpoint" {
        name: FixtureAlias => "name",
    },
    SelectCurrentDeclaration => "select-current-declaration" {
        key: Text<1, 16000> => "key",
        model: FixtureAlias => "model",
    },
    SearchCurrent => "search-current" {
        query: Text<0, 16000> => "query",
    },
    BeginLocalEvaluation => "begin-local-evaluation" {
        arguments: RawJson => "arguments",
        attempt: FixtureAlias => "attempt",
        entry: Text<1, 16000> => "entry",
        execution_mode: ClientActionBeginLocalEvaluationExecutionMode => "executionMode",
        model: FixtureAlias => "model",
        pending: FixtureAlias => "pending",
    },
    AwaitLocalEvaluation => "await-local-evaluation" {
        pending: FixtureAlias => "pending",
    },
    BeginNativeInitialize => "begin-native-initialize" {
        pending: FixtureAlias => "pending",
        runtime: FixtureAlias => "runtime",
    },
    BeginNativeChoose => "begin-native-choose" {
        pending: FixtureAlias => "pending",
        runtime: FixtureAlias => "runtime",
    },
    AwaitNativeBoundary => "await-native-boundary" {
        boundary: ClientActionAwaitNativeBoundaryBoundary => "boundary",
        pending: FixtureAlias => "pending",
    },
    BindNativeProject => "bind-native-project" {
        choice: FixtureAlias => "choice",
        project: FixtureAlias => "project",
        project_id: ClientActionBindNativeProjectProjectId => "projectId",
    },
    BeginNativeOpenProject => "begin-native-open-project" {
        attempt: FixtureAlias => "attempt",
        pending: FixtureAlias => "pending",
        project: FixtureAlias => "project",
        runtime: FixtureAlias => "runtime",
    },
    DisposeNativeRuntime => "dispose-native-runtime" {
        runtime: FixtureAlias => "runtime",
    },
    AwaitNativeDisposal => "await-native-disposal" {
        runtime: FixtureAlias => "runtime",
    },
    BeginConnectedOpening => "begin-connected-opening" {
        attempt: FixtureAlias => "attempt",
        pending: FixtureAlias => "pending",
        project_id: Text<0, 12288> => "projectId",
        scope: ClientActionBeginConnectedOpeningScope => "scope",
        semantic: ClientActionBeginConnectedOpeningSemantic => "semantic",
        source: SourceIdentity => "source",
        transfer_limits: ConnectedTransferLimits => "transferLimits",
    },
    AwaitConnectedBoundary => "await-connected-boundary" {
        boundary: ClientActionAwaitConnectedBoundaryBoundary => "boundary",
        pending: FixtureAlias => "pending",
    },
    DisposeConnectedOpening => "dispose-connected-opening" {
        pending: FixtureAlias => "pending",
    },
    AwaitConnectedDisposal => "await-connected-disposal" {
        pending: FixtureAlias => "pending",
    },
} }

record! { ClientFixtureFilesItem {
        alias: FixtureAlias => "alias",
        bytes: Bytes => "bytes",
} }

record! { ClientFixtureLiteralPeersItem {
        alias: FixtureAlias => "alias",
        frames: Items<Frame, 0, 4096> => "frames",
} optional {
        requests: Items<Frame, 0, 4096> => "requests",
} }

record! { ClientFixture {
        files: Items<ClientFixtureFilesItem, 0, 256> => "files",
        literal_peers: Items<ClientFixtureLiteralPeersItem, 0, 64> => "literalPeers",
} optional {
        runtime: ClientRuntime => "runtime",
} }

literal! { ClientRuntimeControlledModelOriginalsHttpV1ManifestPath => "/api/session" }

record! { ClientRuntimeControlledModelOriginalsHttpV1Manifest {
        body: Frame => "body",
        path: ClientRuntimeControlledModelOriginalsHttpV1ManifestPath => "path",
        status: Natural<200, 599> => "status",
} }

literal! { ClientRuntimeControlledNativeWorkspaceV1EntryUrl => "https://proton.localhost/" }

literal! { ClientRuntimeControlledNativeWorkspaceV1Mapping => "capability-checks" }

tagged! { ClientRuntime("kind") {
    ControlledHttpExecutions => "controlled-http-executions" {
        peer: FixtureAlias => "peer",
        session_id: Text<0, 128> => "sessionId",
    },
    ControlledModelOriginalsHttpV1 => "controlled-model-originals-http-v1" {
        manifest: ClientRuntimeControlledModelOriginalsHttpV1Manifest => "manifest",
        manifest_byte_limit: Natural<1, 131072> => "manifestByteLimit",
        peer: FixtureAlias => "peer",
    },
    ControlledNativeWorkspaceV1 => "controlled-native-workspace-v1" {
        entry_url: ClientRuntimeControlledNativeWorkspaceV1EntryUrl => "entryUrl",
        mapping: ClientRuntimeControlledNativeWorkspaceV1Mapping => "mapping",
        peer: FixtureAlias => "peer",
        runtime: FixtureAlias => "runtime",
    },
} }

words! { ConfigPolicy {
    ProjectOnly => "project-only",
    ProjectAndUsers => "project-and-users",
    AmbientCurrent => "ambient-current",
} }

record! { ConnectedTransferLimits {
        inventory_max_entries: Natural<1, 256> => "inventoryMaxEntries",
        read_max_bytes: Natural<1, 65536> => "readMaxBytes",
} }

pub(super) type Count = Natural<0, 9007199254740991>;

words! { DeliveredReplyTextOperation {
    ExecutionNativeDescriptor => "execution.native-descriptor",
    ExecutionNativeRequest => "execution.native-request",
} }

words! { DeliveredReplyVoidOperation {
    AdapterCancelModelOpen => "adapter.cancel-model-open",
    AdapterCancel => "adapter.cancel",
} }

tagged! { DeliveredReply("kind") {
    Frame => "frame" {
        value: Frame => "value",
    },
    Bytes => "bytes" {
        value: Bytes => "value",
    },
    Json => "json" {
        operation: JsonDeliveryOperation => "operation",
        source: RawJsonSource => "source",
    },
    Text => "text" {
        operation: DeliveredReplyTextOperation => "operation",
        source: RawJsonSource => "source",
    },
    Sha256 => "sha256" {
        value: ContentSha256 => "value",
    },
    FileSelection => "file-selection" {
        file: FixtureAlias => "file",
    },
    PickerCancelled => "picker-cancelled" {

    },
    Void => "void" {
        operation: DeliveredReplyVoidOperation => "operation",
    },
} }

words! { EffectKind {
    Picker => "picker",
    FileRead => "file-read",
    NativeCapture => "native-capture",
    Initialize => "initialize",
    Capture => "capture",
    Inventory => "inventory",
    ReadOriginal => "read-original",
    ReadProjection => "read-projection",
    Release => "release",
    Digest => "digest",
    Inspection => "inspection",
    ExecutionSubmit => "execution-submit",
    ExecutionObserve => "execution-observe",
    ExecutionRelease => "execution-release",
    LocalEvaluation => "local-evaluation",
    Catalog => "catalog",
    NativeInvoke => "native-invoke",
    ManifestFetch => "manifest-fetch",
    WorkspaceOpen => "workspace-open",
} }

record! { EffectRef {
        attempt: FixtureAlias => "attempt",
        kind: EffectKind => "kind",
        ordinal: Natural<0, 8191> => "ordinal",
} }

tagged! { Entry("kind") {
    File => "file" {
        bytes: Bytes => "bytes",
        path: SourcePath => "path",
    },
    Directory => "directory" {
        path: SourcePath => "path",
    },
} }

tagged! { Frame("kind") {
    Literal => "literal" {
        text: Text<0, 1048576> => "text",
    },
    Segments => "segments" {
        parts: Items<FramePart, 1, 4096> => "parts",
    },
} }

tagged! { FramePart("kind") {
    Literal => "literal" {
        text: Text<0, 1048576> => "text",
    },
    Repeat => "repeat" {
        count: Count => "count",
        text: Text<0, 16384> => "text",
    },
} }

literal! { GuestKind => "maintained-workspace-mep" }

record! { Guest {
        alias: FixtureAlias => "alias",
        answers: RawJsonSource => "answers",
        initialize: RawJsonSource => "initialize",
        kind: GuestKind => "kind",
} }

words! { HostActionAwaitBoundaryCaptureAt {
    SharedLockWaiting => "shared-lock-waiting",
    SharedLockAcquired => "shared-lock-acquired",
    BeforeSourceCopy => "before-source-copy",
    AllSelectedCopiesComplete => "all-selected-copies-complete",
    CaptureWorkExited => "capture-work-exited",
} }

literal! { HostActionAwaitBoundaryCaptureOwnerKind => "pending-capture" }

record! { HostActionAwaitBoundaryCaptureOwner {
        kind: HostActionAwaitBoundaryCaptureOwnerKind => "kind",
        pending: FixtureAlias => "pending",
} }

words! { HostActionAwaitBoundaryWriterAt {
    ExclusiveLockWaiting => "exclusive-lock-waiting",
    ExclusiveLockAcquired => "exclusive-lock-acquired",
    BeforeRecordPublication => "before-record-publication",
    WriterWorkExited => "writer-work-exited",
} }

literal! { HostActionAwaitBoundaryWriterOwnerKind => "cooperating-writer" }

record! { HostActionAwaitBoundaryWriterOwner {
        kind: HostActionAwaitBoundaryWriterOwnerKind => "kind",
        writer: FixtureAlias => "writer",
} }

nested_tagged! { HostActionAwaitBoundary("kind" => "await-boundary"; "owner", "kind") {
    Capture => "pending-capture" {
        at: HostActionAwaitBoundaryCaptureAt => "at",
        owner: HostActionAwaitBoundaryCaptureOwner => "owner",
    },
    Writer => "cooperating-writer" {
        at: HostActionAwaitBoundaryWriterAt => "at",
        owner: HostActionAwaitBoundaryWriterOwner => "owner",
    },
} }

words! { HostActionConnectAuthentication {
    Valid => "valid",
    Missing => "missing",
    WrongToken => "wrong-token",
    ForeignOrigin => "foreign-origin",
    ForeignHost => "foreign-host",
} }

words! { HostActionCaptureSelectedScope {
    Primary => "primary",
    Complete => "complete",
} }

words! { HostActionCaptureSelectedSemantic {
    None => "none",
    Projection => "projection",
} }

tagged! { HostActionReadSelectedTarget("kind") {
    OriginalEntry => "original-entry" {
        path: SourcePath => "path",
    },
    SemanticProjection => "semantic-projection" {

    },
} }

words! { HostActionBeginCaptureSelectedScope {
    Primary => "primary",
    Complete => "complete",
} }

words! { HostActionBeginCaptureSelectedSemantic {
    None => "none",
    Projection => "projection",
} }

words! { HostActionHoldCooperatingCompileAt {
    ExclusiveLockAcquired => "exclusive-lock-acquired",
    BeforeRecordPublication => "before-record-publication",
} }

words! { HostActionProducerMessageBoundaryStage {
    IngressRequest => "ingress-request",
    EgressReply => "egress-reply",
} }

tagged! { HostAction("kind") {
    Connect => "connect" {
        authentication: HostActionConnectAuthentication => "authentication",
        connection: FixtureAlias => "connection",
    },
    Discover => "discover" {
        connection: FixtureAlias => "connection",
        provider: FixtureAlias => "provider",
    },
    CaptureSelected => "capture-selected" {
        attempt: FixtureAlias => "attempt",
        capture: FixtureAlias => "capture",
        connection: FixtureAlias => "connection",
        project: FixtureAlias => "project",
        provider: FixtureAlias => "provider",
        request_id: U64Token => "requestId",
        scope: HostActionCaptureSelectedScope => "scope",
        semantic: HostActionCaptureSelectedSemantic => "semantic",
    },
    Inventory => "inventory" {
        capture: FixtureAlias => "capture",
        connection: FixtureAlias => "connection",
        max_entries: Natural<1, 256> => "maxEntries",
        request_id: U64Token => "requestId",
        start_index: Count => "startIndex",
    },
    ReadSelected => "read-selected" {
        capture: FixtureAlias => "capture",
        connection: FixtureAlias => "connection",
        max_bytes: Natural<1, 65536> => "maxBytes",
        offset: Count => "offset",
        request_id: U64Token => "requestId",
        target: HostActionReadSelectedTarget => "target",
    },
    Release => "release" {
        capture: FixtureAlias => "capture",
        connection: FixtureAlias => "connection",
        request_id: U64Token => "requestId",
    },
    Send => "send" {
        connection: FixtureAlias => "connection",
        frame: Frame => "frame",
    },
    Hold => "hold" {
        at: HostBoundary => "at",
        attempt: FixtureAlias => "attempt",
    },
    Continue => "continue" {
        attempt: FixtureAlias => "attempt",
    },
    Disconnect => "disconnect" {
        connection: FixtureAlias => "connection",
    },
    AdvanceDeadline => "advance-deadline" {
        milliseconds: Natural<0, 30001> => "milliseconds",
    },
    RemoveProvider => "remove-provider" {
        provider: FixtureAlias => "provider",
    },
    ReofferSameLabels => "reoffer-same-labels" {
        provider: FixtureAlias => "provider",
    },
    ReplaceProject => "replace-project" {
        grant: FixtureAlias => "grant",
        replacement: FixtureAlias => "replacement",
    },
    ReplaceOutput => "replace-output" {
        grant: FixtureAlias => "grant",
        replacement: FixtureAlias => "replacement",
    },
    StartCooperatingCompile => "start-cooperating-compile" {
        grant: FixtureAlias => "grant",
        next_entries: Items<Entry, 0, 4096> => "nextEntries",
        next_record: Frame => "nextRecord",
        writer: FixtureAlias => "writer",
    },
    AwaitCooperatingCompile => "await-cooperating-compile" {
        writer: FixtureAlias => "writer",
    },
    UncooperativeWrite => "uncooperative-write" {
        entry: Entry => "entry",
        grant: FixtureAlias => "grant",
    },
    Checkpoint => "checkpoint" {
        name: FixtureAlias => "name",
    },
    BeginCaptureSelected => "begin-capture-selected" {
        attempt: FixtureAlias => "attempt",
        capture: FixtureAlias => "capture",
        connection: FixtureAlias => "connection",
        pending: FixtureAlias => "pending",
        project: FixtureAlias => "project",
        provider: FixtureAlias => "provider",
        request_id: U64Token => "requestId",
        scope: HostActionBeginCaptureSelectedScope => "scope",
        semantic: HostActionBeginCaptureSelectedSemantic => "semantic",
    },
    AwaitCapture => "await-capture" {
        pending: FixtureAlias => "pending",
    },
    HoldCooperatingCompile => "hold-cooperating-compile" {
        at: HostActionHoldCooperatingCompileAt => "at",
        writer: FixtureAlias => "writer",
    },
    ContinueCooperatingCompile => "continue-cooperating-compile" {
        writer: FixtureAlias => "writer",
    },
    OpenLegacySelected => "open-legacy-selected" {
        connection: FixtureAlias => "connection",
        project: FixtureAlias => "project",
        provider: FixtureAlias => "provider",
        request_id: U64Token => "requestId",
    },
    ProducerMessageBoundary => "producer-message-boundary" {
        connection: FixtureAlias => "connection",
        frame: Frame => "frame",
        probe: FixtureAlias => "probe",
        stage: HostActionProducerMessageBoundaryStage => "stage",
    },
} delegates {
    AwaitBoundary => "await-boundary": HostActionAwaitBoundary,
} }

words! { HostBoundary {
    BeforeDiscovery => "before-discovery",
    AfterDiscovery => "after-discovery",
    AfterOutputResolution => "after-output-resolution",
    RecordLocked => "record-locked",
    BeforeSourceCopy => "before-source-copy",
    AfterSourceCopy => "after-source-copy",
    BeforeHeader => "before-header",
    BeforeProjection => "before-projection",
    BeforeAuthorityRecheck => "before-authority-recheck",
    PreparedBeforePublication => "prepared-before-publication",
    AfterReady => "after-ready",
    WorkerBeforeExit => "worker-before-exit",
} }

record! { HostFixtureGrantsItem {
        alias: FixtureAlias => "alias",
        nodes: Items<HostNode, 0, 4096> => "nodes",
} }

record! { HostFixtureRecordsItem {
        grant: FixtureAlias => "grant",
        module: Text<0, 4096> => "module",
        raw: Frame => "raw",
} }

tagged! { HostFixtureStartupOutputOverride("kind") {
    None => "none" {

    },
    Explicit => "explicit" {
        grant: FixtureAlias => "grant",
    },
} }

record! { HostFixtureStartup {
        cwd: FixtureAlias => "cwd",
        output_override: HostFixtureStartupOutputOverride => "outputOverride",
} }

record! { HostFixture {
        grants: Items<HostFixtureGrantsItem, 0, 128> => "grants",
        guests: Items<Guest, 0, 64> => "guests",
        providers: Items<Provider, 0, 64> => "providers",
        records: Items<HostFixtureRecordsItem, 0, 128> => "records",
        startup: HostFixtureStartup => "startup",
} }

tagged! { HostNodeEntrySeriesEntry("kind") {
    Directory => "directory" {

    },
    File => "file" {
        bytes: AtomicBytes => "bytes",
    },
} }

tagged! { HostNode("kind") {
    File => "file" {
        bytes: Bytes => "bytes",
        path: SourcePath => "path",
    },
    Directory => "directory" {
        path: SourcePath => "path",
    },
    Symlink => "symlink" {
        path: SourcePath => "path",
        target: Text<0, 12288> => "target",
    },
    Fifo => "fifo" {
        path: SourcePath => "path",
    },
    Socket => "socket" {
        path: SourcePath => "path",
    },
    RawNameFile => "raw-name-file" {
        bytes: Bytes => "bytes",
        name_bytes: Bytes => "nameBytes",
        parent: Text<0, 4096> => "parent",
    },
    EntrySeries => "entry-series" {
        count: Natural<0, 100065> => "count",
        decimal_width: Natural<0, 20> => "decimalWidth",
        entry: HostNodeEntrySeriesEntry => "entry",
        first: Count => "first",
        parent: Text<0, 4096> => "parent",
        prefix: Text<0, 1024> => "prefix",
        suffix: Text<0, 1024> => "suffix",
    },
} }

words! { JsonDeliveryOperation {
    AdapterInitialize => "adapter.initialize",
    AdapterExecute => "adapter.execute",
    WorkerMessage => "worker.message",
    ExecutionTransportResponse => "execution.transport-response",
    NativeWorkspaceOpen => "native.workspace.open",
    NativeWorkspaceRead => "native.workspace.read",
    NativeWorkspaceRelease => "native.workspace.release",
    NativeWorkspaceChoose => "native.workspace.choose",
    NativeWorkspaceRevoke => "native.workspace.revoke",
} }

literal! { LimitsCorpusBytes => 16777216 }

literal! { LimitsEvents => 8192 }

literal! { LimitsEvidenceBytes => 4194304 }

literal! { LimitsInputBytes => 1048576 }

literal! { LimitsObservationsBytes => 16777216 }

literal! { LimitsReportBytes => 33554432 }

record! { Limits {
        actions: Count => "actions",
        corpus_bytes: LimitsCorpusBytes => "corpusBytes",
        events: LimitsEvents => "events",
        evidence_bytes: LimitsEvidenceBytes => "evidenceBytes",
        expanded_decoded_and_read_bytes: Count => "expandedDecodedAndReadBytes",
        expanded_wire_bytes: Count => "expandedWireBytes",
        input_bytes: LimitsInputBytes => "inputBytes",
        ledger_effect_history_entries: Count => "ledgerEffectHistoryEntries",
        ledger_event_history_entries: Count => "ledgerEventHistoryEntries",
        ledger_held_result_bytes: Count => "ledgerHeldResultBytes",
        ledger_payload_comparison_byte_visits: Count => "ledgerPayloadComparisonByteVisits",
        ledger_produced_result_bytes: Count => "ledgerProducedResultBytes",
        metadata_bytes: Count => "metadataBytes",
        observations_bytes: LimitsObservationsBytes => "observationsBytes",
        observer_byte_visits: Count => "observerByteVisits",
        report_bytes: LimitsReportBytes => "reportBytes",
} }

words! { ModelCodec {
    MorphirJson => "morphir-json",
    IonText => "ion-text",
    IonBinary => "ion-binary",
} }

words! { PacketRefPacket {
    Original60 => "original60",
    Inventory35 => "inventory35",
    Wire49 => "wire49",
    Discovery7 => "discovery7",
    Additive => "additive",
} }

record! { PacketRef {
        id: Text<0, 256> => "id",
        packet: PacketRefPacket => "packet",
        sha256: ContentSha256 => "sha256",
} }

tagged! { PickerSignal("kind") {
    FileSelection => "file-selection" {
        file: FixtureAlias => "file",
    },
    PickerCancelEvent => "picker-cancel-event" {

    },
    EmptySelection => "empty-selection" {

    },
} }

record! { ProjectBinding {
        alias: FixtureAlias => "alias",
        module: Text<0, 4096> => "module",
} }

tagged! { Provider("kind") {
    Native => "native" {
        alias: FixtureAlias => "alias",
        config_policy: ConfigPolicy => "configPolicy",
        grant: FixtureAlias => "grant",
        locator: Text<0, 4096> => "locator",
        projects: Items<ProjectBinding, 1, 64> => "projects",
    },
    Installed => "installed" {
        alias: FixtureAlias => "alias",
        config_policy: ConfigPolicy => "configPolicy",
        grant: FixtureAlias => "grant",
        guest: FixtureAlias => "guest",
        locator: Text<0, 4096> => "locator",
        projects: Items<ProjectBinding, 1, 64> => "projects",
    },
} }

kind! { RawJsonSource { String(RawJson), Object(Frame) } }

words! { ReadRunEffectKind {
    ReadOriginal => "read-original",
    ReadProjection => "read-projection",
} }

literal! { ReadRunExpectedRequestContractVersion => "0.1.0-draft.1" }

literal! { ReadRunExpectedRequestMethod => "morphir.model-originals.read" }

record! { ReadRunExpectedRequest {
        capture_id: Text<0, 128> => "captureId",
        contract_version: ReadRunExpectedRequestContractVersion => "contractVersion",
        max_bytes: Natural<1, 65536> => "maxBytes",
        method: ReadRunExpectedRequestMethod => "method",
        target: ReadTarget => "target",
} }

literal! { ReadRunKind => "read-run" }

record! { ReadRunWindow {
        after_offset: Natural<0, 268435456> => "afterOffset",
        chunk_bytes: Natural<1, 65536> => "chunkBytes",
        first_offset: Natural<0, 268435456> => "firstOffset",
        rows: Natural<1, 8192> => "rows",
} }

record! { ReadRun {
        attempt: FixtureAlias => "attempt",
        effect_kind: ReadRunEffectKind => "effectKind",
        expected_request: ReadRunExpectedRequest => "expectedRequest",
        first_ordinal: Natural<0, 8191> => "firstOrdinal",
        kind: ReadRunKind => "kind",
        reply_parts: Items<ReadRunPart, 1, 32> => "replyParts",
        source: FixtureAlias => "source",
        window: ReadRunWindow => "window",
} }

tagged! { ReadRunPart("kind") {
    Literal => "literal" {
        text: Text<0, 16384> => "text",
    },
    CorrelatedRequestId => "correlated-request-id" {

    },
    RowOffset => "row-offset" {

    },
    RowNextOffset => "row-next-offset" {

    },
    Base64Window => "base64-window" {

    },
} }

tagged! { ReadTarget("kind") {
    Original => "original" {
        entry_id: Text<0, 128> => "entryId",
    },
    SemanticProjection => "semantic-projection" {

    },
} }

literal! { RejectedEffectKind => "error" }

words! { RejectedEffectName {
    Error => "Error",
    TypeError => "TypeError",
    AbortError => "AbortError",
} }

record! { RejectedEffect {
        kind: RejectedEffectKind => "kind",
        message: Text<0, 512> => "message",
        name: RejectedEffectName => "name",
} }

tagged! { Run("role") {
    ModelOriginalsServer => "model-originals-server" {
        actions: Items<HostAction, 1, 8192> => "actions",
        fixture: HostFixture => "fixture",
    },
    ModelOriginalsClient => "model-originals-client" {
        actions: Items<ClientAction, 1, 8192> => "actions",
        fixture: ClientFixture => "fixture",
    },
} }

record! { Scenario {
        limits: Limits => "limits",
        origin: PacketRef => "origin",
        runs: Items<Run, 1, 2> => "runs",
} }

record! { SourceIdentity {
        locator: Text<0, 4096> => "locator",
        provider_id: Text<0, 128> => "providerId",
} }

pub(super) type U8 = Natural<0, 255>;
