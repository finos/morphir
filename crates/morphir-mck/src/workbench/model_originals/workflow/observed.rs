//! Independent observed evidence types from frozen1b94, not expected predicates.
//! Exact reused input types were checked through their whole reference closure.
//! No authority/runtime/semantic lineage follows from decoding this evidence.
use super::*;

record! { BytesWitness {
        byte_length: Natural<0, 134217728> => "byteLength",
        bytes: super::input::Bytes => "bytes",
        sha256: ContentSha256 => "sha256",
} }

words! { CancellationCause {
    CancelOpening => "cancel-opening",
    CloseCurrentModel => "close-current-model",
    CloseModel => "close-model",
    Replacement => "replacement",
    Teardown => "teardown",
} }

tagged! { CaptureCleanupOwnConnectionClosedCapture("kind") {
    Unknown => "unknown" {

    },
    Known => "known" {
        capture: FixtureAlias => "capture",
    },
} }

tagged! { CaptureCleanup("kind") {
    None => "none" {

    },
    ReleaseConfirmed => "release-confirmed" {
        capture: FixtureAlias => "capture",
        connection: FixtureAlias => "connection",
        request_id: U64Token => "requestId",
    },
    OwnConnectionClosed => "own-connection-closed" {
        attempt: FixtureAlias => "attempt",
        capture: CaptureCleanupOwnConnectionClosedCapture => "capture",
        connection: FixtureAlias => "connection",
    },
} }

literal! { CaptureCoverageCompleteDeclaration => "0.1.0-draft.1" }

tagged! { CaptureCoverage("kind") {
    Primary => "primary" {

    },
    Complete => "complete" {
        declaration: CaptureCoverageCompleteDeclaration => "declaration",
    },
} }

tagged! { CaptureStateClosedCleanup("kind") {
    None => "none" {

    },
    WorkerOwned => "worker-owned" {
        attempt: FixtureAlias => "attempt",
        worker: FixtureAlias => "worker",
    },
} }

tagged! { CaptureState("kind") {
    Empty => "empty" {

    },
    Capturing => "capturing" {
        attempt: FixtureAlias => "attempt",
        worker: FixtureAlias => "worker",
    },
    PreparedPrivate => "prepared-private" {
        attempt: FixtureAlias => "attempt",
        worker: FixtureAlias => "worker",
    },
    Ready => "ready" {
        capture: FixtureAlias => "capture",
        connection: FixtureAlias => "connection",
    },
    Released => "released" {
        connection: FixtureAlias => "connection",
        last_capture: FixtureAlias => "lastCapture",
    },
    Closed => "closed" {
        cleanup: CaptureStateClosedCleanup => "cleanup",
    },
} }

record! { CapturedEvidence {
        capture: FixtureAlias => "capture",
        coverage: CaptureCoverage => "coverage",
        inventory: InventoryEvidence => "inventory",
        projection: ProjectionWitness => "projection",
        source: SourceRoles => "source",
} }

pub(super) type ClientCheckpointCurrentModel = Nullable<FixtureAlias>;

pub(super) type ClientCheckpointCurrentOpening = Nullable<FixtureAlias>;

pub(super) type ClientCheckpointNavigationInspectionOwner = Nullable<FixtureAlias>;

pub(super) type ClientCheckpointNavigationOutputOwner = Nullable<FixtureAlias>;

pub(super) type ClientCheckpointNavigationSearchOwner = Nullable<FixtureAlias>;

record! { ClientCheckpointNavigation {
        destination_count: super::input::Count => "destinationCount",
        inspection_owner: ClientCheckpointNavigationInspectionOwner => "inspectionOwner",
        output_owner: ClientCheckpointNavigationOutputOwner => "outputOwner",
        search_owner: ClientCheckpointNavigationSearchOwner => "searchOwner",
} }

record! { ClientCheckpoint {
        capture_cleanup: CaptureCleanup => "captureCleanup",
        current_model: ClientCheckpointCurrentModel => "currentModel",
        current_opening: ClientCheckpointCurrentOpening => "currentOpening",
        event_count: Natural<0, 8192> => "eventCount",
        execution_owner: ExecutionOwner => "executionOwner",
        held_core_result_bytes: super::input::Count => "heldCoreResultBytes",
        name: FixtureAlias => "name",
        navigation: ClientCheckpointNavigation => "navigation",
        owner: OwnerEvidence => "owner",
        pending_effects: Items<EffectRef, 0, 8192> => "pendingEffects",
        prepared_core_effects: Items<EffectRef, 0, 8192> => "preparedCoreEffects",
} }

tagged! { EffectInput("kind") {
    None => "none" {

    },
    OutboundFrame => "outbound-frame" {
        index: Natural<0, 8191> => "index",
    },
    Bytes => "bytes" {
        value: BytesWitness => "value",
    },
    Json => "json" {
        source: super::input::RawJsonSource => "source",
    },
    Text => "text" {
        source: super::input::Frame => "source",
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
} }

words! { EffectRecordPendingPort {
    Promise => "promise",
    PickerReceiveCallback => "picker-receive-callback",
} }

words! { EffectRecordLateSignalDisposition {
    RetiredCallback => "ignored-by-retired-callback",
    ConsumedCallback => "ignored-by-consumed-callback",
    SettledPort => "ignored-by-settled-port",
} }

pub(super) type EffectRecordPublicationDispositionActualOpeningOwner = Nullable<FixtureAlias>;

words! { EffectRecordPublicationDispositionDisposition {
    ForwardedByCurrentnessGuard => "forwarded-by-currentness-guard",
    IgnoredByCurrentnessGuard => "ignored-by-currentness-guard",
} }

words! { EffectRecordHeldResultRetiredDisposition {
    DeliveredToProductionPort => "delivered-to-production-port",
    DiscardedAfterProductionGuard => "discarded-after-production-guard",
    DiscardedOnOwnedTeardown => "discarded-on-owned-teardown",
} }

tagged! { EffectRecord("kind") {
    Pending => "pending" {
        effect: EffectRef => "effect",
        input: EffectInput => "input",
        port: EffectRecordPendingPort => "port",
    },
    PickerInputSignal => "picker-input-signal" {
        effect: EffectRef => "effect",
        signal: super::input::PickerSignal => "signal",
    },
    CancellationRequested => "cancellation-requested" {
        action_index: super::input::Count => "actionIndex",
        cause: CancellationCause => "cause",
        effect: EffectRef => "effect",
    },
    WorkStarted => "work-started" {
        effect: EffectRef => "effect",
        owner: WorkOwner => "owner",
        work: FixtureAlias => "work",
    },
    WorkExited => "work-exited" {
        effect: EffectRef => "effect",
        work: FixtureAlias => "work",
    },
    PreparedCoreResult => "prepared-core-result" {
        actual_result_byte_length: super::input::Count => "actualResultByteLength",
        effect: EffectRef => "effect",
        raw_reply: super::input::Frame => "rawReply",
        work: FixtureAlias => "work",
    },
    PromiseResolved => "promise-resolved" {
        effect: EffectRef => "effect",
        reply: super::input::DeliveredReply => "reply",
    },
    PromiseRejected => "promise-rejected" {
        effect: EffectRef => "effect",
        error: super::input::RejectedEffect => "error",
    },
    CallbackDelivered => "callback-delivered" {
        actual_raw_callback_argument: super::input::Frame => "actualRawCallbackArgument",
        effect: EffectRef => "effect",
    },
    CallbackRetired => "callback-retired" {
        action_index: super::input::Count => "actionIndex",
        cause: CancellationCause => "cause",
        effect: EffectRef => "effect",
    },
    LateSignal => "late-signal" {
        actual_signal: super::input::DeliveredReply => "actualSignal",
        causal_source: LateSignalSource => "causalSource",
        disposition: EffectRecordLateSignalDisposition => "disposition",
        effect: EffectRef => "effect",
    },
    PublicationDisposition => "publication-disposition" {
        actual_opening_owner: EffectRecordPublicationDispositionActualOpeningOwner => "actualOpeningOwner",
        disposition: EffectRecordPublicationDispositionDisposition => "disposition",
        effect: EffectRef => "effect",
    },
    HeldResultRetired => "held-result-retired" {
        byte_length: super::input::Count => "byteLength",
        disposition: EffectRecordHeldResultRetiredDisposition => "disposition",
        effect: EffectRef => "effect",
    },
} }

record! { EffectRef {
        attempt: FixtureAlias => "attempt",
        kind: EffectKind => "kind",
        ordinal: Natural<0, 8191> => "ordinal",
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

record! { SourceRoles {
        companion_roots: Items<Root, 0, 63> => "companionRoots",
        primary_root: Root => "primaryRoot",
        source_format_version: SourceHeader => "sourceFormatVersion",
} }

literal! { HarnessTeardownConfirmedHeldCoreResults => 0 }

literal! { HarnessTeardownConfirmedPendingEffects => 0 }

literal! { HarnessTeardownConfirmedProductReleaseInferred => false }

literal! { HarnessTeardownConfirmedStillOwnedWorkers => 0 }

literal! { HarnessTeardownFailedProductReleaseInferred => false }

words! { HarnessTeardownFailedReason {
    Timeout => "timeout",
    DisposalFailed => "disposal-failed",
} }

tagged! { HarnessTeardown("kind") {
    Confirmed => "confirmed" {
        disposed_transports: super::input::Count => "disposedTransports",
        held_core_results: HarnessTeardownConfirmedHeldCoreResults => "heldCoreResults",
        pending_effects: HarnessTeardownConfirmedPendingEffects => "pendingEffects",
        product_release_inferred: HarnessTeardownConfirmedProductReleaseInferred => "productReleaseInferred",
        still_owned_workers: HarnessTeardownConfirmedStillOwnedWorkers => "stillOwnedWorkers",
        workers_exited: super::input::Count => "workersExited",
        workers_started: super::input::Count => "workersStarted",
    },
    Failed => "failed" {
        held_core_results: super::input::Count => "heldCoreResults",
        pending_effects: super::input::Count => "pendingEffects",
        product_release_inferred: HarnessTeardownFailedProductReleaseInferred => "productReleaseInferred",
        reason: HarnessTeardownFailedReason => "reason",
        still_owned_workers: super::input::Count => "stillOwnedWorkers",
    },
} }

record! { InventoryEvidence {
        directory_count: Natural<0, 100064> => "directoryCount",
        entry_count: Natural<0, 100064> => "entryCount",
        file_count: Natural<0, 100064> => "fileCount",
        sha256: ContentSha256 => "sha256",
        source_byte_length: Natural<0, 67108864> => "sourceByteLength",
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

record! { MeasuredTranscriptExchangesItem {
        reply: super::input::Frame => "reply",
        request: super::input::Frame => "request",
} }

record! { MeasuredTranscript {
        exchanges: Items<MeasuredTranscriptExchangesItem, 0, 8192> => "exchanges",
} }

tagged! { Observation("role") {
    ModelOriginalsServer => "model-originals-server" {
        captures: Items<CapturedEvidence, 0, 8192> => "captures",
        checkpoints: Items<ServerCheckpoint, 1, 8192> => "checkpoints",
        outcome: ScenarioOutcome => "outcome",
        teardown: HarnessTeardown => "teardown",
        transcript: MeasuredTranscript => "transcript",
    },
    ModelOriginalsClient => "model-originals-client" {
        checkpoints: Items<ClientCheckpoint, 1, 8192> => "checkpoints",
        core_results: Items<ProducedCoreResult, 0, 8192> => "coreResults",
        downloads: Items<BytesWitness, 0, 256> => "downloads",
        effects: Items<EffectRecord, 0, 8192> => "effects",
        outbound: Items<super::input::Frame, 0, 8192> => "outbound",
        outcome: ScenarioOutcome => "outcome",
        rich_owners: Items<RichOwnerEvidence, 0, 256> => "richOwners",
        teardown: HarnessTeardown => "teardown",
    },
} }

tagged! { OfferEvidence("kind") {
    Held => "held" {
        provider: FixtureAlias => "provider",
        registration: FixtureAlias => "registration",
    },
    Revoked => "revoked" {
        provider: FixtureAlias => "provider",
        registration: FixtureAlias => "registration",
    },
    Replaced => "replaced" {
        current_registration: FixtureAlias => "currentRegistration",
        previous_registration: FixtureAlias => "previousRegistration",
        provider: FixtureAlias => "provider",
    },
} }

words! { OwnerEvidenceSemanticOnlyReason {
    OriginalsNotProvided => "originals-not-provided",
    GeneratedModel => "generated-model",
} }

tagged! { OwnerEvidence("kind") {
    None => "none" {

    },
    VerifiedOriginalFile => "verified-original-file" {
        adoption: TypedAdoption => "adoption",
        codec: super::input::ModelCodec => "codec",
        filename: Text<0, 4096> => "filename",
        opening: FixtureAlias => "opening",
        original: BytesWitness => "original",
    },
    VerifiedOriginalInventory => "verified-original-inventory" {
        adoption: TypedAdoption => "adoption",
        entries: Items<super::input::Entry, 0, 100064> => "entries",
        opening: FixtureAlias => "opening",
        projection: ProjectionWitness => "projection",
        source: SourceRoles => "source",
    },
    SemanticOnly => "semantic-only" {
        model: FixtureAlias => "model",
        reason: OwnerEvidenceSemanticOnlyReason => "reason",
    },
} }

tagged! { ProducedCoreResultModelBinding("kind") {
    None => "none" {

    },
    RetainedOwner => "retained-owner" {
        model: FixtureAlias => "model",
    },
} }

words! { ProducedCoreResultOperation {
    Inspect => "inspect",
    Search => "search",
    ConceptualSpecification => "conceptual-specification",
} }

record! { ProducedCoreResult {
        effect: EffectRef => "effect",
        model_binding: ProducedCoreResultModelBinding => "modelBinding",
        opening: FixtureAlias => "opening",
        operation: ProducedCoreResultOperation => "operation",
        raw_reply: super::input::Frame => "rawReply",
} }

words! { ProjectionWitnessUnavailableReason {
    UnsupportedRepresentation => "unsupported_representation",
    InvalidModel => "invalid_model",
    DecodeLimit => "decode_limit",
    ProjectionLimit => "projection_limit",
    Capacity => "capacity",
    Timeout => "timeout",
} }

tagged! { ProjectionWitness("kind") {
    NotRequested => "not-requested" {

    },
    Unavailable => "unavailable" {
        reason: ProjectionWitnessUnavailableReason => "reason",
    },
    Available => "available" {
        actual_format_version: Text<0, 128> => "actualFormatVersion",
        byte_length: Natural<0, 67108864> => "byteLength",
        sha256: ContentSha256 => "sha256",
    },
} }

record! { ResourceEvidence {
        active_workers: Natural<0, 1> => "activeWorkers",
        metadata_bytes: Natural<0, 67108864> => "metadataBytes",
        projection_bytes: Natural<0, 134217728> => "projectionBytes",
        record_bytes: Natural<0, 67108864> => "recordBytes",
        slots: Natural<0, 64> => "slots",
        source_bytes: Natural<0, 134217728> => "sourceBytes",
} }

tagged! { RichOwnerEvidence("kind") {
    GraphFree => "graph-free" {
        actual_carrier: super::input::Frame => "actualCarrier",
        model: FixtureAlias => "model",
    },
    Rich => "rich" {
        actual_carrier: super::input::Frame => "actualCarrier",
        actual_graph: super::input::Frame => "actualGraph",
        actual_provenance: super::input::Frame => "actualProvenance",
        model: FixtureAlias => "model",
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

words! { ScenarioOutcomeIntentionallyRetainedUncertainCleanupReason {
    SubmissionStatusUnknown => "submission-status-unknown",
    TransportDisconnected => "transport-disconnected",
} }

words! { ScenarioOutcomeIntentionallyRetainedUncertainPhase {
    Unknown => "unknown",
    Disconnected => "disconnected",
} }

tagged! { ScenarioOutcome("kind") {
    Clean => "clean" {
        final_checkpoint: FixtureAlias => "finalCheckpoint",
    },
    IntentionallyRetainedUncertain => "intentionally-retained-uncertain" {
        cleanup_reason: ScenarioOutcomeIntentionallyRetainedUncertainCleanupReason => "cleanupReason",
        execution: FixtureAlias => "execution",
        final_checkpoint: FixtureAlias => "finalCheckpoint",
        model: FixtureAlias => "model",
        phase: ScenarioOutcomeIntentionallyRetainedUncertainPhase => "phase",
    },
} }

record! { ServerCheckpointWorkers {
        exited: super::input::Count => "exited",
        late_publications: super::input::Count => "latePublications",
        started: super::input::Count => "started",
        still_owned: super::input::Count => "stillOwned",
} }

record! { ServerCheckpoint {
        connection: FixtureAlias => "connection",
        effects: SourceEffects => "effects",
        name: FixtureAlias => "name",
        offer: OfferEvidence => "offer",
        resources: ResourceEvidence => "resources",
        state: CaptureState => "state",
        workers: ServerCheckpointWorkers => "workers",
} }

record! { SourceEffects {
        compile_calls: super::input::Count => "compileCalls",
        discovery: super::input::Count => "discovery",
        legacy_open_calls: super::input::Count => "legacyOpenCalls",
        output_resolution: super::input::Count => "outputResolution",
        project_resolution: super::input::Count => "projectResolution",
        projection_attempts: super::input::Count => "projectionAttempts",
        record_reads: super::input::Count => "recordReads",
        source_bytes: super::input::Count => "sourceBytes",
        source_reads: super::input::Count => "sourceReads",
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

tagged! { WorkOwner("kind") {
    InlineProductionInvocation => "inline-production-invocation" {

    },
    ActualWorker => "actual-worker" {
        worker: FixtureAlias => "worker",
    },
} }
