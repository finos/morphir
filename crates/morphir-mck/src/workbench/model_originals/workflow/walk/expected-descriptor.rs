// Generated private descriptor from frozen expectedV17. No serde::Value fallback.
// Root supplies macros and common validated leaves. All fields are required and closed.
// Tagged macros validate/consume the required discriminator, which is excluded from payload.
// `unbounded` / usize::MAX preserves absent schema maximum; actual cumulative budgets still apply.
// Source/receipt and every generated schema node are bound in translation.json.

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

words! { CancellationCause {
    CancelOpening => "cancel-opening",
    CloseCurrentModel => "close-current-model",
    CloseModel => "close-model",
    Replacement => "replacement",
    Teardown => "teardown",
} }

literal! { CaptureCoverageCompleteDeclaration => "0.1.0-draft.1" }

tagged! { CaptureCoverage("kind") {
    Primary => "primary" {

    },
    Complete => "complete" {
        declaration: CaptureCoverageCompleteDeclaration => "declaration",
    },
} }

pub(super) type Count = Natural<0, 9007199254740991>;

words! { CountCheckRole {
    Slots => "slots",
    ActiveWorkers => "activeWorkers",
    SourceBytes => "sourceBytes",
    ProjectionBytes => "projectionBytes",
    MetadataBytes => "metadataBytes",
    RecordBytes => "recordBytes",
    Discovery => "discovery",
    ProjectResolution => "projectResolution",
    OutputResolution => "outputResolution",
    RecordReads => "recordReads",
    SourceReads => "sourceReads",
    ProjectionAttempts => "projectionAttempts",
    CompileCalls => "compileCalls",
    LegacyOpenCalls => "legacyOpenCalls",
    WorkersStarted => "workersStarted",
    WorkersExited => "workersExited",
    StillOwnedWorkers => "stillOwnedWorkers",
    LatePublications => "latePublications",
} }

record! { CountCheck {
        expected: NumberRequirement => "expected",
        role: CountCheckRole => "role",
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

record! { ExchangeRef {
        connection: FixtureAlias => "connection",
        request_id: U64Token => "requestId",
} }

words! { ExecutionOwnerRetainedPhase {
    Pending => "pending",
    Unknown => "unknown",
    Running => "running",
    TerminalUnreleased => "terminal-unreleased",
    Disconnected => "disconnected",
} }

tagged! { ExecutionOwner("kind") {
    None => "none" {

    },
    Retained => "retained" {
        execution: FixtureAlias => "execution",
        model: FixtureAlias => "model",
        phase: ExecutionOwnerRetainedPhase => "phase",
    },
} }

tagged! { ExpectedBinding("kind") {
    DiscoveredServerSelection => "discovered-server-selection" {
        alias: FixtureAlias => "alias",
        connection: FixtureAlias => "connection",
        project: FixtureAlias => "project",
        provider: FixtureAlias => "provider",
    },
    LiteralClientInput => "literal-client-input" {
        alias: FixtureAlias => "alias",
        locator: Text<0, 4096> => "locator",
        project_id: Text<0, 12288> => "projectId",
        provider_id: Text<0, 128> => "providerId",
        session_id: Text<0, 128> => "sessionId",
    },
    RetainedModelFromAttempt => "retained-model-from-attempt" {
        alias: FixtureAlias => "alias",
        attempt: FixtureAlias => "attempt",
        model: FixtureAlias => "model",
    },
} }

record! { ExpectedByteSource {
        alias: FixtureAlias => "alias",
        byte_length: Count => "byteLength",
        bytes: Bytes => "bytes",
        sha256: ContentSha256 => "sha256",
} }

tagged! { ExpectedCleanupOwnConnectionClosedCapture("kind") {
    Unknown => "unknown" {

    },
    Known => "known" {
        capture: FixtureAlias => "capture",
    },
} }

tagged! { ExpectedCleanup("kind") {
    None => "none" {

    },
    ReleaseConfirmed => "release-confirmed" {
        attempt: FixtureAlias => "attempt",
        capture: FixtureAlias => "capture",
        connection: FixtureAlias => "connection",
        request_id: U64Token => "requestId",
    },
    OwnConnectionClosed => "own-connection-closed" {
        attempt: FixtureAlias => "attempt",
        capture: ExpectedCleanupOwnConnectionClosedCapture => "capture",
        connection: FixtureAlias => "connection",
    },
} }

tagged! { ExpectedClientCheckDownloadTarget("kind") {
    RetainedFile => "retained-file" {

    },
    InventoryPath => "inventory-path" {
        path: SourcePath => "path",
    },
} }

tagged! { ExpectedClientCheckRichOwnerGraph("kind") {
    Absent => "absent" {

    },
    Retained => "retained" {
        expected_rich: FixtureAlias => "expectedRich",
    },
} }

pub(super) type ExpectedClientCheckNavigationInspectionOwner = Nullable<FixtureAlias>;

pub(super) type ExpectedClientCheckNavigationOutputOwner = Nullable<FixtureAlias>;

pub(super) type ExpectedClientCheckNavigationSearchOwner = Nullable<FixtureAlias>;

tagged! { ExpectedClientCheckLocalExplorerStateCurrent("kind") {
    None => "none" {

    },
    Model => "model" {
        model: FixtureAlias => "model",
    },
} }

words! { ExpectedClientCheckLocalExplorerStateHistory {
    ContainsSelectedDeclaration => "contains-selected-declaration",
    NoDeclarationDestinations => "no-declaration-destinations",
} }

tagged! { ExpectedClientCheckLocalExplorerStateInspection("kind") {
    None => "none" {

    },
    ActualInspectionResult => "actual-inspection-result" {
        effect: EffectRef => "effect",
        model: FixtureAlias => "model",
    },
} }

pub(super) type ExpectedClientCheckLocalExplorerStateSelectedKey = Nullable<Text<0, 16000>>;

literal! { ExpectedClientCheckLocalEvaluationStateHostRetention => "none" }

tagged! { ExpectedClientCheckLocalEvaluationStateResult("kind") {
    None => "none" {

    },
    ActualCoreResult => "actual-core-result" {
        effect: EffectRef => "effect",
        model: FixtureAlias => "model",
    },
} }

tagged! { ExpectedClientCheckNativeTranscriptExchangesItemCapabilityCheck("kind") {
    ActualCompiledPolicyCore => "actual-compiled-policy-core" {
        expected_result_raw_json: RawJson => "expectedResultRawJson",
    },
    NotCalledByProductionDispose => "not-called-by-production-dispose" {

    },
} }

record! { ExpectedClientCheckNativeTranscriptExchangesItem {
        capability_check: ExpectedClientCheckNativeTranscriptExchangesItemCapabilityCheck => "admission",
        ordinal: Count => "ordinal",
        reply_raw_json: RawJson => "replyRawJson",
        request_raw_json: RawJson => "requestRawJson",
} }

literal! { ExpectedClientCheckNativeTranscriptNumberComparison => "exact-token" }

literal! { ExpectedClientCheckNativeOpenReleaseOrderSourceCodec => "morphir-json" }

literal! { ExpectedClientCheckNativeOpenReleaseOrderSourceHeader => "4.0.0" }

literal! { ExpectedClientCheckNativeWorkspaceOwnerStateExecutionOwner => "none" }

text! { ExpectedClientCheckNativeWorkspaceOwnerStateGrantId { min: 0, max: unbounded, pattern: "^[a-zA-Z0-9_.-]{1,128}$" } }

tagged! { ExpectedClientCheckNativeWorkspaceOwnerStateModelAuthority("kind") {
    None => "none" {

    },
    ActualRetainedOwner => "actual-retained-owner" {
        model: FixtureAlias => "model",
    },
} }

record! { ExpectedClientCheckConnectedTranscriptExchangesItem {
        effect: EffectRef => "effect",
        reply_raw_json: RawJson => "replyRawJson",
        request_id_token: U64Token => "requestIdToken",
        request_raw_json: RawJson => "requestRawJson",
} }

literal! { ExpectedClientCheckConnectedTranscriptManifestCache => "no-store" }

literal! { ExpectedClientCheckConnectedTranscriptManifestCredentials => "same-origin" }

literal! { ExpectedClientCheckConnectedTranscriptManifestMethod => "GET" }

literal! { ExpectedClientCheckConnectedTranscriptManifestPath => "/api/session" }

literal! { ExpectedClientCheckConnectedTranscriptManifestRedirect => "error" }

literal! { ExpectedClientCheckConnectedTranscriptManifestStatus => 200 }

record! { ExpectedClientCheckConnectedTranscriptManifest {
        cache: ExpectedClientCheckConnectedTranscriptManifestCache => "cache",
        credentials: ExpectedClientCheckConnectedTranscriptManifestCredentials => "credentials",
        expected_bytes: FixtureAlias => "expectedBytes",
        method: ExpectedClientCheckConnectedTranscriptManifestMethod => "method",
        path: ExpectedClientCheckConnectedTranscriptManifestPath => "path",
        redirect: ExpectedClientCheckConnectedTranscriptManifestRedirect => "redirect",
        status: ExpectedClientCheckConnectedTranscriptManifestStatus => "status",
} }

literal! { ExpectedClientCheckConnectedTranscriptNumberComparison => "exact-token" }

literal! { ExpectedClientCheckConnectedTranscriptWebSocketPath => "/rpc" }

record! { ExpectedClientCheckConnectedOpeningTransferOriginRecord {
        descriptor: ExpectedDescriptor => "descriptor",
        expected_bytes: FixtureAlias => "expectedBytes",
        module: Text<0, 12288> => "module",
} }

literal! { ExpectedClientCheckConnectedOpeningTransferSourceProvenance => "compiled-inventory" }

literal! { ExpectedClientCheckConnectedInventoryRefusalCleanupKind => "release-or-own-connection-close" }

record! { ExpectedClientCheckConnectedInventoryRefusalCleanupReleaseExchange {
        effect: EffectRef => "effect",
        reply_raw_json: RawJson => "replyRawJson",
        request_id_token: U64Token => "requestIdToken",
        request_raw_json: RawJson => "requestRawJson",
} }

record! { ExpectedClientCheckConnectedInventoryRefusalCleanup {
        capture_id: Text<0, 128> => "captureId",
        connection: FixtureAlias => "connection",
        kind: ExpectedClientCheckConnectedInventoryRefusalCleanupKind => "kind",
        release_exchange: ExpectedClientCheckConnectedInventoryRefusalCleanupReleaseExchange => "releaseExchange",
} }

words! { ExpectedClientCheckConnectedInventoryRefusalFault {
    SkipIndex => "skip-index",
    RepeatIndex => "repeat-index",
    OmitEmptyDirectory => "omit-empty-directory",
    ExtraEntry => "extra-entry",
    WrongInventoryDigest => "wrong-inventory-digest",
    ChangedBinding => "changed-binding",
    FileDirectoryCollision => "file-directory-collision",
    UTF16InsteadOfUTF8Sort => "UTF16-instead-of-UTF8-sort",
} }

literal! { ExpectedClientCheckConnectedInventoryRefusalManifestCache => "no-store" }

literal! { ExpectedClientCheckConnectedInventoryRefusalManifestCredentials => "same-origin" }

literal! { ExpectedClientCheckConnectedInventoryRefusalManifestMethod => "GET" }

literal! { ExpectedClientCheckConnectedInventoryRefusalManifestPath => "/api/session" }

literal! { ExpectedClientCheckConnectedInventoryRefusalManifestRedirect => "error" }

literal! { ExpectedClientCheckConnectedInventoryRefusalManifestStatus => 200 }

record! { ExpectedClientCheckConnectedInventoryRefusalManifest {
        cache: ExpectedClientCheckConnectedInventoryRefusalManifestCache => "cache",
        credentials: ExpectedClientCheckConnectedInventoryRefusalManifestCredentials => "credentials",
        expected_bytes: FixtureAlias => "expectedBytes",
        method: ExpectedClientCheckConnectedInventoryRefusalManifestMethod => "method",
        path: ExpectedClientCheckConnectedInventoryRefusalManifestPath => "path",
        redirect: ExpectedClientCheckConnectedInventoryRefusalManifestRedirect => "redirect",
        status: ExpectedClientCheckConnectedInventoryRefusalManifestStatus => "status",
} }

literal! { ExpectedClientCheckConnectedInventoryRefusalNumberComparison => "exact-token" }

record! { ExpectedClientCheckConnectedInventoryRefusalPrefixExchangesItem {
        effect: EffectRef => "effect",
        reply_raw_json: RawJson => "replyRawJson",
        request_id_token: U64Token => "requestIdToken",
        request_raw_json: RawJson => "requestRawJson",
} }

literal! { ExpectedClientCheckConnectedInventoryRefusalReason => "inventory-binding-or-completeness" }

literal! { ExpectedClientCheckConnectedInventoryRefusalWebSocketPath => "/rpc" }

record! { ExpectedClientCheckConnectedOriginalsRetainedOriginRecord {
        descriptor: ExpectedDescriptor => "descriptor",
        expected_bytes: FixtureAlias => "expectedBytes",
        module: Text<0, 12288> => "module",
} }

literal! { ExpectedClientCheckConnectedOriginalsRetainedProjectionKind => "not-requested" }

record! { ExpectedClientCheckConnectedOriginalsRetainedProjection {
        kind: ExpectedClientCheckConnectedOriginalsRetainedProjectionKind => "kind",
} }

literal! { ExpectedClientCheckConnectedOriginalsRetainedSourceProvenance => "compiled-inventory" }

tagged! { ExpectedClientCheck("kind") {
    PortTrace => "port-trace" {
        expected_trace: FixtureAlias => "expectedTrace",
        id: FixtureAlias => "id",
    },
    PortCounts => "port-counts" {
        attempts: Items<FixtureAlias, 1, 8192> => "attempts",
        effect_kind: EffectKind => "effectKind",
        expected: NumberRequirement => "expected",
        id: FixtureAlias => "id",
    },
    OwnerAbsent => "owner-absent" {
        checkpoint: FixtureAlias => "checkpoint",
        id: FixtureAlias => "id",
    },
    VerifiedOwner => "verified-owner" {
        adoption: TypedAdoption => "adoption",
        attempt: FixtureAlias => "attempt",
        checkpoint: FixtureAlias => "checkpoint",
        id: FixtureAlias => "id",
        model: FixtureAlias => "model",
        originals: ExpectedOriginalOwner => "originals",
    },
    CurrentOpening => "current-opening" {
        checkpoint: FixtureAlias => "checkpoint",
        current: ExpectedCurrentOpening => "current",
        id: FixtureAlias => "id",
    },
    CurrentModel => "current-model" {
        checkpoint: FixtureAlias => "checkpoint",
        current: ExpectedCurrentModel => "current",
        id: FixtureAlias => "id",
    },
    CoreResult => "core-result" {
        attempt: FixtureAlias => "attempt",
        effect: EffectRef => "effect",
        id: FixtureAlias => "id",
        model_binding: ExpectedModelBinding => "modelBinding",
        projection: ExpectedCoreProjection => "projection",
    },
    Download => "download" {
        expected_bytes: FixtureAlias => "expectedBytes",
        id: FixtureAlias => "id",
        model: FixtureAlias => "model",
        ordinal: Count => "ordinal",
        target: ExpectedClientCheckDownloadTarget => "target",
    },
    Archive => "archive" {
        entries: ExpectedEntries => "entries",
        id: FixtureAlias => "id",
        model: FixtureAlias => "model",
        ordinal: Count => "ordinal",
    },
    RichOwner => "rich-owner" {
        expected_carrier_raw_json: RawJson => "expectedCarrierRawJson",
        expected_provenance_rich: FixtureAlias => "expectedProvenanceRich",
        graph: ExpectedClientCheckRichOwnerGraph => "graph",
        id: FixtureAlias => "id",
        model: FixtureAlias => "model",
    },
    Navigation => "navigation" {
        checkpoint: FixtureAlias => "checkpoint",
        destinations: NumberRequirement => "destinations",
        id: FixtureAlias => "id",
        inspection_owner: ExpectedClientCheckNavigationInspectionOwner => "inspectionOwner",
        output_owner: ExpectedClientCheckNavigationOutputOwner => "outputOwner",
        search_owner: ExpectedClientCheckNavigationSearchOwner => "searchOwner",
    },
    CaptureCleanup => "capture-cleanup" {
        checkpoint: FixtureAlias => "checkpoint",
        cleanup: ExpectedCleanup => "cleanup",
        id: FixtureAlias => "id",
    },
    ExecutionOwner => "execution-owner" {
        checkpoint: FixtureAlias => "checkpoint",
        id: FixtureAlias => "id",
        owner: ExecutionOwner => "owner",
    },
    ExecutionReceipt => "execution-receipt" {
        effect: EffectRef => "effect",
        execution: FixtureAlias => "execution",
        expected_raw_json: RawJson => "expectedRawJson",
        id: FixtureAlias => "id",
        model: FixtureAlias => "model",
    },
    LocalExplorerState => "local-explorer-state" {
        checkpoint: FixtureAlias => "checkpoint",
        current: ExpectedClientCheckLocalExplorerStateCurrent => "current",
        history: ExpectedClientCheckLocalExplorerStateHistory => "history",
        id: FixtureAlias => "id",
        inspection: ExpectedClientCheckLocalExplorerStateInspection => "inspection",
        query: Text<0, 16000> => "query",
        selected_key: ExpectedClientCheckLocalExplorerStateSelectedKey => "selectedKey",
        visible_declaration_keys: UniqueItems<Text<1, 16000>, 0, 100000> => "visibleDeclarationKeys",
    },
    LocalEvaluationState => "local-evaluation-state" {
        checkpoint: FixtureAlias => "checkpoint",
        host_retention: ExpectedClientCheckLocalEvaluationStateHostRetention => "hostRetention",
        id: FixtureAlias => "id",
        result: ExpectedClientCheckLocalEvaluationStateResult => "result",
    },
    ModelOutputCleared => "model-output-cleared" {
        checkpoint: FixtureAlias => "checkpoint",
        former_model: FixtureAlias => "formerModel",
        id: FixtureAlias => "id",
    },
    NativeTranscript => "native-transcript" {
        exchanges: Items<ExpectedClientCheckNativeTranscriptExchangesItem, 1, 4096> => "exchanges",
        id: FixtureAlias => "id",
        number_comparison: ExpectedClientCheckNativeTranscriptNumberComparison => "numberComparison",
        runtime: FixtureAlias => "runtime",
    },
    NativeOpenReleaseOrder => "native-open-release-order" {
        attempt: FixtureAlias => "attempt",
        before_inspection_checkpoint: FixtureAlias => "beforeInspectionCheckpoint",
        final_check_ordinal: Count => "finalCheckOrdinal",
        id: FixtureAlias => "id",
        inspection: EffectRef => "inspection",
        model: FixtureAlias => "model",
        publication_checkpoint: FixtureAlias => "publicationCheckpoint",
        release_ordinal: Count => "releaseOrdinal",
        release_postcheck_ordinal: Count => "releasePostcheckOrdinal",
        runtime: FixtureAlias => "runtime",
        source_bytes: FixtureAlias => "sourceBytes",
        source_codec: ExpectedClientCheckNativeOpenReleaseOrderSourceCodec => "sourceCodec",
        source_header: ExpectedClientCheckNativeOpenReleaseOrderSourceHeader => "sourceHeader",
    },
    NativeWorkspaceOwnerState => "native-workspace-owner-state" {
        checkpoint: FixtureAlias => "checkpoint",
        execution_owner: ExpectedClientCheckNativeWorkspaceOwnerStateExecutionOwner => "executionOwner",
        grant_id: ExpectedClientCheckNativeWorkspaceOwnerStateGrantId => "grantId",
        id: FixtureAlias => "id",
        model_authority: ExpectedClientCheckNativeWorkspaceOwnerStateModelAuthority => "modelAuthority",
        pending_release: JsonNull => "pendingRelease",
        projects_raw_json: RawJson => "projectsRawJson",
        runtime: FixtureAlias => "runtime",
        sequence: Count => "sequence",
    },
    ConnectedTranscript => "connected-transcript" {
        attempt: FixtureAlias => "attempt",
        exchanges: Items<ExpectedClientCheckConnectedTranscriptExchangesItem, 3, 4096> => "exchanges",
        id: FixtureAlias => "id",
        manifest: ExpectedClientCheckConnectedTranscriptManifest => "manifest",
        number_comparison: ExpectedClientCheckConnectedTranscriptNumberComparison => "numberComparison",
        pending: FixtureAlias => "pending",
        selected_project_id: Text<0, 12288> => "selectedProjectId",
        selected_source_raw_json: RawJson => "selectedSourceRawJson",
        web_socket_path: ExpectedClientCheckConnectedTranscriptWebSocketPath => "webSocketPath",
    },
    ConnectedOpeningTransfer => "connected-opening-transfer" {
        attempt: FixtureAlias => "attempt",
        before_inspection_checkpoint: FixtureAlias => "beforeInspectionCheckpoint",
        capture_id: Text<0, 128> => "captureId",
        coverage: CaptureCoverage => "coverage",
        id: FixtureAlias => "id",
        inspection: EffectRef => "inspection",
        inventory: ExpectedInventory => "inventory",
        model: FixtureAlias => "model",
        origin_record: ExpectedClientCheckConnectedOpeningTransferOriginRecord => "originRecord",
        pending: FixtureAlias => "pending",
        projection: ExpectedProjection => "projection",
        publication_checkpoint: FixtureAlias => "publicationCheckpoint",
        release_request_id_token: U64Token => "releaseRequestIdToken",
        source: SourceExpectation => "source",
        source_provenance: ExpectedClientCheckConnectedOpeningTransferSourceProvenance => "sourceProvenance",
    },
    ConnectedInventoryRefusal => "connected-inventory-refusal" {
        attempt: FixtureAlias => "attempt",
        checkpoint: FixtureAlias => "checkpoint",
        cleanup: ExpectedClientCheckConnectedInventoryRefusalCleanup => "cleanup",
        failed_inventory: EffectRef => "failedInventory",
        fault: ExpectedClientCheckConnectedInventoryRefusalFault => "fault",
        id: FixtureAlias => "id",
        manifest: ExpectedClientCheckConnectedInventoryRefusalManifest => "manifest",
        number_comparison: ExpectedClientCheckConnectedInventoryRefusalNumberComparison => "numberComparison",
        pending: FixtureAlias => "pending",
        prefix_exchanges: Items<ExpectedClientCheckConnectedInventoryRefusalPrefixExchangesItem, 5, 5> => "prefixExchanges",
        reason: ExpectedClientCheckConnectedInventoryRefusalReason => "reason",
        selected_project_id: Text<0, 12288> => "selectedProjectId",
        selected_source_raw_json: RawJson => "selectedSourceRawJson",
        web_socket_path: ExpectedClientCheckConnectedInventoryRefusalWebSocketPath => "webSocketPath",
    },
    ConnectedOriginalsRetained => "connected-originals-retained" {
        attempt: FixtureAlias => "attempt",
        capture_id: Text<0, 128> => "captureId",
        coverage: CaptureCoverage => "coverage",
        id: FixtureAlias => "id",
        inventory: ExpectedInventory => "inventory",
        model: FixtureAlias => "model",
        origin_record: ExpectedClientCheckConnectedOriginalsRetainedOriginRecord => "originRecord",
        pending: FixtureAlias => "pending",
        projection: ExpectedClientCheckConnectedOriginalsRetainedProjection => "projection",
        publication_checkpoint: FixtureAlias => "publicationCheckpoint",
        release_request_id_token: U64Token => "releaseRequestIdToken",
        source: SourceExpectation => "source",
        source_provenance: ExpectedClientCheckConnectedOriginalsRetainedSourceProvenance => "sourceProvenance",
    },
} }

literal! { ExpectedCoreProjectionExactJsonNumberComparison => "exact-token" }

tagged! { ExpectedCoreProjectionInspectRetainedRich("kind") {
    None => "none" {

    },
    Retained => "retained" {
        expected_rich: FixtureAlias => "expectedRich",
    },
} }

words! { ExpectedCoreProjectionTypedRefusalReason {
    Unsupported => "unsupported",
    InvalidModel => "invalid-model",
    DecodeLimit => "decode-limit",
    LossyConversion => "lossy-conversion",
    CapabilityRefused => "capability-refused",
} }

literal! { ExpectedCoreProjectionLocalEvaluationNumberComparison => "exact-token" }

tagged! { ExpectedCoreProjection("kind") {
    ExactJson => "exact-json" {
        expected_raw_json: RawJson => "expectedRawJson",
        number_comparison: ExpectedCoreProjectionExactJsonNumberComparison => "numberComparison",
    },
    Inspect => "inspect" {
        expected_modules: Items<Text<0, 4096>, 0, 100000> => "expectedModules",
        expected_semantic_bytes: FixtureAlias => "expectedSemanticBytes",
        expected_symbols: Items<Text<0, 4096>, 0, 100000> => "expectedSymbols",
        retained_rich: ExpectedCoreProjectionInspectRetainedRich => "retainedRich",
        semantic_header: Text<0, 128> => "semanticHeader",
        source_header: Text<0, 128> => "sourceHeader",
    },
    Search => "search" {
        expected_result_raw_json: RawJson => "expectedResultRawJson",
    },
    ConceptualSpecification => "conceptual-specification" {
        expected_carrier_raw_json: RawJson => "expectedCarrierRawJson",
        expected_graph: FixtureAlias => "expectedGraph",
        original_owner: FixtureAlias => "originalOwner",
    },
    TypedRefusal => "typed-refusal" {
        expected_code: Text<0, 128> => "expectedCode",
        reason: ExpectedCoreProjectionTypedRefusalReason => "reason",
    },
    LocalEvaluation => "local-evaluation" {
        expected_terminal_raw_json: RawJson => "expectedTerminalRawJson",
        number_comparison: ExpectedCoreProjectionLocalEvaluationNumberComparison => "numberComparison",
    },
} }

tagged! { ExpectedCurrentModel("kind") {
    None => "none" {

    },
    Model => "model" {
        model: FixtureAlias => "model",
    },
} }

tagged! { ExpectedCurrentOpening("kind") {
    None => "none" {

    },
    Attempt => "attempt" {
        attempt: FixtureAlias => "attempt",
    },
} }

words! { ExpectedDescriptorFormat {
    Json => "json",
    Yaml => "yaml",
    Ion => "ion",
} }

words! { ExpectedDescriptorLayout {
    SingleFile => "single-file",
    DocumentTree => "document-tree",
} }

words! { ExpectedDescriptorVersion {
    V3 => "v3",
    V4 => "v4",
} }

record! { ExpectedDescriptor {
        format: ExpectedDescriptorFormat => "format",
        layout: ExpectedDescriptorLayout => "layout",
        path: SourcePath => "path",
        version: ExpectedDescriptorVersion => "version",
} }

tagged! { ExpectedEntries("kind") {
    Literal => "literal" {
        entries: Items<ExpectedEntry, 0, 100064> => "entries",
    },
    FileSeries => "file-series" {
        count: Natural<0, 100000> => "count",
        decimal_width: Natural<1, 20> => "decimalWidth",
        expected_bytes: FixtureAlias => "expectedBytes",
        first: Count => "first",
        parent: SourcePath => "parent",
        prefix: Text<0, 1024> => "prefix",
        roots: Items<ExpectedEntry, 0, 64> => "roots",
        suffix: Text<0, 1024> => "suffix",
    },
} }

tagged! { ExpectedEntry("kind") {
    Directory => "directory" {
        entry: FixtureAlias => "entry",
        path: SourcePath => "path",
    },
    File => "file" {
        entry: FixtureAlias => "entry",
        expected_bytes: FixtureAlias => "expectedBytes",
        path: SourcePath => "path",
    },
} }

words! { ExpectedFailureModelOriginalsCode {
    InvalidRequest => "model_originals.invalid_request",
    InvalidIdentity => "model_originals.invalid_identity",
    InvalidPath => "model_originals.invalid_path",
    InvalidPathSet => "model_originals.invalid_path_set",
    InvalidRange => "model_originals.invalid_range",
    InvalidDeclaration => "model_originals.invalid_declaration",
    Unavailable => "model_originals.unavailable",
    UnknownHandle => "model_originals.unknown_handle",
    ActiveCapture => "model_originals.active_capture",
    Capacity => "model_originals.capacity",
    SourceLimit => "model_originals.source_limit",
    InventoryLimit => "model_originals.inventory_limit",
    ReplyLimit => "model_originals.reply_limit",
    CaptureFailed => "model_originals.capture_failed",
    Timeout => "model_originals.timeout",
} }

words! { ExpectedFailureModelOriginalsRpcExactValue {
    ParseError => "parse-error",
    InvalidParameters => "invalid-parameters",
    ServerError => "server-error",
} }

words! { ExpectedFailureModelOriginalsRpcAnyOfValuesItem {
    ParseError => "parse-error",
    InvalidParameters => "invalid-parameters",
    ServerError => "server-error",
} }

tagged! { ExpectedFailureModelOriginalsRpc("kind") {
    Exact => "exact" {
        value: ExpectedFailureModelOriginalsRpcExactValue => "value",
    },
    AnyOf => "any-of" {
        values: UniqueItems<ExpectedFailureModelOriginalsRpcAnyOfValuesItem, 1, 3> => "values",
    },
} }

words! { ExpectedFailureJsonRpcRpc {
    ParseError => "parse-error",
    InvalidRequest => "invalid-request",
    MethodNotFound => "method-not-found",
    InvalidParameters => "invalid-parameters",
    InternalError => "internal-error",
    ServerError => "server-error",
} }

tagged! { ExpectedFailure("kind") {
    ModelOriginals => "model-originals" {
        code: ExpectedFailureModelOriginalsCode => "code",
        message: ExpectedMessage => "message",
        rpc: ExpectedFailureModelOriginalsRpc => "rpc",
    },
    JsonRpc => "json-rpc" {
        message: ExpectedMessage => "message",
        rpc: ExpectedFailureJsonRpcRpc => "rpc",
    },
} }

record! { ExpectedInventory {
        directory_count: Natural<0, 100064> => "directoryCount",
        entries: ExpectedEntries => "entries",
        entry_count: Natural<0, 100064> => "entryCount",
        file_count: Natural<0, 100064> => "fileCount",
        sha256: ContentSha256 => "sha256",
        source_byte_length: Count => "sourceByteLength",
} }

tagged! { ExpectedLifecycleState("kind") {
    Empty => "empty" {

    },
    Capturing => "capturing" {
        attempt: FixtureAlias => "attempt",
        work: FixtureAlias => "work",
    },
    PreparedPrivate => "prepared-private" {
        attempt: FixtureAlias => "attempt",
        work: FixtureAlias => "work",
    },
    Ready => "ready" {
        capture: FixtureAlias => "capture",
    },
    Released => "released" {
        capture: FixtureAlias => "capture",
    },
    Closed => "closed" {
        still_owned_work: Items<FixtureAlias, 0, 8192> => "stillOwnedWork",
    },
} }

words! { ExpectedLineageTreatmentComparedByDecisionDecision {
    MorphirU3f6 => "morphir-u3f6",
    MorphirEtg222121 => "morphir-etg2.22.1.2.1",
} }

literal! { ExpectedLineageTreatmentSupersededAuthoringErrorAuditSHA256 => "fb040e5a80566cba3cc819a4e68348b8e67f6de50517cbd105b7b484de9e5867" }

literal! { ExpectedLineageTreatmentSupersededAuthoringErrorCorrection => "unsigned-utf8-inventory-order" }

tagged! { ExpectedLineageTreatment("kind") {
    Compared => "compared" {
        check_ids: Items<FixtureAlias, 1, 8192> => "checkIds",
    },
    Commentary => "commentary" {
        commentary_index: Count => "commentaryIndex",
    },
    Unresolved => "unresolved" {
        obligation: FixtureAlias => "obligation",
    },
    ComparedByDecision => "compared-by-decision" {
        check_ids: Items<FixtureAlias, 1, 8192> => "checkIds",
        decision: ExpectedLineageTreatmentComparedByDecisionDecision => "decision",
    },
    SupersededAuthoringError => "superseded-authoring-error" {
        audit_s_h_a256: ExpectedLineageTreatmentSupersededAuthoringErrorAuditSHA256 => "auditSHA256",
        correction: ExpectedLineageTreatmentSupersededAuthoringErrorCorrection => "correction",
        old_value_raw_json: RawJson => "oldValueRawJson",
        replacement_check_ids: Items<FixtureAlias, 1, 8192> => "replacementCheckIds",
    },
} }

record! { ExpectedLineage {
        frozen_expectation: Text<0, 4096> => "frozenExpectation",
        frozen_s_h_a256: ContentSha256 => "frozenSHA256",
        original_pointer: Text<0, 4096> => "originalPointer",
        treatment: ExpectedLineageTreatment => "treatment",
} }

tagged! { ExpectedMessage("kind") {
    Exact => "exact" {
        value: Text<0, 512> => "value",
    },
    NotAnOperand => "not-an-operand" {

    },
} }

tagged! { ExpectedModelBinding("kind") {
    None => "none" {

    },
    RetainedOwner => "retained-owner" {
        model: FixtureAlias => "model",
    },
} }

tagged! { ExpectedOffer("kind") {
    Held => "held" {
        provider: FixtureAlias => "provider",
        registration: FixtureAlias => "registration",
    },
    Revoked => "revoked" {
        provider: FixtureAlias => "provider",
        registration: FixtureAlias => "registration",
    },
    Replaced => "replaced" {
        current: FixtureAlias => "current",
        previous: FixtureAlias => "previous",
        provider: FixtureAlias => "provider",
    },
} }

tagged! { ExpectedOriginalOwner("kind") {
    File => "file" {
        codec: ModelCodec => "codec",
        expected_bytes: FixtureAlias => "expectedBytes",
        filename: Text<0, 4096> => "filename",
    },
    Inventory => "inventory" {
        inventory: Box<ExpectedInventory> => "inventory",
        projection: ExpectedProjection => "projection",
        source: SourceExpectation => "source",
    },
} }

tagged! { ExpectedPageNext("kind") {
    More => "more" {
        start_index: Count => "startIndex",
    },
    Complete => "complete" {

    },
} }

tagged! { ExpectedPagePathExpectation("kind") {
    Literal => "literal" {
        paths: Items<SourcePath, 0, 256> => "paths",
    },
    InventoryWindow => "inventory-window" {
        count: Natural<0, 256> => "count",
    },
} }

record! { ExpectedPage {
        exchange: ExchangeRef => "exchange",
        max_entries: Natural<1, 256> => "maxEntries",
        next: ExpectedPageNext => "next",
        path_expectation: ExpectedPagePathExpectation => "pathExpectation",
        start_index: Count => "startIndex",
} }

tagged! { ExpectedPortReply("kind") {
    ExactJson => "exact-json" {
        expected_raw_json: RawJson => "expectedRawJson",
    },
    ExactBytes => "exact-bytes" {
        expected_bytes: FixtureAlias => "expectedBytes",
    },
    ProducedCoreResult => "produced-core-result" {

    },
    PickerSelected => "picker-selected" {
        codec: ModelCodec => "codec",
        expected_bytes: FixtureAlias => "expectedBytes",
        filename: Text<0, 4096> => "filename",
    },
    PickerCancelled => "picker-cancelled" {

    },
} }

words! { ExpectedProjectionUnavailableReason {
    UnsupportedRepresentation => "unsupported_representation",
    InvalidModel => "invalid_model",
    DecodeLimit => "decode_limit",
    ProjectionLimit => "projection_limit",
    Capacity => "capacity",
    Timeout => "timeout",
} }

literal! { ExpectedProjectionAvailableContentSemanticJsonNumberComparison => "mathematical-decimal-preserve-signed-zero" }

tagged! { ExpectedProjectionAvailableContent("kind") {
    ExactBytes => "exact-bytes" {
        expected_bytes: FixtureAlias => "expectedBytes",
    },
    SemanticJson => "semantic-json" {
        expected_bytes: FixtureAlias => "expectedBytes",
        number_comparison: ExpectedProjectionAvailableContentSemanticJsonNumberComparison => "numberComparison",
    },
} }

tagged! { ExpectedProjection("kind") {
    NotRequested => "not-requested" {

    },
    Unavailable => "unavailable" {
        reason: ExpectedProjectionUnavailableReason => "reason",
    },
    Available => "available" {
        actual_header: Text<0, 128> => "actualHeader",
        content: ExpectedProjectionAvailableContent => "content",
    },
} }

tagged! { ExpectedRichName("kind") {
    Known => "known" {
        text: Text<0, 1048576> => "text",
    },
    Unknown => "unknown" {
        sid: Count => "sid",
    },
} }

words! { ExpectedRichScalarNullType {
    Null => "null",
    Bool => "bool",
    Int => "int",
    Float => "float",
    Decimal => "decimal",
    Timestamp => "timestamp",
    Symbol => "symbol",
    String => "string",
    Clob => "clob",
    Blob => "blob",
    List => "list",
    Sexp => "sexp",
    Struct => "struct",
} }

text! { ExpectedRichScalarIntDecimal { min: 0, max: 1048576, pattern: "^-?(0|[1-9][0-9]*)$" } }

text! { ExpectedRichScalarFloatBits64Hex { min: 0, max: unbounded, pattern: "^[0-9a-f]{16}$" } }

text! { ExpectedRichScalarDecimalCoefficient { min: 0, max: 1048576, pattern: "^-?(0|[1-9][0-9]*)$" } }

text! { ExpectedRichScalarDecimalExponent { min: 0, max: 1048576, pattern: "^-?(0|[1-9][0-9]*)$" } }

tagged! { ExpectedRichScalar("kind") {
    Null => "null" {
        r#type: ExpectedRichScalarNullType => "type",
    },
    Bool => "bool" {
        value: JsonBool => "value",
    },
    Int => "int" {
        decimal: ExpectedRichScalarIntDecimal => "decimal",
    },
    Float => "float" {
        bits64_hex: ExpectedRichScalarFloatBits64Hex => "bits64Hex",
    },
    Decimal => "decimal" {
        coefficient: ExpectedRichScalarDecimalCoefficient => "coefficient",
        exponent: ExpectedRichScalarDecimalExponent => "exponent",
    },
    Timestamp => "timestamp" {
        canonical_ion: Text<0, 1048576> => "canonicalIon",
    },
    Symbol => "symbol" {
        text: Text<0, 1048576> => "text",
    },
    UnknownSymbol => "unknown-symbol" {
        sid: Count => "sid",
        source_bytes: FixtureAlias => "sourceBytes",
    },
    String => "string" {
        value: Text<0, 1048576> => "value",
    },
    Blob => "blob" {
        expected_bytes: FixtureAlias => "expectedBytes",
    },
    Clob => "clob" {
        expected_bytes: FixtureAlias => "expectedBytes",
    },
} }

words! { ExpectedRichValueValueNullType {
    Null => "null",
    Bool => "bool",
    Int => "int",
    Float => "float",
    Decimal => "decimal",
    Timestamp => "timestamp",
    Symbol => "symbol",
    String => "string",
    Clob => "clob",
    Blob => "blob",
    List => "list",
    Sexp => "sexp",
    Struct => "struct",
} }

text! { ExpectedRichValueValueIntDecimal { min: 0, max: 1048576, pattern: "^-?(0|[1-9][0-9]*)$" } }

text! { ExpectedRichValueValueFloatBits64Hex { min: 0, max: unbounded, pattern: "^[0-9a-f]{16}$" } }

text! { ExpectedRichValueValueDecimalCoefficient { min: 0, max: 1048576, pattern: "^-?(0|[1-9][0-9]*)$" } }

text! { ExpectedRichValueValueDecimalExponent { min: 0, max: 1048576, pattern: "^-?(0|[1-9][0-9]*)$" } }

record! { ExpectedRichValueValueStructFieldsItem {
        name: ExpectedRichName => "name",
        value: ExpectedRichValue => "value",
} }

tagged! { ExpectedRichValueValue("kind") {
    Null => "null" {
        r#type: ExpectedRichValueValueNullType => "type",
    },
    Bool => "bool" {
        value: JsonBool => "value",
    },
    Int => "int" {
        decimal: ExpectedRichValueValueIntDecimal => "decimal",
    },
    Float => "float" {
        bits64_hex: ExpectedRichValueValueFloatBits64Hex => "bits64Hex",
    },
    Decimal => "decimal" {
        coefficient: ExpectedRichValueValueDecimalCoefficient => "coefficient",
        exponent: ExpectedRichValueValueDecimalExponent => "exponent",
    },
    Timestamp => "timestamp" {
        canonical_ion: Text<0, 1048576> => "canonicalIon",
    },
    Symbol => "symbol" {
        text: Text<0, 1048576> => "text",
    },
    UnknownSymbol => "unknown-symbol" {
        sid: Count => "sid",
        source_bytes: FixtureAlias => "sourceBytes",
    },
    String => "string" {
        value: Text<0, 1048576> => "value",
    },
    Blob => "blob" {
        expected_bytes: FixtureAlias => "expectedBytes",
    },
    Clob => "clob" {
        expected_bytes: FixtureAlias => "expectedBytes",
    },
    List => "list" {
        items: Items<ExpectedRichValue, 0, 100000> => "items",
    },
    Sexp => "sexp" {
        items: Items<ExpectedRichValue, 0, 100000> => "items",
    },
    Struct => "struct" {
        fields: Items<ExpectedRichValueValueStructFieldsItem, 0, 100000> => "fields",
    },
} }

record! { ExpectedRichValue {
        annotations: Items<Text<0, 1048576>, 0, 100000> => "annotations",
        value: ExpectedRichValueValue => "value",
} }

literal! { ExpectedServerCheckCapturePrivateRecordSchema => 1 }

literal! { ExpectedServerCheckCapturePrivateRecordTask => "compile" }

record! { ExpectedServerCheckCapturePrivateRecord {
        descriptor: ExpectedDescriptor => "descriptor",
        expected_bytes: FixtureAlias => "expectedBytes",
        module: Text<0, 16000> => "module",
        schema: ExpectedServerCheckCapturePrivateRecordSchema => "schema",
        task: ExpectedServerCheckCapturePrivateRecordTask => "task",
} }

literal! { ExpectedServerCheckInventoryComplete => true }

tagged! { ExpectedServerCheckStreamCoverage("kind") {
    Complete => "complete" {

    },
    Eof => "eof" {
        offset: Count => "offset",
    },
} }

literal! { ExpectedServerCheckReleaseStatus => "released" }

literal! { ExpectedServerCheckLegacyOpenSourceProvenance => "semantic-only" }

words! { ExpectedServerCheckCaptureUnavailableReason {
    NotCompiled => "not_compiled",
    CompanionsUndeclared => "companions_undeclared",
    UnsupportedRepresentation => "unsupported_representation",
} }

record! { ExpectedServerCheckCooperatingLockOrderOrderItem {
        after: LockEventRef => "after",
        before: LockEventRef => "before",
} }

literal! { ExpectedServerCheckCooperatingLockOrderScopeLockFilename => "compile.lock" }

record! { ExpectedServerCheckCooperatingLockOrderScope {
        binding: FixtureAlias => "binding",
        lock_filename: ExpectedServerCheckCooperatingLockOrderScopeLockFilename => "lockFilename",
        module: Text<0, 16000> => "module",
} }

literal! { ExpectedServerCheckLegacyOpenSelectedContentSemanticJsonNumberComparison => "mathematical-decimal-preserve-signed-zero-no-header-aliases" }

tagged! { ExpectedServerCheckLegacyOpenSelectedContent("kind") {
    ExactBytes => "exact-bytes" {
        expected_bytes: FixtureAlias => "expectedBytes",
    },
    SemanticJson => "semantic-json" {
        expected_bytes: FixtureAlias => "expectedBytes",
        number_comparison: ExpectedServerCheckLegacyOpenSelectedContentSemanticJsonNumberComparison => "numberComparison",
    },
} }

literal! { ExpectedServerCheckLegacyOpenSelectedDescriptorDistribution => "single-file" }

literal! { ExpectedServerCheckLegacyOpenSelectedDescriptorKind => "model" }

literal! { ExpectedServerCheckLegacyOpenSelectedDescriptorRoute => "explorer" }

literal! { ExpectedServerCheckLegacyOpenSelectedDescriptorSource => "selected-project-semantic-model" }

literal! { ExpectedServerCheckLegacyOpenSelectedDescriptorTimestamps => "same-utc-millisecond-timestamp" }

record! { ExpectedServerCheckLegacyOpenSelectedDescriptor {
        distribution: ExpectedServerCheckLegacyOpenSelectedDescriptorDistribution => "distribution",
        kind: ExpectedServerCheckLegacyOpenSelectedDescriptorKind => "kind",
        name: Text<0, 16000> => "name",
        route: ExpectedServerCheckLegacyOpenSelectedDescriptorRoute => "route",
        source: ExpectedServerCheckLegacyOpenSelectedDescriptorSource => "source",
        timestamps: ExpectedServerCheckLegacyOpenSelectedDescriptorTimestamps => "timestamps",
} }

literal! { ExpectedServerCheckLegacyOpenSelectedSourceProvenance => "semantic-only" }

literal! { ExpectedServerCheckProducerMessageBoundaryBoundaryIngressRequestDispositionRefusedCode => "model_originals.invalid_request" }

tagged! { ExpectedServerCheckProducerMessageBoundaryBoundaryIngressRequestDisposition("kind") {
    Accepted => "accepted" {
        code: JsonNull => "code",
    },
    Refused => "refused" {
        code: ExpectedServerCheckProducerMessageBoundaryBoundaryIngressRequestDispositionRefusedCode => "code",
    },
} }

literal! { ExpectedServerCheckProducerMessageBoundaryBoundaryEgressReplyDispositionRefusedCode => "model_originals.reply_limit" }

tagged! { ExpectedServerCheckProducerMessageBoundaryBoundaryEgressReplyDisposition("kind") {
    Accepted => "accepted" {
        code: JsonNull => "code",
    },
    Refused => "refused" {
        code: ExpectedServerCheckProducerMessageBoundaryBoundaryEgressReplyDispositionRefusedCode => "code",
    },
} }

tagged! { ExpectedServerCheckProducerMessageBoundaryBoundary("stage") {
    IngressRequest => "ingress-request" {
        disposition: ExpectedServerCheckProducerMessageBoundaryBoundaryIngressRequestDisposition => "disposition",
    },
    EgressReply => "egress-reply" {
        disposition: ExpectedServerCheckProducerMessageBoundaryBoundaryEgressReplyDisposition => "disposition",
    },
} }

literal! { ExpectedServerCheckProducerMessageBoundaryTruncated => false }

tagged! { ExpectedServerCheck("kind") {
    Capture => "capture" {
        binding: FixtureAlias => "binding",
        capture: FixtureAlias => "capture",
        coverage: CaptureCoverage => "coverage",
        exchange: ExchangeRef => "exchange",
        id: FixtureAlias => "id",
        inventory: Box<ExpectedInventory> => "inventory",
        private_record: ExpectedServerCheckCapturePrivateRecord => "privateRecord",
        projection: ExpectedProjection => "projection",
        source: SourceExpectation => "source",
    },
    Inventory => "inventory" {
        capture: FixtureAlias => "capture",
        complete: ExpectedServerCheckInventoryComplete => "complete",
        expected_inventory: ExpectedInventory => "expectedInventory",
        id: FixtureAlias => "id",
        pages: Items<ExpectedPage, 1, 8192> => "pages",
    },
    Stream => "stream" {
        capture: FixtureAlias => "capture",
        coverage: ExpectedServerCheckStreamCoverage => "coverage",
        exchanges: Items<ExchangeRef, 1, 8192> => "exchanges",
        expected_bytes: FixtureAlias => "expectedBytes",
        id: FixtureAlias => "id",
        target: ExpectedStreamTarget => "target",
    },
    RpcRefusal => "rpc-refusal" {
        checkpoint: FixtureAlias => "checkpoint",
        effect_delta: Items<CountCheck, 0, 32> => "effectDelta",
        exchange: ExchangeRef => "exchange",
        failure: ExpectedFailure => "failure",
        id: FixtureAlias => "id",
    },
    Release => "release" {
        capture: FixtureAlias => "capture",
        exchange: ExchangeRef => "exchange",
        id: FixtureAlias => "id",
        status: ExpectedServerCheckReleaseStatus => "status",
    },
    CheckpointCounts => "checkpoint-counts" {
        checkpoint: FixtureAlias => "checkpoint",
        connection: FixtureAlias => "connection",
        counts: Items<CountCheck, 1, 32> => "counts",
        id: FixtureAlias => "id",
    },
    CaptureLifecycle => "capture-lifecycle" {
        checkpoint: FixtureAlias => "checkpoint",
        connection: FixtureAlias => "connection",
        id: FixtureAlias => "id",
        state: ExpectedLifecycleState => "state",
    },
    Offer => "offer" {
        checkpoint: FixtureAlias => "checkpoint",
        connection: FixtureAlias => "connection",
        id: FixtureAlias => "id",
        state: ExpectedOffer => "state",
    },
    WorkspaceSnapshot => "workspace-snapshot" {
        binding: FixtureAlias => "binding",
        exchange: ExchangeRef => "exchange",
        expected_raw_json: RawJson => "expectedRawJson",
        id: FixtureAlias => "id",
    },
    LegacyOpen => "legacy-open" {
        exchange: ExchangeRef => "exchange",
        expected_raw_json: RawJson => "expectedRawJson",
        id: FixtureAlias => "id",
        source_provenance: ExpectedServerCheckLegacyOpenSourceProvenance => "sourceProvenance",
    },
    CaptureUnavailable => "capture-unavailable" {
        binding: FixtureAlias => "binding",
        checkpoint: FixtureAlias => "checkpoint",
        exchange: ExchangeRef => "exchange",
        id: FixtureAlias => "id",
        reason: ExpectedServerCheckCaptureUnavailableReason => "reason",
    },
    CooperatingLockOrder => "cooperating-lock-order" {
        actors: Items<LockActor, 1, 8192> => "actors",
        id: FixtureAlias => "id",
        order: Items<ExpectedServerCheckCooperatingLockOrderOrderItem, 1, 8192> => "order",
        required_events: Items<LockEventRef, 1, 8192> => "requiredEvents",
        scope: ExpectedServerCheckCooperatingLockOrderScope => "scope",
    },
    LegacyOpenSelected => "legacy-open-selected" {
        binding: FixtureAlias => "binding",
        content: ExpectedServerCheckLegacyOpenSelectedContent => "content",
        descriptor: ExpectedServerCheckLegacyOpenSelectedDescriptor => "descriptor",
        exchange: ExchangeRef => "exchange",
        id: FixtureAlias => "id",
        source_provenance: ExpectedServerCheckLegacyOpenSelectedSourceProvenance => "sourceProvenance",
    },
    ProducerMessageBoundary => "producer-message-boundary" {
        boundary: ExpectedServerCheckProducerMessageBoundaryBoundary => "boundary",
        byte_length: Count => "byteLength",
        connection: FixtureAlias => "connection",
        expected_bytes: FixtureAlias => "expectedBytes",
        id: FixtureAlias => "id",
        probe: FixtureAlias => "probe",
        sha256: ContentSha256 => "sha256",
        truncated: ExpectedServerCheckProducerMessageBoundaryTruncated => "truncated",
    },
} }

tagged! { ExpectedStreamTarget("kind") {
    Original => "original" {
        path: SourcePath => "path",
    },
    SemanticProjection => "semantic-projection" {

    },
} }

tagged! { ExpectedTraceEventPendingInput("kind") {
    ScenarioInvocation => "scenario-invocation" {

    },
    ExactJson => "exact-json" {
        expected_raw_json: RawJson => "expectedRawJson",
    },
} }

words! { ExpectedTraceEventPendingPort {
    Promise => "promise",
    PickerReceiveCallback => "picker-receive-callback",
} }

words! { ExpectedTraceEventPromiseRejectedErrorName {
    Error => "Error",
    TypeError => "TypeError",
    AbortError => "AbortError",
} }

record! { ExpectedTraceEventPromiseRejectedError {
        message: Text<0, 512> => "message",
        name: ExpectedTraceEventPromiseRejectedErrorName => "name",
} }

words! { ExpectedTraceEventLateSignalDisposition {
    RetiredCallback => "ignored-by-retired-callback",
    ConsumedCallback => "ignored-by-consumed-callback",
    SettledPort => "ignored-by-settled-port",
} }

words! { ExpectedTraceEventPublicationDispositionDisposition {
    ForwardedByCurrentnessGuard => "forwarded-by-currentness-guard",
    IgnoredByCurrentnessGuard => "ignored-by-currentness-guard",
} }

words! { ExpectedTraceEventHeldResultRetiredDisposition {
    DeliveredToProductionPort => "delivered-to-production-port",
    DiscardedAfterProductionGuard => "discarded-after-production-guard",
    DiscardedOnOwnedTeardown => "discarded-on-owned-teardown",
} }

words! { ExpectedTraceEventWorkStartedOwner {
    ActualWorker => "actual-worker",
    InlineProductionInvocation => "inline-production-invocation",
} }

tagged! { ExpectedTraceEvent("kind") {
    Pending => "pending" {
        effect: EffectRef => "effect",
        input: ExpectedTraceEventPendingInput => "input",
        port: ExpectedTraceEventPendingPort => "port",
    },
    PickerInputSignal => "picker-input-signal" {
        effect: EffectRef => "effect",
        signal: PickerSignal => "signal",
    },
    CancellationRequested => "cancellation-requested" {
        action_index: Count => "actionIndex",
        cause: CancellationCause => "cause",
        effect: EffectRef => "effect",
    },
    PreparedCoreResult => "prepared-core-result" {
        bytes: NumberRequirement => "bytes",
        effect: EffectRef => "effect",
        work: FixtureAlias => "work",
    },
    PromiseResolved => "promise-resolved" {
        effect: EffectRef => "effect",
        reply: ExpectedPortReply => "reply",
    },
    PromiseRejected => "promise-rejected" {
        effect: EffectRef => "effect",
        error: ExpectedTraceEventPromiseRejectedError => "error",
    },
    CallbackDelivered => "callback-delivered" {
        effect: EffectRef => "effect",
        reply: ExpectedPortReply => "reply",
    },
    CallbackRetired => "callback-retired" {
        action_index: Count => "actionIndex",
        cause: CancellationCause => "cause",
        effect: EffectRef => "effect",
    },
    LateSignal => "late-signal" {
        causal_source: LateSignalSource => "causalSource",
        disposition: ExpectedTraceEventLateSignalDisposition => "disposition",
        effect: EffectRef => "effect",
        signal: ExpectedPortReply => "signal",
    },
    PublicationDisposition => "publication-disposition" {
        disposition: ExpectedTraceEventPublicationDispositionDisposition => "disposition",
        effect: EffectRef => "effect",
    },
    HeldResultRetired => "held-result-retired" {
        bytes: NumberRequirement => "bytes",
        disposition: ExpectedTraceEventHeldResultRetiredDisposition => "disposition",
        effect: EffectRef => "effect",
    },
    WorkStarted => "work-started" {
        effect: EffectRef => "effect",
        owner: ExpectedTraceEventWorkStartedOwner => "owner",
        work: FixtureAlias => "work",
    },
    WorkExited => "work-exited" {
        effect: EffectRef => "effect",
        work: FixtureAlias => "work",
    },
} }

words! { ExpectedWorkflowModelOriginalsServerOutcomeIntentionallyRetainedUncertainPhase {
    Unknown => "unknown",
    Disconnected => "disconnected",
} }

words! { ExpectedWorkflowModelOriginalsServerOutcomeIntentionallyRetainedUncertainReason {
    SubmissionStatusUnknown => "submission-status-unknown",
    TransportDisconnected => "transport-disconnected",
} }

tagged! { ExpectedWorkflowModelOriginalsServerOutcome("kind") {
    Clean => "clean" {
        final_checkpoint: FixtureAlias => "finalCheckpoint",
    },
    IntentionallyRetainedUncertain => "intentionally-retained-uncertain" {
        execution: FixtureAlias => "execution",
        final_checkpoint: FixtureAlias => "finalCheckpoint",
        model: FixtureAlias => "model",
        phase: ExpectedWorkflowModelOriginalsServerOutcomeIntentionallyRetainedUncertainPhase => "phase",
        reason: ExpectedWorkflowModelOriginalsServerOutcomeIntentionallyRetainedUncertainReason => "reason",
    },
} }

record! { ExpectedWorkflowModelOriginalsServerQualificationBlockedObligationsItem {
        id: FixtureAlias => "id",
        reason: Text<0, 16384> => "reason",
} }

tagged! { ExpectedWorkflowModelOriginalsServerQualification("kind") {
    ComparisonReady => "comparison-ready" {

    },
    Blocked => "blocked" {
        obligations: Items<ExpectedWorkflowModelOriginalsServerQualificationBlockedObligationsItem, 1, 8192> => "obligations",
    },
} }

record! { ExpectedWorkflowModelOriginalsServerRichSourcesItem {
        alias: FixtureAlias => "alias",
        source_bytes: FixtureAlias => "sourceBytes",
        value: ExpectedRichValue => "value",
} }

literal! { ExpectedWorkflowModelOriginalsServerTeardownHeldCoreResults => 0 }

literal! { ExpectedWorkflowModelOriginalsServerTeardownKind => "confirmed" }

literal! { ExpectedWorkflowModelOriginalsServerTeardownPendingCallbackRegistrations => 0 }

literal! { ExpectedWorkflowModelOriginalsServerTeardownPendingPromisePorts => 0 }

literal! { ExpectedWorkflowModelOriginalsServerTeardownProductReleaseInferred => false }

literal! { ExpectedWorkflowModelOriginalsServerTeardownStillOwnedWork => 0 }

record! { ExpectedWorkflowModelOriginalsServerTeardown {
        held_core_results: ExpectedWorkflowModelOriginalsServerTeardownHeldCoreResults => "heldCoreResults",
        kind: ExpectedWorkflowModelOriginalsServerTeardownKind => "kind",
        pending_callback_registrations: ExpectedWorkflowModelOriginalsServerTeardownPendingCallbackRegistrations => "pendingCallbackRegistrations",
        pending_promise_ports: ExpectedWorkflowModelOriginalsServerTeardownPendingPromisePorts => "pendingPromisePorts",
        product_release_inferred: ExpectedWorkflowModelOriginalsServerTeardownProductReleaseInferred => "productReleaseInferred",
        still_owned_work: ExpectedWorkflowModelOriginalsServerTeardownStillOwnedWork => "stillOwnedWork",
} }

record! { ExpectedWorkflowModelOriginalsServerTraceSourcesItem {
        alias: FixtureAlias => "alias",
        events: Items<ExpectedTraceEvent, 0, 8192> => "events",
} }

literal! { ExpectedWorkflowModelOriginalsServerVersion => "author-candidate-17" }

words! { ExpectedWorkflowModelOriginalsClientOutcomeIntentionallyRetainedUncertainPhase {
    Unknown => "unknown",
    Disconnected => "disconnected",
} }

words! { ExpectedWorkflowModelOriginalsClientOutcomeIntentionallyRetainedUncertainReason {
    SubmissionStatusUnknown => "submission-status-unknown",
    TransportDisconnected => "transport-disconnected",
} }

tagged! { ExpectedWorkflowModelOriginalsClientOutcome("kind") {
    Clean => "clean" {
        final_checkpoint: FixtureAlias => "finalCheckpoint",
    },
    IntentionallyRetainedUncertain => "intentionally-retained-uncertain" {
        execution: FixtureAlias => "execution",
        final_checkpoint: FixtureAlias => "finalCheckpoint",
        model: FixtureAlias => "model",
        phase: ExpectedWorkflowModelOriginalsClientOutcomeIntentionallyRetainedUncertainPhase => "phase",
        reason: ExpectedWorkflowModelOriginalsClientOutcomeIntentionallyRetainedUncertainReason => "reason",
    },
} }

record! { ExpectedWorkflowModelOriginalsClientQualificationBlockedObligationsItem {
        id: FixtureAlias => "id",
        reason: Text<0, 16384> => "reason",
} }

tagged! { ExpectedWorkflowModelOriginalsClientQualification("kind") {
    ComparisonReady => "comparison-ready" {

    },
    Blocked => "blocked" {
        obligations: Items<ExpectedWorkflowModelOriginalsClientQualificationBlockedObligationsItem, 1, 8192> => "obligations",
    },
} }

record! { ExpectedWorkflowModelOriginalsClientRichSourcesItem {
        alias: FixtureAlias => "alias",
        source_bytes: FixtureAlias => "sourceBytes",
        value: ExpectedRichValue => "value",
} }

literal! { ExpectedWorkflowModelOriginalsClientTeardownHeldCoreResults => 0 }

literal! { ExpectedWorkflowModelOriginalsClientTeardownKind => "confirmed" }

literal! { ExpectedWorkflowModelOriginalsClientTeardownPendingCallbackRegistrations => 0 }

literal! { ExpectedWorkflowModelOriginalsClientTeardownPendingPromisePorts => 0 }

literal! { ExpectedWorkflowModelOriginalsClientTeardownProductReleaseInferred => false }

literal! { ExpectedWorkflowModelOriginalsClientTeardownStillOwnedWork => 0 }

record! { ExpectedWorkflowModelOriginalsClientTeardown {
        held_core_results: ExpectedWorkflowModelOriginalsClientTeardownHeldCoreResults => "heldCoreResults",
        kind: ExpectedWorkflowModelOriginalsClientTeardownKind => "kind",
        pending_callback_registrations: ExpectedWorkflowModelOriginalsClientTeardownPendingCallbackRegistrations => "pendingCallbackRegistrations",
        pending_promise_ports: ExpectedWorkflowModelOriginalsClientTeardownPendingPromisePorts => "pendingPromisePorts",
        product_release_inferred: ExpectedWorkflowModelOriginalsClientTeardownProductReleaseInferred => "productReleaseInferred",
        still_owned_work: ExpectedWorkflowModelOriginalsClientTeardownStillOwnedWork => "stillOwnedWork",
} }

record! { ExpectedWorkflowModelOriginalsClientTraceSourcesItem {
        alias: FixtureAlias => "alias",
        events: Items<ExpectedTraceEvent, 0, 8192> => "events",
} }

literal! { ExpectedWorkflowModelOriginalsClientVersion => "author-candidate-17" }

tagged! { ExpectedWorkflow("role") {
    ModelOriginalsServer => "model-originals-server" {
        bindings: Items<ExpectedBinding, 0, 8192> => "bindings",
        byte_sources: Items<ExpectedByteSource, 0, 4096> => "byteSources",
        checks: Items<ExpectedServerCheck, 1, 8192> => "checks",
        commentary: Items<Text<0, 16384>, 0, 8192> => "commentary",
        lineage: Items<ExpectedLineage, 0, 100000> => "lineage",
        origin: PacketRef => "origin",
        outcome: ExpectedWorkflowModelOriginalsServerOutcome => "outcome",
        qualification: ExpectedWorkflowModelOriginalsServerQualification => "qualification",
        rich_sources: Items<ExpectedWorkflowModelOriginalsServerRichSourcesItem, 0, 256> => "richSources",
        run_index: Natural<0, 1> => "runIndex",
        teardown: ExpectedWorkflowModelOriginalsServerTeardown => "teardown",
        trace_sources: Items<ExpectedWorkflowModelOriginalsServerTraceSourcesItem, 0, 8192> => "traceSources",
        version: ExpectedWorkflowModelOriginalsServerVersion => "version",
    },
    ModelOriginalsClient => "model-originals-client" {
        bindings: Items<ExpectedBinding, 0, 8192> => "bindings",
        byte_sources: Items<ExpectedByteSource, 0, 4096> => "byteSources",
        checks: Items<ExpectedClientCheck, 1, 8192> => "checks",
        commentary: Items<Text<0, 16384>, 0, 8192> => "commentary",
        lineage: Items<ExpectedLineage, 0, 100000> => "lineage",
        origin: PacketRef => "origin",
        outcome: ExpectedWorkflowModelOriginalsClientOutcome => "outcome",
        qualification: ExpectedWorkflowModelOriginalsClientQualification => "qualification",
        rich_sources: Items<ExpectedWorkflowModelOriginalsClientRichSourcesItem, 0, 256> => "richSources",
        run_index: Natural<0, 1> => "runIndex",
        teardown: ExpectedWorkflowModelOriginalsClientTeardown => "teardown",
        trace_sources: Items<ExpectedWorkflowModelOriginalsClientTraceSourcesItem, 0, 8192> => "traceSources",
        version: ExpectedWorkflowModelOriginalsClientVersion => "version",
    },
} }

words! { LateSignalSourceActualSelectionValidationReason {
    InvalidName => "invalid-name",
    UnsupportedCodec => "unsupported-codec",
    Oversized => "oversized",
} }

tagged! { LateSignalSource("kind") {
    FileReadCompletion => "actual-file-read-completion" {
        effect: EffectRef => "effect",
    },
    HeldWorkerResult => "actual-held-worker-result" {

    },
    PickerCancelEvent => "actual-picker-cancel-event" {

    },
    EmptySelectionEvent => "actual-empty-selection-event" {

    },
    SelectionValidation => "actual-selection-validation" {
        reason: LateSignalSourceActualSelectionValidationReason => "reason",
    },
} }

tagged! { LockActor("kind") {
    Capture => "capture" {
        alias: FixtureAlias => "alias",
        attempt: FixtureAlias => "attempt",
        pending: FixtureAlias => "pending",
    },
    CooperatingWriter => "cooperating-writer" {
        alias: FixtureAlias => "alias",
        writer: FixtureAlias => "writer",
    },
} }

words! { LockEventRefCaptureEvent {
    SharedLockRequested => "shared-lock-requested",
    SharedLockWaiting => "shared-lock-waiting",
    SharedLockAcquired => "shared-lock-acquired",
    RawRecordCopied => "raw-record-copied",
    SelectedBytesAndDescriptorCopied => "selected-bytes-and-descriptor-copied",
    SharedLockReleased => "shared-lock-released",
    CapturePromiseSettled => "capture-promise-settled",
    CaptureWorkExited => "capture-work-exited",
} }

words! { LockEventRefCooperatingWriterEvent {
    ExclusiveLockRequested => "exclusive-lock-requested",
    ExclusiveLockWaiting => "exclusive-lock-waiting",
    ExclusiveLockAcquired => "exclusive-lock-acquired",
    RecordPublished => "record-published",
    ExclusiveLockReleased => "exclusive-lock-released",
    WriterPromiseSettled => "writer-promise-settled",
    WriterWorkExited => "writer-work-exited",
} }

tagged! { LockEventRef("kind") {
    Capture => "capture" {
        actor: FixtureAlias => "actor",
        event: LockEventRefCaptureEvent => "event",
        occurrence: Natural<0, 8191> => "occurrence",
    },
    CooperatingWriter => "cooperating-writer" {
        actor: FixtureAlias => "actor",
        event: LockEventRefCooperatingWriterEvent => "event",
        occurrence: Natural<0, 8191> => "occurrence",
    },
} }

words! { ModelCodec {
    MorphirJson => "morphir-json",
    IonText => "ion-text",
    IonBinary => "ion-binary",
} }

tagged! { NumberRequirement("kind") {
    Exact => "exact" {
        value: Count => "value",
    },
    AtMost => "at-most" {
        value: Count => "value",
    },
    Positive => "positive" {
        maximum: Natural<1, 9007199254740991> => "maximum",
    },
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

tagged! { Root("kind") {
    File => "file" {
        path: SourcePath => "path",
    },
    Directory => "directory" {
        path: SourcePath => "path",
    },
} }

record! { SourceExpectation {
        companion_roots: Items<Root, 0, 63> => "companionRoots",
        primary_root: Root => "primaryRoot",
        source_header: SourceHeader => "sourceHeader",
} }

tagged! { SourceHeader("kind") {
    Reported => "reported" {
        release: Text<0, 128> => "release",
    },
    NotReported => "not-reported" {

    },
} }

tagged! { TypedAdoption("kind") {
    NotAdopted => "not-adopted" {

    },
    Adopted => "adopted" {
        model: FixtureAlias => "model",
    },
} }

pub(super) type U8 = Natural<0, 255>;
